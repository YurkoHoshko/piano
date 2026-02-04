defmodule Piano.Background.TaskWarrior do
  @moduledoc """
  TaskWarrior integration for background task processing.

  Checks for tasks with +background tag and schedules Piano interactions
  to complete them.

  ## TaskWarrior Task Format

  Tasks should be created with the `+background` tag and the description
  should contain the goal/prompt for the AI agent:

      task add +background "Fix the login bug in auth.ex"

  To notify a user when done, add surface annotation:

      task add +background "Generate report" && task <id> annotate surface:telegram:123:456

  ## Processing Flow

  1. Quantum scheduler calls `process_background_tasks/0` every minute
  2. List all pending tasks with +background tag
  3. For each task:
     - Mark as in-progress (started)
     - Create a MockSurface for result collection
     - Schedule an interaction with the task description as the prompt
     - Wait for completion
     - Send results to original surface (if specified)
     - Mark task as done
  """

  require Logger

  alias Piano.Mock.Surface, as: MockSurface
  alias Piano.Telegram.Surface, as: TelegramSurface

  @doc """
  Called every minute by Quantum scheduler.
  Finds pending background tasks and processes them.
  """
  @spec process_background_tasks() :: :ok
  def process_background_tasks do
    if taskwarrior_available?() do
      case list_background_tasks() do
        {:ok, tasks} when is_list(tasks) ->
          Enum.each(tasks, &process_task/1)

        {:error, reason} ->
          Logger.warning("Failed to list background tasks: #{inspect(reason)}")
      end
    else
      Logger.debug("TaskWarrior not available, skipping background task check")
    end

    :ok
  end

  @doc """
  Schedule a background task with surface notification.

  Creates a taskwarrior task with +background tag and stores the reply_to
  surface in annotations so results can be sent back to the user.

  ## Examples

      schedule_task("Generate monthly report", "telegram:123:456")
      schedule_task("Check server status", "telegram:123:456", due: "in 1 hour")
  """
  @spec schedule_task(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def schedule_task(description, reply_to, opts \\ []) do
    due = Keyword.get(opts, :due)

    args =
      ["add", "+background", description] ++
        if(due, do: ["due:#{due}"], else: [])

    case System.cmd("task", args ++ ["rc.confirmation=off"], stderr_to_stdout: true) do
      {output, 0} ->
        case extract_task_id(output) do
          {:ok, task_id} ->
            add_surface_annotation(task_id, reply_to)
            {:ok, task_id}

          :error ->
            {:error, :failed_to_extract_id}
        end

      {output, _} ->
        {:error, output}
    end
  end

  @doc """
  Check if taskwarrior is installed and available.
  """
  @spec taskwarrior_available?() :: boolean()
  def taskwarrior_available? do
    case System.cmd("which", ["task"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  List all taskwarrior tasks with +background tag that are pending.
  """
  @spec list_background_tasks() :: {:ok, [map()]} | {:error, term()}
  def list_background_tasks do
    case System.cmd("task", ["+background", "status:pending", "export"], stderr_to_stdout: true) do
      {output, 0} ->
        json_output = extract_json(output)

        case Jason.decode(json_output) do
          {:ok, tasks} -> {:ok, tasks}
          {:error, _} -> {:ok, []}
        end

      {"", _} ->
        {:ok, []}

      {output, _} ->
        {:error, output}
    end
  end

  # Extract JSON array from output that may contain taskwarrior messages
  defp extract_json(output) do
    case Regex.run(~r/\[.*\]/s, output) do
      [json] -> json
      nil -> "[]"
    end
  end

  # Extract task ID from "Created task N." output
  defp extract_task_id(output) do
    case Regex.run(~r/Created task (\d+)\./, output) do
      [_, id] -> {:ok, id}
      nil -> :error
    end
  end

  # Add surface annotation to task
  defp add_surface_annotation(task_id, reply_to) do
    System.cmd("task", [task_id, "annotate", "surface:#{reply_to}", "rc.confirmation=off"],
      stderr_to_stdout: true
    )

    :ok
  end

  # Extract surface from task annotations
  defp extract_surface_from_task(%{"annotations" => annotations}) when is_list(annotations) do
    Enum.find_value(annotations, fn
      %{"description" => "surface:" <> reply_to} -> reply_to
      _ -> nil
    end)
  end

  defp extract_surface_from_task(_), do: nil

  @doc """
  Start processing a single task.
  """
  @spec process_task(map()) :: :ok
  def process_task(%{"uuid" => uuid, "description" => description} = task) do
    Logger.info("Processing background task: #{uuid} - #{description}")

    mark_in_progress(uuid)

    # Check if task has a surface to notify
    notify_surface = extract_surface_from_task(task)

    mock_id = "task-#{uuid}"
    {:ok, _surface} = MockSurface.start(mock_id)

    reply_to = MockSurface.build_reply_to(mock_id)

    case schedule_interaction(description, reply_to) do
      {:ok, interaction_id} ->
        Task.start(fn ->
          wait_for_completion(interaction_id)
          mark_completed(uuid)

          results = MockSurface.get_results(mock_id)
          Logger.info("Task #{uuid} completed with #{length(results)} events")

          # Notify original surface if specified
          if notify_surface do
            notify_task_completion(notify_surface, uuid, description, results)
          end

          MockSurface.stop(mock_id)
        end)

      {:error, reason} ->
        Logger.error("Failed to schedule task #{uuid}: #{inspect(reason)}")
        mark_failed(uuid, reason)

        if notify_surface do
          notify_task_failure(notify_surface, uuid, description, reason)
        end

        MockSurface.stop(mock_id)
    end

    :ok
  end

  def process_task(task) do
    Logger.warning("Invalid task format: #{inspect(task)}")
    :ok
  end

  @doc """
  Mark a task as in-progress in TaskWarrior.
  """
  @spec mark_in_progress(String.t()) :: :ok
  def mark_in_progress(uuid) do
    System.cmd("task", [uuid, "start", "rc.confirmation=off"], stderr_to_stdout: true)
    :ok
  end

  @doc """
  Mark a task as completed in TaskWarrior.
  """
  @spec mark_completed(String.t()) :: :ok
  def mark_completed(uuid) do
    System.cmd("task", [uuid, "done", "rc.confirmation=off"], stderr_to_stdout: true)
    :ok
  end

  @doc """
  Add a failure annotation to a task.
  """
  @spec mark_failed(String.t(), term()) :: :ok
  def mark_failed(uuid, reason) do
    System.cmd(
      "task",
      [uuid, "annotate", "Failed: #{inspect(reason)}", "rc.confirmation=off"],
      stderr_to_stdout: true
    )

    :ok
  end

  defp schedule_interaction(prompt, reply_to) do
    case Piano.Core.Interaction
         |> Ash.Changeset.for_create(:create, %{
           original_message: prompt,
           reply_to: reply_to
         })
         |> Ash.create() do
      {:ok, interaction} ->
        case Piano.Codex.start_turn(interaction) do
          {:ok, _} -> {:ok, interaction.id}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_completion(interaction_id) do
    wait_for_completion(interaction_id, 600)
  end

  defp wait_for_completion(_interaction_id, 0) do
    Logger.warning("Task completion timeout reached")
    :timeout
  end

  defp wait_for_completion(interaction_id, attempts_left) do
    Process.sleep(1_000)

    case Ash.get(Piano.Core.Interaction, interaction_id) do
      {:ok, %{status: status}} when status in [:complete, :failed, :interrupted] ->
        :ok

      {:ok, _} ->
        wait_for_completion(interaction_id, attempts_left - 1)

      {:error, _} ->
        wait_for_completion(interaction_id, attempts_left - 1)
    end
  end

  defp notify_task_completion(reply_to, uuid, description, results) do
    Logger.info("Notifying surface #{reply_to} for task #{uuid}")

    case parse_surface(reply_to) do
      {:ok, surface} ->
        # Extract final message from results if available
        final_message = extract_final_message(results)

        message =
          if final_message do
            "✅ *Task completed*\n\n#{description}\n\n#{final_message}"
          else
            "✅ *Task completed*\n\n#{description}"
          end

        result = Piano.Surface.send_message(surface, message)
        Logger.info("Notification sent to #{reply_to}: #{inspect(result)}")
        result

      {:error, reason} ->
        Logger.warning("Failed to notify surface #{reply_to} for task #{uuid}: #{inspect(reason)}")
    end
  end

  defp notify_task_failure(reply_to, uuid, description, reason) do
    case parse_surface(reply_to) do
      {:ok, surface} ->
        message = "❌ *Task failed*\n\n#{description}\n\nError: #{inspect(reason)}"
        Piano.Surface.send_message(surface, message)

      {:error, err} ->
        Logger.warning("Failed to notify surface #{reply_to} for task #{uuid}: #{inspect(err)}")
    end
  end

  # Parse reply_to into a surface struct for the protocol
  defp parse_surface("telegram:" <> _ = reply_to) do
    TelegramSurface.parse(reply_to)
  end

  defp parse_surface("mock:" <> _ = reply_to) do
    MockSurface.parse(reply_to)
  end

  defp parse_surface(_), do: {:error, :unknown_surface_type}

  defp extract_final_message(results) do
    # Look for the last turn_completed event with agent message
    results
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{type: :turn_completed, data: %{params: params}} ->
        get_in(params, ["response"])

      _ ->
        nil
    end)
  end
end
