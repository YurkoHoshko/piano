defmodule Piano.Codex do
  @moduledoc """
  High-level API for interacting with Codex app-server.

  This module provides functions to start threads, execute turns,
  and handle the event streaming back to surfaces.
  """

  alias Piano.Codex.Client
  alias Piano.Core.{Thread, Interaction, InteractionItem}

  require Logger

  @doc """
  Start a Codex turn for an interaction.

  This function:
  1. Ensures the thread has a codex_thread_id (creates via thread/start if needed)
  2. Starts a turn with the agent's configuration
  3. Streams events, calling Surface.handle_event for each
  4. Creates/updates InteractionItem records
  5. Updates Interaction status on completion

  Returns `{:ok, interaction}` or `{:error, reason}`.
  """
  def start_turn(interaction, opts \\ []) do
    client = Keyword.get(opts, :client, Client)
    surface_module = Keyword.get(opts, :surface_module)

    with {:ok, interaction} <- load_interaction(interaction),
         {:ok, thread} <- ensure_codex_thread(interaction.thread, client),
         {:ok, interaction} <- update_interaction_thread(interaction, thread) do
      with_event_stream(interaction, surface_module, client, fn ->
        with {:ok, turn_id} <- do_start_turn(interaction, thread, client),
             {:ok, interaction} <- mark_interaction_started(interaction, turn_id) do
          {:ok, interaction}
        end
      end)
    end
  end

  @doc """
  Start a new Codex thread.
  """
  def start_thread(client \\ Client) do
    case Client.request(client, "thread/start", %{}) do
      {:ok, %{"threadId" => thread_id}} ->
        {:ok, thread_id}

      {:ok, %{"thread" => %{"id" => thread_id}}} ->
        {:ok, thread_id}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Read effective Codex app-server configuration.
  """
  def read_config(client \\ Client) do
    Client.request(client, "config/read", %{})
  end

  @doc """
  Interrupt an active turn.
  """
  def interrupt_turn(turn_id, client \\ Client) do
    Client.request(client, "turn/interrupt", %{turnId: turn_id})
  end

  @doc """
  Archive a thread.
  """
  def archive_thread(thread_id, client \\ Client) do
    Client.request(client, "thread/archive", %{threadId: thread_id})
  end

  # Private Functions

  defp load_interaction(%Interaction{} = interaction) do
    case Ash.load(interaction, [:thread, :surface, thread: [:agent]]) do
      {:ok, loaded} -> {:ok, loaded}
      {:error, reason} -> {:error, {:load_failed, reason}}
    end
  end

  defp load_interaction(interaction_id) when is_binary(interaction_id) do
    case Ash.get(Interaction, interaction_id) do
      {:ok, interaction} -> load_interaction(interaction)
      {:error, reason} -> {:error, {:not_found, reason}}
    end
  end

  defp ensure_codex_thread(nil, _client) do
    {:error, :no_thread}
  end

  defp ensure_codex_thread(%Thread{codex_thread_id: id} = thread, _client)
       when not is_nil(id) do
    {:ok, thread}
  end

  defp ensure_codex_thread(%Thread{} = thread, client) do
    case start_thread(client) do
      {:ok, codex_thread_id} ->
        Ash.update(thread, %{codex_thread_id: codex_thread_id}, action: :set_codex_thread_id)

      {:error, reason} ->
        {:error, {:thread_start_failed, reason}}
    end
  end

  defp update_interaction_thread(interaction, thread) do
    if interaction.thread_id == thread.id do
      {:ok, %{interaction | thread: thread}}
    else
      case Ash.update(interaction, %{thread_id: thread.id}, action: :assign_thread) do
        {:ok, updated} -> {:ok, %{updated | thread: thread}}
        {:error, reason} -> {:error, {:thread_assign_failed, reason}}
      end
    end
  end

  defp do_start_turn(interaction, thread, client) do
    agent = thread.agent
    input = [%{type: "text", text: interaction.original_message}]

    params = %{
      threadId: thread.codex_thread_id,
      input: input,
      cwd: agent && agent.workspace_path,
      model: agent && agent.model,
      sandboxPolicy: map_sandbox_policy(agent && agent.sandbox_policy, agent && agent.workspace_path)
    }

    params = params |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

    case Client.request(client, "turn/start", params) do
      {:ok, %{"turnId" => turn_id}} ->
        {:ok, turn_id}

      {:ok, %{"turn" => %{"id" => turn_id}}} ->
        {:ok, turn_id}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, {:turn_start_failed, reason}}
    end
  end

  defp mark_interaction_started(interaction, turn_id) do
    Ash.update(interaction, %{codex_turn_id: turn_id}, action: :start)
  end

  defp map_sandbox_policy(:read_only, _cwd), do: %{type: "readOnly", networkAccess: true}
  defp map_sandbox_policy(:workspace_write, cwd) do
    policy = %{type: "workspaceWrite", networkAccess: true}

    if is_binary(cwd) and cwd != "" do
      Map.put(policy, :writableRoots, [cwd])
    else
      policy
    end
  end

  defp map_sandbox_policy(:full_access, _cwd), do: %{type: "dangerFullAccess", networkAccess: true}
  defp map_sandbox_policy(_, _cwd), do: nil

  defp with_event_stream(interaction, surface_module, client, starter_fun) do
    caller = self()
    ref = make_ref()

    approval_handler = fn method, params ->
      handle_approval_request(method, params, interaction, surface_module)
    end

    Client.register_request_handler(client, "commandExecution/approve", approval_handler)
    Client.register_request_handler(client, "fileChange/approve", approval_handler)

    notification_handler = fn method, params ->
      send(caller, {:codex_event, ref, method, params})
    end

    default_handler = fn _method, _params -> :ok end

    Client.register_notification_handler(client, :default, default_handler)

    events = [
      "turn/started",
      "turn/completed",
      "item/started",
      "item/completed",
      "item/agentMessage/delta"
    ]

    Enum.each(events, fn event ->
      Client.register_notification_handler(client, event, notification_handler)
    end)

    try do
      case starter_fun.() do
        {:ok, interaction} ->
          receive_events(ref, interaction, surface_module, %{items: %{}, response: nil})

        {:error, _} = error ->
          error
      end
    after
      Enum.each(events, fn event ->
        Client.unregister_notification_handler(client, event)
      end)

      Client.unregister_notification_handler(client, :default)

      Client.unregister_request_handler(client, "commandExecution/approve")
      Client.unregister_request_handler(client, "fileChange/approve")
    end
  end

  defp receive_events(ref, interaction, surface_module, acc) do
    receive do
      {:codex_event, ^ref, "turn/started", params} ->
        notify_surface(surface_module, interaction, :turn_started, params)
        receive_events(ref, interaction, surface_module, acc)

      {:codex_event, ^ref, "turn/completed", params} ->
        notify_surface(surface_module, interaction, :turn_completed, params)
        acc = handle_turn_completed(params, acc)
        finalize_interaction(interaction, acc)

      {:codex_event, ^ref, "item/started", params} ->
        notify_surface(surface_module, interaction, :item_started, params)
        acc = handle_item_started(params, interaction, acc)
        receive_events(ref, interaction, surface_module, acc)

      {:codex_event, ^ref, "item/completed", params} ->
        notify_surface(surface_module, interaction, :item_completed, params)
        acc = handle_item_completed(params, acc)
        receive_events(ref, interaction, surface_module, acc)

      {:codex_event, ^ref, "item/agentMessage/delta", params} ->
        notify_surface(surface_module, interaction, :agent_message_delta, params)
        acc = handle_message_delta(params, acc)
        receive_events(ref, interaction, surface_module, acc)
    after
      120_000 ->
        Logger.error("Timeout waiting for Codex events")
        Ash.update(interaction, %{response: "Timeout waiting for response"}, action: :fail)
    end
  end

  defp notify_surface(nil, _interaction, _event, _params), do: :ok

  defp notify_surface(surface_module, interaction, event, params) do
    surface = interaction.surface
    surface_module.handle_event(surface, interaction, event, params)
  rescue
    e ->
      Logger.error("Surface.handle_event error: #{inspect(e)}")
      :ok
  end

  defp handle_item_started(params, interaction, acc) do
    item = params["item"] || params
    item_id = item["id"] || item["itemId"]
    type = map_item_type(item["type"] || params["type"])

    case Ash.create(InteractionItem, %{
           codex_item_id: item_id,
           type: type,
           payload: params,
           interaction_id: interaction.id
         }) do
      {:ok, item} ->
        %{acc | items: Map.put(acc.items, item_id, item)}

      {:error, reason} ->
        Logger.error("Failed to create InteractionItem: #{inspect(reason)}")
        acc
    end
  end

  defp handle_item_completed(params, acc) do
    item = params["item"] || params
    item_id = item["id"] || item["itemId"]
    type = map_item_type(item["type"] || params["type"])

    if type == :agent_message do
      Logger.debug("Codex agentMessage item completed: #{inspect(item)}")
    end

    case Map.get(acc.items, item_id) do
      nil ->
        maybe_capture_response(type, item, acc)

      item ->
        case Ash.update(item, %{payload: params}, action: :complete) do
          {:ok, updated} ->
            acc
            |> Map.update!(:items, &Map.put(&1, item_id, updated))
            |> maybe_capture_response(type, item)

          {:error, _reason} ->
            acc
        end
    end
  end

  defp handle_message_delta(params, acc) do
    delta = params["delta"] || get_in(params, ["item", "delta"]) || ""
    current = acc.response || ""
    %{acc | response: current <> delta}
  end

  defp handle_turn_completed(params, acc) do
    turn = params["turn"] || params
    items = turn["items"] || []

    acc =
      Enum.reduce(items, acc, fn item, acc ->
        maybe_capture_response(map_item_type(item["type"]), item, acc)
      end)

    acc
    |> maybe_capture_turn_output(turn)
  end

  defp maybe_capture_turn_output(acc, turn) do
    cond do
      is_binary(turn["output_text"]) and turn["output_text"] != "" ->
        %{acc | response: turn["output_text"]}

      is_list(turn["output"]) ->
        text =
          turn["output"]
          |> Enum.filter(&(&1["type"] == "message"))
          |> Enum.flat_map(&(&1["content"] || []))
          |> Enum.filter(&(&1["type"] == "output_text"))
          |> Enum.map(& &1["text"])
          |> Enum.join("")

        if text != "" do
          %{acc | response: text}
        else
          acc
        end

      true ->
        acc
    end
  end

  defp maybe_capture_response(:agent_message, item, acc) do
    text =
      cond do
        is_binary(item["text"]) -> item["text"]
        is_list(item["content"]) ->
          item["content"]
          |> Enum.filter(fn part -> part["type"] in ["text", "output_text"] end)
          |> Enum.map(& &1["text"])
          |> Enum.join("")
        true ->
          nil
      end

    if is_binary(text) and text != "" do
      %{acc | response: text}
    else
      acc
    end
  end

  defp maybe_capture_response(_type, _item, acc), do: acc

  defp finalize_interaction(interaction, acc) do
    response = acc.response || extract_response_from_items(acc.items)

    case Ash.update(interaction, %{response: response}, action: :complete) do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} -> {:error, {:finalize_failed, reason}}
    end
  end

  defp extract_response_from_items(items) do
    items
    |> Map.values()
    |> Enum.filter(&(&1.type == :agent_message))
    |> Enum.sort_by(& &1.inserted_at)
    |> Enum.map(&get_in(&1.payload, ["content"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp handle_approval_request(method, params, interaction, surface_module) do
    event = :approval_required

    case notify_surface_for_approval(surface_module, interaction, event, %{
           method: method,
           params: params
         }) do
      {:ok, :accept} ->
        {:ok, %{decision: "accept"}}

      {:ok, :decline} ->
        {:ok, %{decision: "decline"}}

      {:ok, decision} when is_binary(decision) ->
        {:ok, %{decision: decision}}

      _ ->
        {:ok, %{decision: "decline"}}
    end
  end

  defp notify_surface_for_approval(nil, _interaction, _event, _params) do
    {:ok, :decline}
  end

  defp notify_surface_for_approval(surface_module, interaction, event, params) do
    surface = interaction.surface
    surface_module.handle_event(surface, interaction, event, params)
  rescue
    e ->
      Logger.error("Surface.handle_event approval error: #{inspect(e)}")
      {:ok, :decline}
  end

  defp map_item_type("userMessage"), do: :user_message
  defp map_item_type("agentMessage"), do: :agent_message
  defp map_item_type("reasoning"), do: :reasoning
  defp map_item_type("commandExecution"), do: :command_execution
  defp map_item_type("fileChange"), do: :file_change
  defp map_item_type("mcpToolCall"), do: :mcp_tool_call
  defp map_item_type("webSearch"), do: :web_search
  defp map_item_type(_), do: :agent_message
end
