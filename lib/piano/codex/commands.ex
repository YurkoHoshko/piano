defmodule Piano.Codex.Commands do
  @moduledoc """
  Structured commands for the Codex app-server protocol.

  This module provides Elixir structs and helper functions for all client-sent
  requests to the Codex app-server, based on the official JSON-RPC protocol schemas.

  ## Command Types

  ### Initialization
  - `Initialize` - Initialize the Codex client session
  - `Initialized` - Confirm initialization complete

  ### Thread Management
  - `ThreadStart` - Create a new conversation thread
  - `ThreadResume` - Resume an existing thread
  - `ThreadFork` - Branch a thread into a new one
  - `ThreadRead` - Read thread data without subscribing
  - `ThreadList` - List all threads
  - `ThreadArchive` - Archive a thread
  - `ThreadUnarchive` - Restore an archived thread
  - `ThreadRollback` - Drop last N turns from context

  ### Turn Management
  - `TurnStart` - Start a new turn with user input
  - `TurnInterrupt` - Interrupt/cancel an in-progress turn

  ### Command Execution
  - `CommandExec` - Execute a command in the sandbox

  ### Account & Auth
  - `AccountRead` - Check current auth status
  - `AccountLoginStart` - Start login flow (API key or ChatGPT)
  - `AccountLoginCancel` - Cancel an in-progress login
  - `AccountLogout` - Log out
  - `AccountRateLimitsRead` - Get current rate limits

  ### Configuration
  - `ConfigRead` - Read server configuration
  - `ConfigValueWrite` - Write a configuration value

  ### Skills
  - `SkillsList` - List available skills
  - `SkillsConfigWrite` - Enable/disable skills

  ## Usage

  Build and serialize commands for sending to Codex:

      iex> command = Piano.Codex.Commands.ThreadStart.new(model: "gpt-5.1-codex")
      iex> Piano.Codex.Commands.to_json_rpc(command, request_id: 1)
      %{"method" => "thread/start", "id" => 1, "params" => %{...}}

  Or use the convenience functions:

      iex> Piano.Codex.Commands.thread_start(model: "gpt-5.1-codex", request_id: 1)
      %{"method" => "thread/start", "id" => 1, "params" => %{...}}
  """

  # ============================================================================
  # Support Types
  # ============================================================================

  defmodule SandboxPolicy do
    @moduledoc "Sandbox security policy for command execution."
    defstruct [:type, :writable_roots, :network_access]

    @type type :: :read_only | :workspace_write | :full_access

    @type t :: %__MODULE__{
            type: type(),
            writable_roots: list(String.t()) | nil,
            network_access: boolean()
          }

    @doc """
    Creates a new sandbox policy.

    ## Options

    - `:type` - Policy type (`:read_only`, `:workspace_write`, or `:full_access`)
    - `:writable_roots` - List of paths the agent can write to
    - `:network_access` - Whether network access is allowed
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        type: opts[:type] || :workspace_write,
        writable_roots: opts[:writable_roots],
        network_access: Keyword.get(opts, :network_access, true)
      }
    end

    @doc """
    Converts the policy to a map for JSON serialization.
    """
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = policy) do
      base = %{"type" => serialize_type(policy.type)}

      base =
        if policy.writable_roots do
          Map.put(base, "writableRoots", policy.writable_roots)
        else
          base
        end

      if policy.network_access do
        Map.put(base, "networkAccess", policy.network_access)
      else
        base
      end
    end

    defp serialize_type(:read_only), do: "readOnly"
    defp serialize_type(:workspace_write), do: "workspaceWrite"
    defp serialize_type(:full_access), do: "fullAccess"
    defp serialize_type(other) when is_atom(other), do: to_string(other)
    defp serialize_type(other), do: other
  end

  defmodule InputItem do
    @moduledoc "Input item for turn start."
    defstruct [:type, :text, :url, :path, :name]

    @type item_type :: :text | :image | :local_image | :skill

    @type t :: %__MODULE__{
            type: item_type(),
            text: String.t() | nil,
            url: String.t() | nil,
            path: String.t() | nil,
            name: String.t() | nil
          }

    @doc "Create a text input item."
    @spec text(String.t()) :: t()
    def text(content) do
      %__MODULE__{type: :text, text: content}
    end

    @doc "Create an image input item from URL."
    @spec image(String.t()) :: t()
    def image(url) do
      %__MODULE__{type: :image, url: url}
    end

    @doc "Create a local image input item from file path."
    @spec local_image(String.t()) :: t()
    def local_image(path) do
      %__MODULE__{type: :local_image, path: path}
    end

    @doc "Create a skill reference input item."
    @spec skill(String.t(), String.t()) :: t()
    def skill(name, path) do
      %__MODULE__{type: :skill, name: name, path: path}
    end

    @doc """
    Converts the input item to a map for JSON serialization.
    """
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{type: :text, text: text}), do: %{"type" => "text", "text" => text}

    def to_map(%__MODULE__{type: :image, url: url}), do: %{"type" => "image", "url" => url}

    def to_map(%__MODULE__{type: :local_image, path: path}),
      do: %{"type" => "localImage", "path" => path}

    def to_map(%__MODULE__{type: :skill, name: name, path: path}),
      do: %{"type" => "skill", "name" => name, "path" => path}
  end

  # ============================================================================
  # Command Structs
  # ============================================================================

  defmodule Initialize do
    @moduledoc "Initialize the Codex client session."
    defstruct [:client_info, :capabilities]

    @type client_info :: %{name: String.t(), title: String.t() | nil, version: String.t()}

    @type t :: %__MODULE__{
            client_info: client_info(),
            capabilities: map() | nil
          }

    @doc """
    Creates a new initialize command.

    ## Options

    - `:name` - Client name (required, used for compliance/logging)
    - `:title` - Human-readable client title
    - `:version` - Client version
    - `:capabilities` - Optional client capabilities map
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        client_info: %{
          name: opts[:name] || "piano_client",
          title: opts[:title],
          version: opts[:version] || "0.1.0"
        },
        capabilities: opts[:capabilities]
      }
    end
  end

  defmodule Initialized do
    @moduledoc "Confirm initialization is complete (sent after initialize response)."
    defstruct []

    @type t :: %__MODULE__{}

    @doc "Creates a new initialized command."
    @spec new() :: t()
    def new, do: %__MODULE__{}
  end

  defmodule ThreadStart do
    @moduledoc "Create a new conversation thread."
    defstruct [
      :model,
      :effort,
      :summary,
      :cwd,
      :approval_policy,
      :sandbox_policy,
      :input_items,
      :output_schema
    ]

    @type t :: %__MODULE__{
            model: String.t() | nil,
            effort: String.t() | nil,
            summary: String.t() | nil,
            cwd: String.t() | nil,
            approval_policy: String.t() | nil,
            sandbox_policy: SandboxPolicy.t() | nil,
            input_items: list(InputItem.t()),
            output_schema: map() | nil
          }

    @doc """
    Creates a new thread start command.

    ## Options

    - `:model` - Model to use (e.g., "gpt-5.1-codex")
    - `:effort` - Effort level ("low", "medium", "high")
    - `:summary` - Summary style ("concise", "detailed")
    - `:cwd` - Working directory for the thread
    - `:approval_policy` - Default approval policy
    - `:sandbox_policy` - SandboxPolicy struct or nil
    - `:input` - List of InputItem structs or string for single text input
    - `:output_schema` - JSON schema for structured output
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      input_items =
        case opts[:input] do
          nil -> []
          items when is_list(items) -> items
          text when is_binary(text) -> [InputItem.text(text)]
        end

      %__MODULE__{
        model: opts[:model],
        effort: opts[:effort],
        summary: opts[:summary],
        cwd: opts[:cwd],
        approval_policy: opts[:approval_policy],
        sandbox_policy: opts[:sandbox_policy],
        input_items: input_items,
        output_schema: opts[:output_schema]
      }
    end
  end

  defmodule ThreadResume do
    @moduledoc "Resume an existing thread."
    defstruct [:thread_id]

    @type t :: %__MODULE__{
            thread_id: String.t()
          }

    @doc "Creates a new thread resume command."
    @spec new(String.t()) :: t()
    def new(thread_id) when is_binary(thread_id) do
      %__MODULE__{thread_id: thread_id}
    end
  end

  defmodule ThreadFork do
    @moduledoc "Fork a thread into a new one."
    defstruct [:thread_id, :turn_id]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            turn_id: String.t() | nil
          }

    @doc """
    Creates a new thread fork command.

    ## Options

    - `:turn_id` - Turn ID to fork from (optional, forks from end if not provided)
    """
    @spec new(String.t(), keyword()) :: t()
    def new(thread_id, opts \\ []) when is_binary(thread_id) do
      %__MODULE__{
        thread_id: thread_id,
        turn_id: opts[:turn_id]
      }
    end
  end

  defmodule ThreadRead do
    @moduledoc "Read thread data without loading into memory."
    defstruct [:thread_id, :include_turns]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            include_turns: boolean()
          }

    @doc """
    Creates a new thread read command.

    ## Options

    - `:include_turns` - Whether to include turn data (default: true)
    """
    @spec new(String.t(), keyword()) :: t()
    def new(thread_id, opts \\ []) when is_binary(thread_id) do
      %__MODULE__{
        thread_id: thread_id,
        include_turns: Keyword.get(opts, :include_turns, true)
      }
    end
  end

  defmodule ThreadList do
    @moduledoc "List all threads with pagination."
    defstruct [:cursor, :limit, :include_archived, :source_kinds]

    @type t :: %__MODULE__{
            cursor: String.t() | nil,
            limit: integer() | nil,
            include_archived: boolean(),
            source_kinds: list(String.t()) | nil
          }

    @doc """
    Creates a new thread list command.

    ## Options

    - `:cursor` - Pagination cursor
    - `:limit` - Maximum results to return
    - `:include_archived` - Include archived threads
    - `:source_kinds` - Filter by source ("cli", "vscode", "appServer", etc.)
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        cursor: opts[:cursor],
        limit: opts[:limit],
        include_archived: Keyword.get(opts, :include_archived, false),
        source_kinds: opts[:source_kinds]
      }
    end
  end

  defmodule ThreadArchive do
    @moduledoc "Archive a thread."
    defstruct [:thread_id]

    @type t :: %__MODULE__{
            thread_id: String.t()
          }

    @doc "Creates a new thread archive command."
    @spec new(String.t()) :: t()
    def new(thread_id) when is_binary(thread_id) do
      %__MODULE__{thread_id: thread_id}
    end
  end

  defmodule ThreadUnarchive do
    @moduledoc "Unarchive (restore) a thread."
    defstruct [:thread_id]

    @type t :: %__MODULE__{
            thread_id: String.t()
          }

    @doc "Creates a new thread unarchive command."
    @spec new(String.t()) :: t()
    def new(thread_id) when is_binary(thread_id) do
      %__MODULE__{thread_id: thread_id}
    end
  end

  defmodule ThreadRollback do
    @moduledoc "Drop last N turns from thread context."
    defstruct [:thread_id, :num_turns]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            num_turns: integer()
          }

    @doc """
    Creates a new thread rollback command.

    ## Parameters

    - `thread_id` - Thread to rollback
    - `num_turns` - Number of user turns to remove
    """
    @spec new(String.t(), integer()) :: t()
    def new(thread_id, num_turns) when is_binary(thread_id) and is_integer(num_turns) do
      %__MODULE__{
        thread_id: thread_id,
        num_turns: num_turns
      }
    end
  end

  defmodule TurnStart do
    @moduledoc "Start a new turn in a thread."
    defstruct [
      :thread_id,
      :input_items,
      :model,
      :effort,
      :summary,
      :cwd,
      :approval_policy,
      :sandbox_policy,
      :output_schema
    ]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            input_items: list(InputItem.t()),
            model: String.t() | nil,
            effort: String.t() | nil,
            summary: String.t() | nil,
            cwd: String.t() | nil,
            approval_policy: String.t() | nil,
            sandbox_policy: SandboxPolicy.t() | nil,
            output_schema: map() | nil
          }

    @doc """
    Creates a new turn start command.

    ## Parameters

    - `thread_id` - Thread to start turn in
    - `input` - List of InputItem structs or string for single text input

    ## Options

    - `:model` - Override model for this turn
    - `:effort` - Override effort level
    - `:summary` - Override summary style
    - `:cwd` - Override working directory
    - `:approval_policy` - Override approval policy
    - `:sandbox_policy` - Override sandbox policy
    - `:output_schema` - JSON schema for structured output
    """
    @spec new(String.t(), keyword()) :: t()
    def new(thread_id, opts \\ []) when is_binary(thread_id) do
      input_items =
        case opts[:input] do
          nil -> []
          items when is_list(items) -> items
          text when is_binary(text) -> [InputItem.text(text)]
        end

      %__MODULE__{
        thread_id: thread_id,
        input_items: input_items,
        model: opts[:model],
        effort: opts[:effort],
        summary: opts[:summary],
        cwd: opts[:cwd],
        approval_policy: opts[:approval_policy],
        sandbox_policy: opts[:sandbox_policy],
        output_schema: opts[:output_schema]
      }
    end
  end

  defmodule TurnInterrupt do
    @moduledoc "Interrupt/cancel an in-progress turn."
    defstruct [:thread_id, :turn_id]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            turn_id: String.t()
          }

    @doc "Creates a new turn interrupt command."
    @spec new(String.t(), String.t()) :: t()
    def new(thread_id, turn_id) when is_binary(thread_id) and is_binary(turn_id) do
      %__MODULE__{
        thread_id: thread_id,
        turn_id: turn_id
      }
    end
  end

  defmodule CommandExec do
    @moduledoc "Execute a single command in the sandbox."
    defstruct [:command, :cwd, :sandbox_policy, :timeout_ms, :external_sandbox]

    @type t :: %__MODULE__{
            command: list(String.t()),
            cwd: String.t() | nil,
            sandbox_policy: SandboxPolicy.t() | nil,
            timeout_ms: integer() | nil,
            external_sandbox: map() | nil
          }

    @doc """
    Creates a new command exec command.

    ## Parameters

    - `command` - List of command arguments (e.g., ["ls", "-la"])

    ## Options

    - `:cwd` - Working directory
    - `:sandbox_policy` - Sandbox policy
    - `:timeout_ms` - Timeout in milliseconds
    - `:external_sandbox` - External sandbox configuration
    """
    @spec new(list(String.t()), keyword()) :: t()
    def new(command, opts \\ []) when is_list(command) do
      %__MODULE__{
        command: command,
        cwd: opts[:cwd],
        sandbox_policy: opts[:sandbox_policy],
        timeout_ms: opts[:timeout_ms],
        external_sandbox: opts[:external_sandbox]
      }
    end
  end

  defmodule AccountRead do
    @moduledoc "Read current account/auth status."
    defstruct [:refresh_token]

    @type t :: %__MODULE__{
            refresh_token: boolean()
          }

    @doc """
    Creates a new account read command.

    ## Options

    - `:refresh_token` - Force token refresh
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        refresh_token: Keyword.get(opts, :refresh_token, false)
      }
    end
  end

  defmodule AccountLoginStart do
    @moduledoc "Start a login flow."
    defstruct [:type, :api_key]

    @type login_type :: :api_key | :chatgpt

    @type t :: %__MODULE__{
            type: login_type(),
            api_key: String.t() | nil
          }

    @doc """
    Creates a new login start command.

    ## Parameters

    - `type` - `:api_key` or `:chatgpt`

    ## Options

    - `:api_key` - API key (required for `:api_key` type)
    """
    @spec new(login_type(), keyword()) :: t()
    def new(type, opts \\ []) do
      %__MODULE__{
        type: type,
        api_key: opts[:api_key]
      }
    end
  end

  defmodule AccountLoginCancel do
    @moduledoc "Cancel an in-progress login."
    defstruct [:login_id]

    @type t :: %__MODULE__{
            login_id: String.t()
          }

    @doc "Creates a new login cancel command."
    @spec new(String.t()) :: t()
    def new(login_id) when is_binary(login_id) do
      %__MODULE__{login_id: login_id}
    end
  end

  defmodule AccountLogout do
    @moduledoc "Log out."
    defstruct []

    @type t :: %__MODULE__{}

    @doc "Creates a new logout command."
    @spec new() :: t()
    def new, do: %__MODULE__{}
  end

  defmodule AccountRateLimitsRead do
    @moduledoc "Read current rate limits."
    defstruct []

    @type t :: %__MODULE__{}

    @doc "Creates a new rate limits read command."
    @spec new() :: t()
    def new, do: %__MODULE__{}
  end

  defmodule ConfigRead do
    @moduledoc "Read server configuration."
    defstruct []

    @type t :: %__MODULE__{}

    @doc "Creates a new config read command."
    @spec new() :: t()
    def new, do: %__MODULE__{}
  end

  defmodule ConfigValueWrite do
    @moduledoc "Write a configuration value."
    defstruct [:key, :value]

    @type t :: %__MODULE__{
            key: String.t(),
            value: any()
          }

    @doc "Creates a new config value write command."
    @spec new(String.t(), any()) :: t()
    def new(key, value) when is_binary(key) do
      %__MODULE__{key: key, value: value}
    end
  end

  defmodule SkillsList do
    @moduledoc "List available skills."
    defstruct [:cwds, :force_reload]

    @type t :: %__MODULE__{
            cwds: list(String.t()) | nil,
            force_reload: boolean()
          }

    @doc """
    Creates a new skills list command.

    ## Options

    - `:cwds` - List of working directories to scope skills
    - `:force_reload` - Force reload of skills from disk
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        cwds: opts[:cwds],
        force_reload: Keyword.get(opts, :force_reload, false)
      }
    end
  end

  defmodule SkillsConfigWrite do
    @moduledoc "Enable/disable a skill."
    defstruct [:path, :enabled]

    @type t :: %__MODULE__{
            path: String.t(),
            enabled: boolean()
          }

    @doc "Creates a new skills config write command."
    @spec new(String.t(), boolean()) :: t()
    def new(path, enabled) when is_binary(path) and is_boolean(enabled) do
      %__MODULE__{path: path, enabled: enabled}
    end
  end

  defmodule ReviewStart do
    @moduledoc "Start a review session."
    defstruct [:thread_id, :target, :delivery]

    @type target :: :uncommitted_changes | :base_branch | :commit | {:custom, String.t()}
    @type delivery :: :inline | :detached

    @type t :: %__MODULE__{
            thread_id: String.t(),
            target: target(),
            delivery: delivery()
          }

    @doc """
    Creates a new review start command.

    ## Parameters

    - `thread_id` - Thread to review

    ## Options

    - `:target` - Review target (`:uncommitted_changes`, `:base_branch`, `:commit`, or `{:custom, ref}`)
    - `:delivery` - `:inline` (current thread) or `:detached` (new thread)
    """
    @spec new(String.t(), keyword()) :: t()
    def new(thread_id, opts \\ []) when is_binary(thread_id) do
      %__MODULE__{
        thread_id: thread_id,
        target: opts[:target] || :uncommitted_changes,
        delivery: opts[:delivery] || :inline
      }
    end
  end

  # ============================================================================
  # JSON-RPC Serialization
  # ============================================================================

  @type command ::
          Initialize.t()
          | Initialized.t()
          | ThreadStart.t()
          | ThreadResume.t()
          | ThreadFork.t()
          | ThreadRead.t()
          | ThreadList.t()
          | ThreadArchive.t()
          | ThreadUnarchive.t()
          | ThreadRollback.t()
          | TurnStart.t()
          | TurnInterrupt.t()
          | CommandExec.t()
          | AccountRead.t()
          | AccountLoginStart.t()
          | AccountLoginCancel.t()
          | AccountLogout.t()
          | AccountRateLimitsRead.t()
          | ConfigRead.t()
          | ConfigValueWrite.t()
          | SkillsList.t()
          | SkillsConfigWrite.t()
          | ReviewStart.t()

  @doc """
  Converts a command struct to a JSON-RPC request map.

  ## Parameters

  - `command` - A command struct from this module
  - `opts` - Options including:
    - `:request_id` - The JSON-RPC request ID (required for requests)

  ## Returns

  A map ready for JSON serialization with `method`, `id`, and `params` keys.
  """
  @spec to_json_rpc(command(), keyword()) :: map()
  def to_json_rpc(command, opts \\ [])

  # Initialize (requires request_id)
  def to_json_rpc(%Initialize{} = cmd, opts) do
    params = %{
      "clientInfo" => %{
        "name" => cmd.client_info.name,
        "version" => cmd.client_info.version
      }
    }

    params =
      if cmd.client_info.title do
        put_in(params, ["clientInfo", "title"], cmd.client_info.title)
      else
        params
      end

    params =
      if cmd.capabilities do
        Map.put(params, "capabilities", cmd.capabilities)
      else
        params
      end

    %{
      "method" => "initialize",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  # Initialized (notification - no id)
  def to_json_rpc(%Initialized{} = _cmd, _opts) do
    %{
      "method" => "initialized",
      "params" => %{}
    }
  end

  # Thread commands
  def to_json_rpc(%ThreadStart{} = cmd, opts) do
    params =
      %{}
      |> put_optional("model", cmd.model)
      |> put_optional("effort", cmd.effort)
      |> put_optional("summary", cmd.summary)
      |> put_optional("cwd", cmd.cwd)
      |> put_optional("approvalPolicy", cmd.approval_policy)
      |> put_optional("sandbox", cmd.sandbox_policy, &SandboxPolicy.to_map/1)
      |> put_optional("outputSchema", cmd.output_schema)

    params =
      if cmd.input_items != [] do
        input = Enum.map(cmd.input_items, &InputItem.to_map/1)
        Map.put(params, "input", input)
      else
        params
      end

    %{
      "method" => "thread/start",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%ThreadResume{} = cmd, opts) do
    %{
      "method" => "thread/resume",
      "id" => opts[:request_id],
      "params" => %{"threadId" => cmd.thread_id}
    }
  end

  def to_json_rpc(%ThreadFork{} = cmd, opts) do
    params = %{"threadId" => cmd.thread_id}
    params = put_optional(params, "turnId", cmd.turn_id)

    %{
      "method" => "thread/fork",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%ThreadRead{} = cmd, opts) do
    params = %{"threadId" => cmd.thread_id, "includeTurns" => cmd.include_turns}

    %{
      "method" => "thread/read",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%ThreadList{} = cmd, opts) do
    params =
      %{}
      |> put_optional("cursor", cmd.cursor)
      |> put_optional("limit", cmd.limit)
      |> put_optional("sourceKinds", cmd.source_kinds)

    params = if cmd.include_archived, do: Map.put(params, "includeArchived", true), else: params

    %{
      "method" => "thread/list",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%ThreadArchive{} = cmd, opts) do
    %{
      "method" => "thread/archive",
      "id" => opts[:request_id],
      "params" => %{"threadId" => cmd.thread_id}
    }
  end

  def to_json_rpc(%ThreadUnarchive{} = cmd, opts) do
    %{
      "method" => "thread/unarchive",
      "id" => opts[:request_id],
      "params" => %{"threadId" => cmd.thread_id}
    }
  end

  def to_json_rpc(%ThreadRollback{} = cmd, opts) do
    %{
      "method" => "thread/rollback",
      "id" => opts[:request_id],
      "params" => %{
        "threadId" => cmd.thread_id,
        "numTurns" => cmd.num_turns
      }
    }
  end

  # Turn commands
  def to_json_rpc(%TurnStart{} = cmd, opts) do
    params =
      %{
        "threadId" => cmd.thread_id,
        "input" => Enum.map(cmd.input_items, &InputItem.to_map/1)
      }
      |> put_optional("model", cmd.model)
      |> put_optional("effort", cmd.effort)
      |> put_optional("summary", cmd.summary)
      |> put_optional("cwd", cmd.cwd)
      |> put_optional("approvalPolicy", cmd.approval_policy)
      |> put_optional("sandbox", cmd.sandbox_policy, &SandboxPolicy.to_map/1)
      |> put_optional("outputSchema", cmd.output_schema)

    %{
      "method" => "turn/start",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%TurnInterrupt{} = cmd, opts) do
    %{
      "method" => "turn/interrupt",
      "id" => opts[:request_id],
      "params" => %{
        "threadId" => cmd.thread_id,
        "turnId" => cmd.turn_id
      }
    }
  end

  # Command execution
  def to_json_rpc(%CommandExec{} = cmd, opts) do
    params =
      %{
        "command" => cmd.command
      }
      |> put_optional("cwd", cmd.cwd)
      |> put_optional("sandbox", cmd.sandbox_policy, &SandboxPolicy.to_map/1)
      |> put_optional("timeoutMs", cmd.timeout_ms)
      |> put_optional("externalSandbox", cmd.external_sandbox)

    %{
      "method" => "command/exec",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  # Account commands
  def to_json_rpc(%AccountRead{} = cmd, opts) do
    params = if cmd.refresh_token, do: %{"refreshToken" => true}, else: %{}

    %{
      "method" => "account/read",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%AccountLoginStart{} = cmd, opts) do
    params =
      case cmd.type do
        :api_key -> %{"type" => "apiKey", "apiKey" => cmd.api_key}
        :chatgpt -> %{"type" => "chatgpt"}
        _ -> %{"type" => to_string(cmd.type)}
      end

    %{
      "method" => "account/login/start",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%AccountLoginCancel{} = cmd, opts) do
    %{
      "method" => "account/login/cancel",
      "id" => opts[:request_id],
      "params" => %{"loginId" => cmd.login_id}
    }
  end

  def to_json_rpc(%AccountLogout{} = _cmd, opts) do
    %{
      "method" => "account/logout",
      "id" => opts[:request_id],
      "params" => %{}
    }
  end

  def to_json_rpc(%AccountRateLimitsRead{} = _cmd, opts) do
    %{
      "method" => "account/rateLimits/read",
      "id" => opts[:request_id],
      "params" => %{}
    }
  end

  # Config commands
  def to_json_rpc(%ConfigRead{} = _cmd, opts) do
    %{
      "method" => "config/read",
      "id" => opts[:request_id],
      "params" => %{}
    }
  end

  def to_json_rpc(%ConfigValueWrite{} = cmd, opts) do
    %{
      "method" => "config/value/write",
      "id" => opts[:request_id],
      "params" => %{
        "key" => cmd.key,
        "value" => cmd.value
      }
    }
  end

  # Skills commands
  def to_json_rpc(%SkillsList{} = cmd, opts) do
    params =
      %{}
      |> put_optional("cwds", cmd.cwds)

    params = if cmd.force_reload, do: Map.put(params, "forceReload", true), else: params

    %{
      "method" => "skills/list",
      "id" => opts[:request_id],
      "params" => params
    }
  end

  def to_json_rpc(%SkillsConfigWrite{} = cmd, opts) do
    %{
      "method" => "skills/config/write",
      "id" => opts[:request_id],
      "params" => %{
        "path" => cmd.path,
        "enabled" => cmd.enabled
      }
    }
  end

  # Review command
  def to_json_rpc(%ReviewStart{} = cmd, opts) do
    target_str =
      case cmd.target do
        :uncommitted_changes -> "uncommittedChanges"
        :base_branch -> "baseBranch"
        :commit -> "commit"
        {:custom, ref} -> ref
        other -> to_string(other)
      end

    delivery_str = if cmd.delivery == :detached, do: "detached", else: "inline"

    %{
      "method" => "review/start",
      "id" => opts[:request_id],
      "params" => %{
        "threadId" => cmd.thread_id,
        "target" => target_str,
        "delivery" => delivery_str
      }
    }
  end

  # ============================================================================
  # Convenience Functions
  # ============================================================================

  @doc """
  Creates a thread/start request map.

  ## Options

  Same as `ThreadStart.new/1`, plus:
  - `:request_id` - JSON-RPC request ID (required)
  """
  @spec thread_start(keyword()) :: map()
  def thread_start(opts \\ []) do
    opts
    |> ThreadStart.new()
    |> to_json_rpc(request_id: opts[:request_id])
  end

  @doc """
  Creates a turn/start request map.

  ## Parameters

  - `thread_id` - Thread to start turn in
  - `input` - Input items or text string

  ## Options

  Same as `TurnStart.new/2`, plus:
  - `:request_id` - JSON-RPC request ID (required)
  """
  @spec turn_start(String.t(), keyword()) :: map()
  def turn_start(thread_id, opts \\ []) do
    thread_id
    |> TurnStart.new(opts)
    |> to_json_rpc(request_id: opts[:request_id])
  end

  @doc """
  Creates a thread/read request map.

  ## Parameters

  - `thread_id` - Thread to read

  ## Options

  - `:include_turns` - Include turn data (default: true)
  - `:request_id` - JSON-RPC request ID (required)
  """
  @spec thread_read(String.t(), keyword()) :: map()
  def thread_read(thread_id, opts \\ []) do
    thread_id
    |> ThreadRead.new(include_turns: opts[:include_turns])
    |> to_json_rpc(request_id: opts[:request_id])
  end

  @doc """
  Creates an initialize request map.

  ## Options

  - `:name` - Client name
  - `:title` - Client title
  - `:version` - Client version
  - `:request_id` - JSON-RPC request ID (required)
  """
  @spec initialize(keyword()) :: map()
  def initialize(opts \\ []) do
    opts
    |> Initialize.new()
    |> to_json_rpc(request_id: opts[:request_id])
  end

  @doc """
  Creates an initialized notification map (no request_id needed).
  """
  @spec initialized() :: map()
  def initialized do
    Initialized.new()
    |> to_json_rpc()
  end

  @doc """
  Creates an account/read request map.

  ## Options

  - `:refresh_token` - Force token refresh
  - `:request_id` - JSON-RPC request ID (required)
  """
  @spec account_read(keyword()) :: map()
  def account_read(opts \\ []) do
    opts
    |> AccountRead.new()
    |> to_json_rpc(request_id: opts[:request_id])
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, []), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
  defp put_optional(map, _key, nil, _transform), do: map
  defp put_optional(map, key, value, transform), do: Map.put(map, key, transform.(value))
end
