# Waking Agent - Periodic Task Scheduler Design

## Overview

A system to periodically wake up the agent to execute autonomous tasks without user interaction. This enables proactive behaviors like:
- Email monitoring and notifications
- Scheduled reminders and follow-ups
- Background data processing
- System health checks
- Periodic reports/summaries

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Scheduler     │────▶│  Task Executor   │────▶│  Piano Agent    │
│   (Cron-like)   │     │   (GenServer)    │     │  (Codex Turn)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                       │                        │
         │              ┌────────┴────────┐              │
         ▼              ▼                 ▼              ▼
┌─────────────────┐ ┌──────────┐   ┌───────────┐ ┌─────────────────┐
│  ScheduledTask  │ │ TaskLog  │   │  Gmail    │ │  Surface        │
│  (Ash Resource) │ │ (Audit)  │   │  Checker  │ │  Notification   │
└─────────────────┘ └──────────┘   └───────────┘ └─────────────────┘
```

## Components

### 1. ScheduledTask Resource

```elixir
# lib/piano/scheduler/scheduled_task.ex
defmodule Piano.Scheduler.ScheduledTask do
  @moduledoc """
  Defines a periodically executed task that wakes up the agent.
  """
  use Ash.Resource,
    domain: Piano.Scheduler,
    data_layer: AshSqlite.DataLayer

  attributes do
    uuid_primary_key :id
    
    attribute :name, :string do
      allow_nil? false
      description "Human-readable task name"
    end
    
    attribute :task_type, :atom do
      constraints one_of: [
        :check_email,      # Check Gmail/inbox
        :health_check,     # System health monitoring
        :daily_summary,    # Generate daily report
        :custom_prompt     # Execute custom Codex prompt
      ]
      allow_nil? false
    end
    
    attribute :cron_expression, :string do
      allow_nil? false
      description "Cron expression (e.g., '0 */6 * * *' for every 6 hours)"
    end
    
    attribute :timezone, :string do
      default "UTC"
      description "Timezone for cron execution (e.g., 'America/New_York')"
    end
    
    attribute :config, :map do
      default %{}
      description "Task-specific configuration (e.g., email filters, prompt template)"
    end
    
    attribute :target_surface_id, :uuid do
      description "Surface to notify with results (optional)"
    end
    
    attribute :target_user_id, :uuid do
      description "User to run task as (for context/memory)"
    end
    
    attribute :enabled, :boolean do
      default true
    end
    
    attribute :last_run_at, :utc_datetime_usec
    attribute :next_run_at, :utc_datetime_usec
    attribute :last_error, :string
    
    timestamps()
  end
  
  relationships do
    belongs_to :target_surface, Piano.Core.Surface
    belongs_to :target_user, Piano.Core.User
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [:name, :task_type, :cron_expression, :timezone, 
              :config, :target_surface_id, :target_user_id, :enabled]
    end
    
    update :update do
      accept [:name, :cron_expression, :timezone, :config, 
              :enabled, :target_surface_id, :target_user_id]
    end
    
    update :record_execution do
      accept [:last_run_at, :next_run_at, :last_error]
    end
    
    read :due_for_execution do
      prepare fn query, _context ->
        now = DateTime.utc_now()
        
        query
        |> Ash.Query.filter(enabled == true)
        |> Ash.Query.filter(
          is_nil(next_run_at) or next_run_at <= ^now
        )
        |> Ash.Query.sort(:next_run_at)
      end
    end
    
    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      
      filter expr(target_user_id == ^arg(:user_id))
    end
  end
  
  calculations do
    calculate :calculate_next_run, :utc_datetime_usec do
      constraint fn task ->
        # Calculate next run time from cron expression
        case Crontab.CronExpression.Parser.parse(task.cron_expression) do
          {:ok, cron} ->
            now = DateTime.utc_now() |> DateTime.to_naive()
            next = Crontab.Scheduler.get_next_run_date(cron, now)
            {:ok, DateTime.from_naive!(next, "UTC")}
            
          {:error, reason} ->
            {:error, "Invalid cron expression: #{reason}"}
        end
      end
    end
  end
end
```

### 2. Task Execution Log

```elixir
# lib/piano/scheduler/task_execution.ex
defmodule Piano.Scheduler.TaskExecution do
  @moduledoc """
  Audit log of task executions for debugging and monitoring.
  """
  use Ash.Resource,
    domain: Piano.Scheduler,
    data_layer: AshSqlite.DataLayer

  attributes do
    uuid_primary_key :id
    
    attribute :status, :atom do
      constraints one_of: [:started, :completed, :failed]
      allow_nil? false
    end
    
    attribute :started_at, :utc_datetime_usec, allow_nil?: false
    attribute :completed_at, :utc_datetime_usec
    attribute :duration_ms, :integer
    
    attribute :result_summary, :string
    attribute :error_message, :string
    attribute :output_data, :map, default: %{}
    
    timestamps()
  end
  
  relationships do
    belongs_to :scheduled_task, Piano.Scheduler.ScheduledTask
  end
  
  actions do
    defaults [:read]
    
    create :create do
      accept [:scheduled_task_id, :status, :started_at]
    end
    
    update :complete do
      accept [:status, :completed_at, :duration_ms, :result_summary, :output_data]
      change set_attribute(:status, :completed)
    end
    
    update :fail do
      accept [:status, :completed_at, :duration_ms, :error_message]
      change set_attribute(:status, :failed)
    end
    
    read :recent_for_task do
      argument :scheduled_task_id, :uuid, allow_nil?: false
      argument :limit, :integer, default: 10
      
      prepare fn query, _context ->
        task_id = Ash.Query.get_argument(query, :scheduled_task_id)
        limit = Ash.Query.get_argument(query, :limit)
        
        query
        |> Ash.Query.filter(scheduled_task_id == ^task_id)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end
  end
end
```

### 3. Task Scheduler (GenServer)

```elixir
# lib/piano/scheduler/scheduler.ex
defmodule Piano.Scheduler do
  @moduledoc """
  Cron-like task scheduler that periodically wakes up the agent.
  
  Features:
  - Polls for due tasks every minute
  - Executes tasks asynchronously
  - Updates next run times automatically
  - Handles errors gracefully
  """
  
  use GenServer
  require Logger
  
  alias Piano.Scheduler.TaskRunner
  
  @poll_interval_ms 60_000  # Check every minute
  @max_concurrent_tasks 5
  
  defstruct [
    :timer_ref,
    running_tasks: %{},
    last_poll_at: nil
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Force immediate check for due tasks.
  """
  def check_now do
    GenServer.cast(__MODULE__, :check_due_tasks)
  end
  
  @doc """
  Get current scheduler status.
  """
  def status do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Temporarily pause a scheduled task.
  """
  def pause_task(task_id) do
    GenServer.call(__MODULE__, {:pause_task, task_id})
  end
  
  @doc """
  Resume a paused task.
  """
  def resume_task(task_id) do
    GenServer.call(__MODULE__, {:resume_task, task_id})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Schedule first poll
    timer = schedule_next_poll()
    
    Logger.info("Task scheduler started, polling every #{@poll_interval_ms}ms")
    
    {:ok, %__MODULE__{timer_ref: timer}}
  end
  
  @impl true
  def handle_cast(:check_due_tasks, state) do
    new_state = execute_due_tasks(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:poll, state) do
    new_state = execute_due_tasks(state)
    timer = schedule_next_poll()
    
    {:noreply, %{new_state | timer_ref: timer, last_poll_at: DateTime.utc_now()}}
  end
  
  @impl true
  def handle_info({:task_completed, task_id, result}, state) do
    {_, new_running} = Map.pop(state.running_tasks, task_id)
    
    case result do
      {:ok, execution} ->
        Logger.info("Scheduled task completed", 
          task_id: task_id, 
          duration_ms: execution.duration_ms,
          status: execution.status
        )
        
      {:error, reason} ->
        Logger.error("Scheduled task failed", 
          task_id: task_id, 
          error: inspect(reason)
        )
    end
    
    {:noreply, %{state | running_tasks: new_running}}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      running_tasks_count: map_size(state.running_tasks),
      running_task_ids: Map.keys(state.running_tasks),
      last_poll_at: state.last_poll_at,
      next_poll_in_ms: @poll_interval_ms
    }
    
    {:reply, {:ok, status}, state}
  end
  
  # Private Functions
  
  defp schedule_next_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end
  
  defp execute_due_tasks(state) do
    # Don't overload - check if we're at capacity
    if map_size(state.running_tasks) >= @max_concurrent_tasks do
      Logger.warning("Scheduler at capacity, skipping poll",
        running_count: map_size(state.running_tasks),
        max: @max_concurrent_tasks
      )
      
      state
    else
      case Piano.Scheduler.ScheduledTask 
           |> Ash.Query.for_read(:due_for_execution)
           |> Ash.read() do
        
        {:ok, tasks} ->
          Logger.debug("Found #{length(tasks)} tasks due for execution")
          
          Enum.reduce(tasks, state, fn task, acc ->
            if map_size(acc.running_tasks) < @max_concurrent_tasks do
              execute_task_async(task, acc)
            else
              acc
            end
          end)
          
        {:error, reason} ->
          Logger.error("Failed to query due tasks: #{inspect(reason)}")
          state
      end
    end
  end
  
  defp execute_task_async(task, state) do
    # Start task execution
    pid = self()
    task_id = task.id
    
    spawn_monitor(fn ->
      result = TaskRunner.run(task)
      send(pid, {:task_completed, task_id, result})
    end)
    
    %{state | running_tasks: Map.put(state.running_tasks, task_id, DateTime.utc_now())}
  end
end
```

### 4. Task Runner

```elixir
# lib/piano/scheduler/task_runner.ex
defmodule Piano.Scheduler.TaskRunner do
  @moduledoc """
  Executes scheduled tasks and handles the interaction with Codex.
  """
  
  require Logger
  
  alias Piano.Scheduler.TaskExecution
  alias Piano.Core.{Thread, Interaction}
  
  @doc """
  Execute a scheduled task and return the result.
  """
  def run(task) do
    started_at = DateTime.utc_now()
    
    # Log execution start
    {:ok, execution} = TaskExecution.create(%{
      scheduled_task_id: task.id,
      status: :started,
      started_at: started_at
    })
    
    # Execute the appropriate task handler
    result = execute_task_by_type(task, execution)
    
    # Calculate duration
    completed_at = DateTime.utc_now()
    duration_ms = DateTime.diff(completed_at, started_at, :millisecond)
    
    # Update execution log
    case result do
      {:ok, summary, output} ->
        TaskExecution.complete(execution, %{
          completed_at: completed_at,
          duration_ms: duration_ms,
          result_summary: summary,
          output_data: output
        })
        
      {:error, reason} ->
        TaskExecution.fail(execution, %{
          completed_at: completed_at,
          duration_ms: duration_ms,
          error_message: inspect(reason)
        })
    end
    
    # Update task with last run info
    update_task_schedule(task, result)
    
    result
  end
  
  defp execute_task_by_type(task, execution) do
    case task.task_type do
      :check_email ->
        check_email_task(task)
        
      :health_check ->
        health_check_task(task)
        
      :daily_summary ->
        daily_summary_task(task)
        
      :custom_prompt ->
        custom_prompt_task(task)
        
      _ ->
        {:error, "Unknown task type: #{task.task_type}"}
    end
  end
  
  # Task Implementations
  
  defp check_email_task(task) do
    config = task.config
    
    # This would integrate with the Gmail checker from product_improvements.md
    case Piano.Tools.GmailChecker.check(config) do
      {:ok, emails} ->
        if length(emails) > 0 do
          # Create an autonomous interaction
          prompt = build_email_prompt(emails, config)
          {:ok, result} = create_autonomous_interaction(task, prompt)
          
          {:ok, "Found #{length(emails)} new emails", %{emails: emails, processed: true}}
        else
          {:ok, "No new emails", %{emails: []}}
        end
        
      {:error, reason} ->
        {:error, "Email check failed: #{inspect(reason)}"}
    end
  end
  
  defp health_check_task(task) do
    # Check system health
    checks = [
      check_codex_connection(),
      check_database_connection(),
      check_telegram_connection(),
      check_disk_space()
    ]
    
    issues = Enum.filter(checks, fn {status, _} -> status == :error end)
    
    if length(issues) > 0 do
      # Alert user about issues
      alert_message = build_health_alert(issues)
      create_autonomous_interaction(task, alert_message)
      
      {:ok, "Health check found #{length(issues)} issues", %{issues: length(issues)}}
    else
      {:ok, "All systems healthy", %{healthy: true}}
    end
  end
  
  defp daily_summary_task(task) do
    # Gather daily activity
    user_id = task.target_user_id
    
    summary_data = %{
      interactions_today: count_today_interactions(user_id),
      threads_active: count_active_threads(user_id),
      tasks_run: count_tasks_run_today(user_id),
      top_topics: get_top_topics(user_id)
    }
    
    prompt = """
    Generate a daily summary for the user based on the following data:
    
    Interactions today: #{summary_data.interactions_today}
    Active threads: #{summary_data.threads_active}
    Scheduled tasks run: #{summary_data.tasks_run}
    Top topics: #{Enum.join(summary_data.top_topics, ", ")}
    
    Create a brief, helpful summary and suggest any follow-up actions.
    """
    
    create_autonomous_interaction(task, prompt)
    
    {:ok, "Daily summary generated", summary_data}
  end
  
  defp custom_prompt_task(task) do
    config = task.config
    prompt = config["prompt"] || config[:prompt] || "Execute scheduled task"
    
    create_autonomous_interaction(task, prompt)
    
    {:ok, "Custom prompt executed", %{prompt: prompt}}
  end
  
  # Helper Functions
  
  defp create_autonomous_interaction(task, prompt) do
    # Create a synthetic interaction for the scheduled task
    reply_to = build_reply_to(task)
    
    with {:ok, thread} <- get_or_create_thread(task, reply_to),
         {:ok, interaction} <- create_interaction(task, prompt, thread, reply_to) do
      
      # Start the turn like a normal message
      Piano.Codex.start_turn(interaction)
    end
  end
  
  defp get_or_create_thread(task, reply_to) do
    # Try to find existing thread for this scheduled task
    query = 
      Thread
      |> Ash.Query.filter(reply_to == ^reply_to)
      |> Ash.Query.filter(status == :active)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)
    
    case Ash.read(query) do
      {:ok, [thread | _]} -> {:ok, thread}
      {:ok, []} -> 
        # Create new thread for this scheduled task
        Ash.create(Thread, %{
          reply_to: reply_to,
          agent_id: get_default_agent_id()
        })
      error -> error
    end
  end
  
  defp create_interaction(task, prompt, thread, reply_to) do
    Ash.create(Interaction, %{
      original_message: "[SCHEDULED TASK: #{task.name}]\n\n#{prompt}",
      reply_to: reply_to,
      thread_id: thread.id
    })
  end
  
  defp build_reply_to(task) do
    # Create a unique reply_to for scheduled tasks
    # This allows them to have their own thread
    "scheduled:#{task.id}:#{DateTime.to_unix(DateTime.utc_now())}"
  end
  
  defp update_task_schedule(task, result) do
    # Calculate next run time
    case Crontab.CronExpression.Parser.parse(task.cron_expression) do
      {:ok, cron} ->
        now = DateTime.utc_now() |> DateTime.to_naive()
        next_run = Crontab.Scheduler.get_next_run_date(cron, now)
        
        last_error = case result do
          {:error, reason} -> inspect(reason)
          _ -> nil
        end
        
        Piano.Scheduler.ScheduledTask.record_execution(task, %{
          last_run_at: DateTime.utc_now(),
          next_run_at: DateTime.from_naive!(next_run, "UTC"),
          last_error: last_error
        })
        
      {:error, _} ->
        :ok
    end
  end
  
  # Placeholder health checks
  defp check_codex_connection, do: {:ok, "Codex connected"}
  defp check_database_connection, do: {:ok, "Database connected"}
  defp check_telegram_connection, do: {:ok, "Telegram connected"}
  defp check_disk_space, do: {:ok, "Disk space OK"}
  
  defp get_default_agent_id do
    # Get the default agent ID
    case Piano.Core.Agent
         |> Ash.Query.for_read(:get_default)
         |> Ash.read() do
      {:ok, [agent | _]} -> agent.id
      _ -> nil
    end
  end
  
  # Placeholder data functions
  defp count_today_interactions(_user_id), do: 0
  defp count_active_threads(_user_id), do: 0
  defp count_tasks_run_today(_user_id), do: 0
  defp get_top_topics(_user_id), do: []
  
  defp build_email_prompt(emails, _config) do
    email_list = Enum.map_join(emails, "\n", fn email ->
      "- #{email.subject} from #{email.from}"
    end)
    
    """
    You have #{length(emails)} new email(s):
    
    #{email_list}
    
    Please provide a brief summary and suggest priority actions.
    """
  end
  
  defp build_health_alert(issues) do
    issue_list = Enum.map_join(issues, "\n", fn {:error, msg} -> "- #{msg}" end)
    
    """
    System health check detected #{length(issues)} issue(s):
    
    #{issue_list}
    
    Please alert the user about these issues.
    """
  end
end
```

### 5. Scheduler Domain

```elixir
# lib/piano/scheduler.ex
defmodule Piano.Scheduler do
  @moduledoc """
  Domain for scheduled tasks and task execution.
  """
  
  use Ash.Domain
  
  resources do
    resource Piano.Scheduler.ScheduledTask
    resource Piano.Scheduler.TaskExecution
  end
end
```

### 6. Integration with Application

```elixir
# lib/piano/application.ex - Add to children

defp scheduler_children do
  if Application.get_env(:piano, :scheduler_enabled, true) do
    [
      Piano.Scheduler,  # The scheduler GenServer
    ]
  else
    []
  end
end

# In start/2:
children = [
  PianoWeb.Telemetry,
  Piano.Repo,
  {DNSCluster, query: Application.get_env(:piano, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: Piano.PubSub},
  Piano.Codex.Client,
  Piano.Pipeline.CodexEventPipeline,
  PianoWeb.Endpoint
] ++ browser_agent_children() ++ telegram_children() ++ scheduler_children()
```

### 7. Mix Dependency

Add to `mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps ...
    
    # Task scheduling
    {:crontab, "~> 1.1"},
  ]
end
```

## Database Migration

```elixir
# priv/repo/migrations/20260131000000_add_scheduler_tables.exs
defmodule Piano.Repo.Migrations.AddSchedulerTables do
  use Ecto.Migration

  def up do
    create table(:scheduled_tasks, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :task_type, :text, null: false
      add :cron_expression, :text, null: false
      add :timezone, :text, null: false, default: "UTC"
      add :config, :map, null: false, default: %{}
      add :target_surface_id, references(:surfaces, column: :id, type: :uuid)
      add :target_user_id, references(:users, column: :id, type: :uuid)
      add :enabled, :boolean, null: false, default: true
      add :last_run_at, :utc_datetime_usec
      add :next_run_at, :utc_datetime_usec
      add :last_error, :text
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end
    
    create index(:scheduled_tasks, [:enabled, :next_run_at])
    create index(:scheduled_tasks, [:target_user_id])
    
    create table(:task_executions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :scheduled_task_id, references(:scheduled_tasks, column: :id, type: :uuid), null: false
      add :status, :text, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer
      add :result_summary, :text
      add :error_message, :text
      add :output_data, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end
    
    create index(:task_executions, [:scheduled_task_id, :inserted_at])
  end

  def down do
    drop table(:task_executions)
    drop table(:scheduled_tasks)
  end
end
```

## API Examples

### Creating a Scheduled Task

```elixir
# Check email every 30 minutes
{:ok, task} = Piano.Scheduler.ScheduledTask.create(%{
  name: "Email Monitor",
  task_type: :check_email,
  cron_expression: "*/30 * * * *",
  timezone: "America/New_York",
  config: %{
    filters: ["unread", "important"],
    max_results: 10
  },
  target_surface_id: surface_id,
  target_user_id: user_id
})

# Daily summary at 9 AM
{:ok, task} = Piano.Scheduler.ScheduledTask.create(%{
  name: "Daily Summary",
  task_type: :daily_summary,
  cron_expression: "0 9 * * *",
  target_user_id: user_id
})

# Custom prompt every 6 hours
{:ok, task} = Piano.Scheduler.ScheduledTask.create(%{
  name: "Progress Check",
  task_type: :custom_prompt,
  cron_expression: "0 */6 * * *",
  config: %{
    prompt: "Review my active projects and suggest next steps based on recent activity."
  },
  target_user_id: user_id
})
```

### Querying Task History

```elixir
# Get recent executions for a task
Piano.Scheduler.TaskExecution
|> Ash.Query.for_read(:recent_for_task, %{scheduled_task_id: task_id, limit: 5})
|> Ash.read()

# Check scheduler status
{:ok, status} = Piano.Scheduler.status()
# Returns: %{running_tasks_count: 2, last_poll_at: ~U[2026-01-31 10:00:00Z], ...}
```

## Telegram Commands

Add to `Piano.Telegram.BotV2`:

```elixir
command("tasks", description: "List your scheduled tasks")
command("addtask", description: "Add a new scheduled task")
command("runtask", description: "Run a task immediately")

def handle({:command, :tasks, msg}, context) do
  user = get_or_create_user(msg.from, :telegram)
  
  tasks = 
    Piano.Scheduler.ScheduledTask
    |> Ash.Query.for_read(:for_user, %{user_id: user.id})
    |> Ash.read!()
  
  if Enum.empty?(tasks) do
    answer(context, "You have no scheduled tasks. Use /addtask to create one.")
  else
    task_list = Enum.map_join(tasks, "\n", fn t ->
      status = if t.enabled, do: "✅", else: "⏸️"
      next_run = if t.next_run_at, do: "(next: #{format_time(t.next_run_at)})", else: ""
      "#{status} #{t.name} #{next_run}"
    end)
    
    answer(context, "Your scheduled tasks:\n#{task_list}")
  end
end

def handle({:command, :runtask, msg}, context) do
  # Extract task name from message
  task_name = msg.text |> String.trim()
  
  if task_name == "" do
    answer(context, "Usage: /runtask <task_name>")
  else
    user = get_or_create_user(msg.from, :telegram)
    
    # Find task by name
    case find_task_by_name(user.id, task_name) do
      {:ok, task} ->
        Piano.Scheduler.TaskRunner.run(task)
        answer(context, "Task '#{task_name}' executed. Check /tasks for results.")
        
      {:error, :not_found} ->
        answer(context, "Task '#{task_name}' not found. Use /tasks to see available tasks.")
    end
  end
end
```

## Benefits

1. **Proactive Agent**: Agent can now reach out to users, not just respond
2. **Background Processing**: Long-running tasks don't block user interactions
3. **Consistent Schedule**: Cron-based reliability
4. **Audit Trail**: Complete history of all autonomous actions
5. **User Control**: Per-user tasks with enable/disable
6. **Resource Management**: Limits concurrent tasks to prevent overload

## Security Considerations

1. Tasks run with user's context - respect their permissions
2. Audit all autonomous actions in TaskExecution
3. Rate limit task creation to prevent abuse
4. Validate all config parameters
5. Timeout long-running tasks

This system transforms Piano from purely reactive to proactive, enabling the agent to be a true assistant that anticipates needs and acts autonomously.
