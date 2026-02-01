# Task Warrior - Simple Self-Scheduling System

## Overview

A lightweight task system where the AI model can schedule tasks for itself during conversation. The model decides what needs to be done and when, and the server simply picks up and executes these tasks.

**Key Philosophy**: The AI is in control. It decides what tasks to create, when they should run, and what they should do. The server is just the executor.

## Architecture

```
User: "Remind me to check the deployment in 2 hours"
    ↓
Model (via tool): Creates task "Check deployment status" due in 2h
    ↓
Database: Stores task with due_at timestamp
    ↓
Poller: Checks every minute for due tasks
    ↓
Server: Creates new interaction: "[TASK DUE] Check deployment status"
    ↓
Model: Wakes up and executes the task
```

## Components

### 1. Simple Task Resource

```elixir
# lib/piano/tasks/task.ex
defmodule Piano.Tasks.Task do
  @moduledoc """
  A simple task that the AI has scheduled for itself.
  """
  use Ash.Resource,
    domain: Piano.Tasks,
    data_layer: AshSqlite.DataLayer

  attributes do
    uuid_primary_key :id
    
    attribute :description, :string do
      allow_nil? false
      description "What the AI needs to do"
    end
    
    attribute :context, :map do
      default: %{}
      description "Additional context the AI provided"
    end
    
    attribute :due_at, :utc_datetime_usec do
      allow_nil? false
    end
    
    attribute :status, :atom do
      constraints one_of: [:pending, :completed, :cancelled]
      default :pending
    end
    
    attribute :created_by_interaction_id, :uuid do
      description "The interaction that created this task"
    end
    
    attribute :completed_at, :utc_datetime_usec
    attribute :result, :string
    
    timestamps()
  end
  
  relationships do
    belongs_to :user, Piano.Core.User
    belongs_to :surface, Piano.Core.Surface
    belongs_to :created_by_interaction, Piano.Core.Interaction
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [:description, :context, :due_at, :user_id, :surface_id, :created_by_interaction_id]
    end
    
    update :complete do
      accept [:status, :completed_at, :result]
      change set_attribute(:status, :completed)
    end
    
    update :cancel do
      change set_attribute(:status, :cancelled)
    end
    
    read :due do
      prepare fn query, _context ->
        now = DateTime.utc_now()
        
        query
        |> Ash.Query.filter(status == :pending)
        |> Ash.Query.filter(due_at <= ^now)
        |> Ash.Query.sort(:due_at)
      end
    end
    
    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      argument :status, :atom, default: :pending
      
      filter expr(user_id == ^arg(:user_id) and status == ^arg(:status))
    end
  end
end
```

### 2. MCP Tool for Task Creation

```elixir
# lib/piano/tools/task_warrior.ex
defmodule Piano.Tools.TaskWarrior do
  @moduledoc """
  MCP tool that allows the AI to schedule tasks for itself.
  """
  
  alias Piano.Tasks.Task
  
  def tool_definition do
    %{
      name: "schedule_task",
      description: """
      Schedule a task for yourself to complete later. Use this when:
      - The user asks you to remind them of something
      - You need to check on something later (e.g., "check email in an hour")
      - You want to follow up on a long-running process
      - You need to perform periodic actions
      
      You can use natural language for the due time like:
      - "in 30 minutes"
      - "tomorrow at 9am"
      - "in 2 hours"
      - "next Monday"
      """,
      parameters: %{
        type: "object",
        properties: %{
          description: %{
            type: "string",
            description: "Clear description of what needs to be done"
          },
          due_in: %{
            type: "string",
            description: "When to execute (e.g., '30 minutes', '2 hours', 'tomorrow 9am')"
          },
          context: %{
            type: "object",
            description: "Any additional context needed to complete the task"
          }
        },
        required: ["description", "due_in"]
      }
    }
  end
  
  def handle_tool_call(%{"description" => description, "due_in" => due_in} = args, opts) do
    # Parse the natural language time
    case parse_due_time(due_in) do
      {:ok, due_at} ->
        # Get context from the current interaction
        interaction_id = opts[:interaction_id]
        interaction = get_interaction(interaction_id)
        
        attrs = %{
          description: description,
          context: args["context"] || %{},
          due_at: due_at,
          user_id: interaction.user_id,
          surface_id: interaction.surface_id,
          created_by_interaction_id: interaction_id
        }
        
        case Ash.create(Task, attrs) do
          {:ok, task} ->
            formatted_time = format_time(due_at)
            {:ok, %{
              task_id: task.id,
              description: description,
              scheduled_for: formatted_time,
              status: "scheduled"
            }}
            
          {:error, reason} ->
            {:error, "Failed to schedule task: #{inspect(reason)}"}
        end
        
      {:error, reason} ->
        {:error, "Could not understand time '#{due_in}': #{reason}"}
    end
  end
  
  def handle_tool_call(_args, _opts) do
    {:error, "Missing required parameters: description and due_in"}
  end
  
  # Natural language time parsing
  defp parse_due_time("in " <> rest) do
    parse_duration(rest)
  end
  
  defp parse_due_time("tomorrow" <> time) do
    time = String.trim(time)
    tomorrow = Date.utc_today() |> Date.add(1)
    
    case parse_time_of_day(time) do
      {:ok, {hour, minute}} ->
        due_at = NaiveDateTime.new!(tomorrow, Time.new!(hour, minute, 0))
                 |> DateTime.from_naive!("UTC")
        {:ok, due_at}
        
      :error ->
        # Default to 9am
        due_at = NaiveDateTime.new!(tomorrow, ~T[09:00:00])
                 |> DateTime.from_naive!("UTC")
        {:ok, due_at}
    end
  end
  
  defp parse_due_time(text) do
    # Try to parse various formats
    cond do
      Regex.match?(~r/^\d+\s*minutes?$/i, text) ->
        parse_duration(text)
        
      Regex.match?(~r/^\d+\s*hours?$/i, text) ->
        parse_duration(text)
        
      Regex.match?(~r/\d{1,2}:\d{2}/, text) ->
        parse_absolute_time(text)
        
      true ->
        {:error, "Unsupported time format. Try 'in 30 minutes' or 'tomorrow 9am'"}
    end
  end
  
  defp parse_duration(text) do
    case Regex.run(~r/(\d+)\s*(minutes?|hours?|h|m)/i, text) do
      [_, num, unit] ->
        minutes = case String.downcase(unit) do
          u when u in ["hours", "hour", "h"] -> String.to_integer(num) * 60
          u when u in ["minutes", "minute", "m", "min", "mins"] -> String.to_integer(num)
          _ -> String.to_integer(num)
        end
        
        due_at = DateTime.utc_now() |> DateTime.add(minutes * 60, :second)
        {:ok, due_at}
        
      _ ->
        {:error, "Could not parse duration"}
    end
  end
  
  defp parse_absolute_time(text) do
    case Regex.run(~r/(\d{1,2}):(\d{2})/, text) do
      [_, hour_str, minute_str] ->
        hour = String.to_integer(hour_str)
        minute = String.to_integer(minute_str)
        
        now = DateTime.utc_now()
        today = Date.utc_today()
        
        # If time already passed today, schedule for tomorrow
        target_date = if hour < now.hour or (hour == now.hour and minute < now.minute) do
          Date.add(today, 1)
        else
          today
        end
        
        due_at = NaiveDateTime.new!(target_date, Time.new!(hour, minute, 0))
                 |> DateTime.from_naive!("UTC")
        {:ok, due_at}
        
      _ ->
        {:error, "Could not parse time"}
    end
  end
  
  defp parse_time_of_day("at " <> time), do: parse_time_of_day(time)
  defp parse_time_of_day(time) do
    case Regex.run(~r/(\d{1,2}):?(\d{2})?\s*(am|pm)?/i, time) do
      [_, hour_str, minute_str, am_pm] ->
        hour = String.to_integer(hour_str)
        minute = if minute_str && minute_str != "", do: String.to_integer(minute_str), else: 0
        
        hour = case am_pm do
          "pm" when hour < 12 -> hour + 12
          "am" when hour == 12 -> 0
          _ -> hour
        end
        
        {:ok, {hour, minute}}
        
      _ ->
        :error
    end
  end
  
  defp get_interaction(interaction_id) do
    case Ash.get(Piano.Core.Interaction, interaction_id) do
      {:ok, interaction} -> interaction
      _ -> nil
    end
  end
  
  defp format_time(datetime) do
    datetime
    |> DateTime.shift_zone!("America/New_York")  # Use user's timezone
    |> Calendar.strftime("%B %d at %I:%M %p")
  end
end
```

### 3. Task Poller

```elixir
# lib/piano/tasks/poller.ex
defmodule Piano.Tasks.Poller do
  @moduledoc """
  Simple poller that checks for due tasks and wakes up the agent.
  """
  
  use GenServer
  require Logger
  
  @poll_interval_ms 60_000  # Check every minute
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    schedule_poll()
    Logger.info("Task poller started")
    {:ok, %{last_run: nil}}
  end
  
  @impl true
  def handle_info(:poll, state) do
    process_due_tasks()
    schedule_poll()
    {:noreply, %{state | last_run: DateTime.utc_now()}}
  end
  
  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end
  
  defp process_due_tasks do
    case Piano.Tasks.Task
         |> Ash.Query.for_read(:due)
         |> Ash.read() do
      {:ok, tasks} when length(tasks) > 0 ->
        Logger.info("Found #{length(tasks)} due tasks", task_ids: Enum.map(tasks, & &1.id))
        
        Enum.each(tasks, &wake_up_for_task/1)
        
      {:ok, []} ->
        :ok
        
      {:error, reason} ->
        Logger.error("Failed to query due tasks: #{inspect(reason)}")
    end
  end
  
  defp wake_up_for_task(task) do
    Logger.info("Waking up for task", task_id: task.id, description: task.description)
    
    # Create an interaction to wake up the agent
    {:ok, _interaction} = create_wake_up_interaction(task)
    
    # Mark task as being processed (but don't complete yet - 
    # the AI will mark it complete after processing)
    # We'll mark it as processing by setting a flag or just leaving it pending
    # The AI's response should include completing the task
  end
  
  defp create_wake_up_interaction(task) do
    # Create a synthetic interaction that looks like a user message
    reply_to = build_reply_to(task)
    
    # Find or create a thread for this task
    {:ok, thread} = get_or_create_thread(task, reply_to)
    
    # Build the wake-up message
    message = build_wake_up_message(task)
    
    Piano.Core.Interaction.create(%{
      original_message: message,
      reply_to: reply_to,
      thread_id: thread.id,
      user_id: task.user_id
    })
  end
  
  defp build_wake_up_message(task) do
    context = if map_size(task.context) > 0 do
      context_str = Enum.map_join(task.context, "\n", fn {k, v} -> "#{k}: #{v}" end)
      "\n\nContext:\n#{context_str}"
    else
      ""
    end
    
    """
    [TASK DUE]
    
    You previously scheduled this task:
    #{task.description}
    #{context}
    
    Please complete this task now and report back. 
    When done, mark the task as complete using the complete_task tool.
    """
  end
  
  defp get_or_create_thread(task, reply_to) do
    query = 
      Piano.Core.Thread
      |> Ash.Query.filter(reply_to == ^reply_to)
      |> Ash.Query.filter(status == :active)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)
    
    case Ash.read(query) do
      {:ok, [thread | _]} -> 
        {:ok, thread}
        
      {:ok, []} -> 
        Ash.create(Piano.Core.Thread, %{
          reply_to: reply_to,
          agent_id: get_default_agent_id()
        })
        
      error -> 
        error
    end
  end
  
  defp build_reply_to(task) do
    "task:#{task.id}"
  end
  
  defp get_default_agent_id do
    case Piano.Core.Agent
         |> Ash.Query.for_read(:get_default)
         |> Ash.read() do
      {:ok, [agent | _]} -> agent.id
      _ -> nil
    end
  end
end
```

### 4. Complete Task Tool

```elixir
# lib/piano/tools/task_warrior.ex (add to existing)

def complete_task_tool_definition do
  %{
    name: "complete_task",
    description: "Mark a scheduled task as completed after you've finished it",
    parameters: %{
      type: "object",
      properties: %{
        task_id: %{
          type: "string",
          description: "The ID of the task to complete"
        },
        result: %{
          type: "string",
          description: "Brief summary of what was accomplished"
        }
      },
      required: ["task_id"]
    }
  }
end

def handle_complete_task(%{"task_id" => task_id} = args, _opts) do
  case Ash.get(Piano.Tasks.Task, task_id) do
    {:ok, task} ->
      result = args["result"] || "Task completed"
      
      case Piano.Tasks.Task.complete(task, %{
        completed_at: DateTime.utc_now(),
        result: result
      }) do
        {:ok, updated_task} ->
          {:ok, %{
            task_id: updated_task.id,
            status: "completed",
            completed_at: updated_task.completed_at,
            result: result
          }}
          
        {:error, reason} ->
          {:error, "Failed to complete task: #{inspect(reason)}"}
      end
      
    {:error, _} ->
      {:error, "Task not found: #{task_id}"}
  end
end
```

### 5. MCP Tool Registration

Update `Piano.Tools.Mcp` to include the new tools:

```elixir
# lib/piano/tools/mcp.ex

def tool_definitions do
  [
    # ... existing tools ...
    
    Piano.Tools.TaskWarrior.tool_definition(),
    Piano.Tools.TaskWarrior.complete_task_tool_definition()
  ]
end

def handle_tool_call("schedule_task", arguments, opts) do
  Piano.Tools.TaskWarrior.handle_tool_call(arguments, opts)
end

def handle_tool_call("complete_task", arguments, opts) do
  Piano.Tools.TaskWarrior.handle_complete_task(arguments, opts)
end
```

### 6. Domain Definition

```elixir
# lib/piano/tasks.ex
defmodule Piano.Tasks do
  use Ash.Domain
  
  resources do
    resource Piano.Tasks.Task
  end
end
```

### 7. Migration

```elixir
# priv/repo/migrations/20260131000001_add_tasks_table.exs
defmodule Piano.Repo.Migrations.AddTasksTable do
  use Ecto.Migration

  def up do
    create table(:tasks, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :description, :text, null: false
      add :context, :map, null: false, default: %{}
      add :due_at, :utc_datetime_usec, null: false
      add :status, :text, null: false, default: "pending"
      add :user_id, references(:users, column: :id, type: :uuid)
      add :surface_id, references(:surfaces, column: :id, type: :uuid)
      add :created_by_interaction_id, references(:interactions, column: :id, type: :uuid)
      add :completed_at, :utc_datetime_usec
      add :result, :text
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end
    
    create index(:tasks, [:status, :due_at])
    create index(:tasks, [:user_id, :status])
  end

  def down do
    drop table(:tasks)
  end
end
```

### 8. Application Integration

```elixir
# lib/piano/application.ex

defp scheduler_children do
  if Application.get_env(:piano, :task_poller_enabled, true) do
    [
      Piano.Tasks.Poller
    ]
  else
    []
  end
end

# Add to children list
children = [
  # ... existing children ...
] ++ scheduler_children()
```

## Usage Examples

### User Conversation

```
User: "Can you check my email in an hour and let me know if anything urgent came in?"

Model: *uses schedule_task tool*
  description: "Check user's email for urgent messages"
  due_in: "in 1 hour"
  context: {check_for: "urgent", notify_if_found: true}

Model: "I'll check your email in an hour and let you know if there's anything urgent."

[1 hour later...]

System: Creates interaction "[TASK DUE] Check user's email for urgent messages"

Model: "Checking your email now..." *checks email*
Model: *uses complete_task tool*

Model: "Good news! No urgent emails. You have 3 new messages but nothing that needs immediate attention."
```

### Self-Scheduling

```
User: "Deploy that new feature when the tests pass"

Model: *runs tests*
Model: "Tests are still running. I'll check back in 5 minutes."
*uses schedule_task tool*
  description: "Check test results and deploy if passed"
  due_in: "in 5 minutes"

[5 minutes later...]

System: Creates interaction "[TASK DUE] Check test results and deploy if passed"

Model: "Checking tests..."
Model: "All tests passed! Deploying now..."
Model: *deploys*
Model: *uses complete_task tool*

Model: "Deployment complete! The new feature is live."
```

### Daily Reminders

```
User: "Remind me every day at 9am to review my PRs"

Model: *uses schedule_task tool*
  description: "Check GitHub PRs and provide summary"
  due_in: "tomorrow 9am"
  
[Tomorrow at 9am...]

System: Creates interaction "[TASK DUE] Check GitHub PRs and provide summary"

Model: *checks PRs*
Model: "Good morning! You have 2 PRs awaiting review:
- PR #123: Fix auth bug (ready to merge)
- PR #124: Add new feature (needs changes)"
Model: *uses schedule_task tool to schedule next reminder*
  description: "Check GitHub PRs and provide summary"
  due_in: "tomorrow 9am"
```

## Benefits of This Approach

1. **Simplicity**: No complex cron expressions - natural language "in 2 hours"
2. **AI Control**: The AI decides what to schedule, not rigid config files
3. **Context Preservation**: Tasks carry context from the conversation
4. **Conversational**: Feels natural - "I'll remind you later"
5. **Self-Healing**: If a task fails, the AI can reschedule it
6. **No Admin UI Needed**: Everything happens through conversation

## Comparison: Task Warrior vs Full Scheduler

| Aspect | Task Warrior (Simple) | Full Scheduler (Complex) |
|--------|----------------------|-------------------------|
| **Who creates tasks** | AI during conversation | Admin or config file |
| **Time syntax** | Natural language | Cron expressions |
| **Complexity** | Low - 2 resources | High - 4+ resources |
| **Flexibility** | High - AI decides | Low - pre-configured |
| **Use case** | Ad-hoc reminders, follow-ups | Recurring system tasks |
| **User experience** | Conversational | Configuration |

## Recommendation

**Start with Task Warrior** - it's simpler, more natural for users, and the AI can handle the scheduling logic. You can always add the full cron-based scheduler later for system-level recurring tasks (like "check disk space every hour").

Task Warrior is perfect for:
- "Remind me in 2 hours"
- "Check back on this tomorrow"
- "Follow up next week"
- User-driven scheduling

The full scheduler is better for:
- System monitoring
- Automated backups
- Admin-configured jobs
- Infrastructure tasks
