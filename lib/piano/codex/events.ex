defmodule Piano.Codex.Events do
  @moduledoc """
  Structured events from the Codex app-server protocol.

  This module provides Elixir structs and helper functions for all server-sent
  events (notifications) from the Codex app-server, based on the official
  JSON-RPC protocol schemas.

  ## Event Types

  ### Turn Lifecycle
  - `TurnStarted` - Emitted when a turn begins processing
  - `TurnCompleted` - Emitted when a turn finishes (success, failure, or interrupted)
  - `TurnDiffUpdated` - Incremental diff updates during the turn
  - `TurnPlanUpdated` - Plan updates during agent execution

  ### Item Lifecycle
  - `ItemStarted` - An item (message, tool call, etc.) has started
  - `ItemCompleted` - An item has completed
  - `ItemDelta` - Streaming content updates for items

  ### Thread Lifecycle
  - `ThreadStarted` - A new thread was created
  - `ThreadArchived` - Thread was archived
  - `ThreadTokenUsageUpdated` - Token usage statistics updated

  ### Account & Auth
  - `AccountUpdated` - Account state changed
  - `AccountLoginCompleted` - Login flow completed
  - `AccountRateLimitsUpdated` - Rate limit status changed

  ### Approval Flows
  - `CommandExecutionRequestApproval` - Command needs approval
  - `FileChangeRequestApproval` - File change needs approval
  - `ApplyPatchApproval` - Patch application needs approval

  ## Usage

  Parse raw Codex events into structured types:

      iex> Piano.Codex.Events.parse(%{"method" => "turn/started", "params" => %{...}})
      {:ok, %Piano.Codex.Events.TurnStarted{...}}

  Pattern match on event types in consumers:

      case event do
        %Piano.Codex.Events.TurnStarted{} -> handle_turn_start(event)
        %Piano.Codex.Events.ItemCompleted{type: :command_execution} -> handle_command(event)
        _ -> :ok
      end
  """

  alias Piano.Codex.Events

  require Logger

  # ============================================================================
  # Item Types
  # ============================================================================

  @item_types [
    :user_message,
    :agent_message,
    :reasoning,
    :command_execution,
    :file_change,
    :mcp_tool_call,
    :web_search,
    :collab_tool_call,
    :image_view,
    :review_mode,
    :compacted,
    :unknown
  ]

  @type item_type :: unquote(Enum.reduce(@item_types, &{:|, [], [&1, &2]}))

  @doc """
  Maps a Codex item type string to a normalized atom.
  """
  @spec map_item_type(String.t() | atom() | nil) :: item_type()
  def map_item_type("userMessage"), do: :user_message
  def map_item_type("agentMessage"), do: :agent_message
  def map_item_type("reasoning"), do: :reasoning
  def map_item_type("commandExecution"), do: :command_execution
  def map_item_type("fileChange"), do: :file_change
  def map_item_type("mcpToolCall"), do: :mcp_tool_call
  def map_item_type("webSearch"), do: :web_search
  def map_item_type("collabToolCall"), do: :collab_tool_call
  def map_item_type("imageView"), do: :image_view
  def map_item_type("enteredReviewMode"), do: :review_mode
  def map_item_type("exitedReviewMode"), do: :review_mode
  def map_item_type("compacted"), do: :compacted
  def map_item_type(nil), do: :unknown
  def map_item_type(type) when is_atom(type), do: type
  def map_item_type(_), do: :unknown

  # ============================================================================
  # Turn Events
  # ============================================================================

  defmodule TurnStarted do
    @moduledoc "Emitted when a Codex turn begins processing."
    defstruct [:turn_id, :thread_id, :input_items, :raw_params]

    @type t :: %__MODULE__{
            turn_id: String.t(),
            thread_id: String.t(),
            input_items: list(map()),
            raw_params: map()
          }
  end

  defmodule TurnCompleted do
    @moduledoc "Emitted when a Codex turn completes (success, failure, or interrupted)."
    defstruct [:turn_id, :thread_id, :status, :error, :items, :usage, :raw_params]

    @type status :: :completed | :failed | :interrupted

    @type t :: %__MODULE__{
            turn_id: String.t(),
            thread_id: String.t(),
            status: status(),
            error: map() | nil,
            items: list(map()),
            usage: Events.TokenUsage.t() | nil,
            raw_params: map()
          }
  end

  defmodule TurnDiffUpdated do
    @moduledoc "Incremental diff updates during a turn."
    defstruct [:turn_id, :thread_id, :diff, :raw_params]

    @type t :: %__MODULE__{
            turn_id: String.t(),
            thread_id: String.t(),
            diff: String.t(),
            raw_params: map()
          }
  end

  defmodule TurnPlanUpdated do
    @moduledoc "Plan updates during agent execution."
    defstruct [:turn_id, :thread_id, :plan, :raw_params]

    @type t :: %__MODULE__{
            turn_id: String.t(),
            thread_id: String.t(),
            plan: map(),
            raw_params: map()
          }
  end

  # ============================================================================
  # Item Events
  # ============================================================================

  defmodule ItemStarted do
    @moduledoc "Emitted when an item (tool call, message, etc.) starts."
    defstruct [:item_id, :turn_id, :thread_id, :type, :item, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            thread_id: String.t(),
            type: Events.item_type(),
            item: map(),
            raw_params: map()
          }
  end

  defmodule ItemCompleted do
    @moduledoc "Emitted when an item completes."
    defstruct [:item_id, :turn_id, :thread_id, :type, :status, :item, :result, :raw_params]

    @type status :: :completed | :failed | :declined

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            thread_id: String.t(),
            type: Events.item_type(),
            status: status(),
            item: map(),
            result: map() | nil,
            raw_params: map()
          }
  end

  defmodule AgentMessage do
    @moduledoc "Legacy v1 event: Complete agent message (non-streaming)."
    defstruct [:turn_id, :thread_id, :message, :raw_params]

    @type t :: %__MODULE__{
            turn_id: String.t(),
            thread_id: String.t(),
            message: String.t(),
            raw_params: map()
          }
  end

  defmodule UserMessage do
    @moduledoc "Legacy v1 event: User message received (includes images)."
    defstruct [
      :turn_id,
      :thread_id,
      :message,
      :images,
      :local_images,
      :text_elements,
      :raw_params
    ]

    @type t :: %__MODULE__{
            turn_id: String.t(),
            thread_id: String.t(),
            message: String.t(),
            images: list(map()),
            local_images: list(map()),
            text_elements: list(map()),
            raw_params: map()
          }
  end

  defmodule AgentMessageDelta do
    @moduledoc "Streaming content delta for agent messages."
    defstruct [:item_id, :turn_id, :delta, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            delta: String.t(),
            raw_params: map()
          }
  end

  defmodule ReasoningDelta do
    @moduledoc "Streaming reasoning content delta."
    defstruct [:item_id, :turn_id, :delta, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            delta: String.t(),
            raw_params: map()
          }
  end

  defmodule CommandOutputDelta do
    @moduledoc "Streaming command execution output."
    defstruct [:item_id, :turn_id, :output, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            output: String.t(),
            raw_params: map()
          }
  end

  defmodule FileChangeOutputDelta do
    @moduledoc "Streaming file change output."
    defstruct [:item_id, :turn_id, :output, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            output: String.t(),
            raw_params: map()
          }
  end

  # ============================================================================
  # Thread Events
  # ============================================================================

  defmodule ThreadStarted do
    @moduledoc "Emitted when a new thread is created."
    defstruct [:thread_id, :raw_params]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            raw_params: map()
          }
  end

  defmodule ThreadArchived do
    @moduledoc "Emitted when a thread is archived."
    defstruct [:thread_id, :raw_params]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            raw_params: map()
          }
  end

  defmodule ThreadTokenUsageUpdated do
    @moduledoc "Token usage statistics updated for a thread."
    defstruct [:thread_id, :usage, :rate_limits, :raw_params]

    @type t :: %__MODULE__{
            thread_id: String.t(),
            usage: Events.TokenUsage.t() | nil,
            rate_limits: map() | nil,
            raw_params: map()
          }
  end

  # ============================================================================
  # Account Events
  # ============================================================================

  defmodule AccountUpdated do
    @moduledoc "Account state changed notification."
    defstruct [:account, :raw_params]

    @type t :: %__MODULE__{
            account: map(),
            raw_params: map()
          }
  end

  defmodule AccountLoginCompleted do
    @moduledoc "Login flow completed notification."
    defstruct [:account, :raw_params]

    @type t :: %__MODULE__{
            account: map(),
            raw_params: map()
          }
  end

  defmodule AccountRateLimitsUpdated do
    @moduledoc "Rate limit status changed notification."
    defstruct [:rate_limits, :raw_params]

    @type t :: %__MODULE__{
            rate_limits: map(),
            raw_params: map()
          }
  end

  # ============================================================================
  # Approval Events
  # ============================================================================

  defmodule CommandExecutionRequestApproval do
    @moduledoc "Command execution requires user approval."
    defstruct [:item_id, :turn_id, :thread_id, :command, :reason, :risk, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            thread_id: String.t(),
            command: list(String.t()),
            reason: String.t() | nil,
            risk: String.t() | nil,
            raw_params: map()
          }
  end

  defmodule FileChangeRequestApproval do
    @moduledoc "File change requires user approval."
    defstruct [:item_id, :turn_id, :thread_id, :path, :reason, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            thread_id: String.t(),
            path: String.t(),
            reason: String.t() | nil,
            raw_params: map()
          }
  end

  defmodule ApplyPatchApproval do
    @moduledoc "Patch application requires user approval."
    defstruct [:item_id, :turn_id, :thread_id, :patch, :reason, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            thread_id: String.t(),
            patch: String.t(),
            reason: String.t() | nil,
            raw_params: map()
          }
  end

  # ============================================================================
  # MCP Tool Events
  # ============================================================================

  defmodule McpToolCallProgress do
    @moduledoc "Progress update for MCP tool call."
    defstruct [:item_id, :turn_id, :tool, :progress, :raw_params]

    @type t :: %__MODULE__{
            item_id: String.t(),
            turn_id: String.t(),
            tool: String.t(),
            progress: map(),
            raw_params: map()
          }
  end

  # ============================================================================
  # Error Events
  # ============================================================================

  defmodule Error do
    @moduledoc "Error notification from the server."
    defstruct [:message, :codex_error_info, :turn_id, :thread_id, :will_retry, :raw_params]

    @type t :: %__MODULE__{
            message: String.t(),
            codex_error_info: map() | nil,
            turn_id: String.t() | nil,
            thread_id: String.t() | nil,
            will_retry: boolean() | nil,
            raw_params: map()
          }
  end

  defmodule Warning do
    @moduledoc "Warning notification from the server."
    defstruct [:message, :raw_params]

    @type t :: %__MODULE__{
            message: String.t(),
            raw_params: map()
          }
  end

  # ============================================================================
  # Support Types
  # ============================================================================

  defmodule TokenUsage do
    @moduledoc "Token usage statistics."
    defstruct [:input_tokens, :output_tokens, :total_tokens]

    @type t :: %__MODULE__{
            input_tokens: integer() | nil,
            output_tokens: integer() | nil,
            total_tokens: integer() | nil
          }
  end

  # ============================================================================
  # Event Parsing
  # ============================================================================

  @type event ::
          TurnStarted.t()
          | TurnCompleted.t()
          | TurnDiffUpdated.t()
          | TurnPlanUpdated.t()
          | ItemStarted.t()
          | ItemCompleted.t()
          | AgentMessage.t()
          | AgentMessageDelta.t()
          | ReasoningDelta.t()
          | CommandOutputDelta.t()
          | FileChangeOutputDelta.t()
          | ThreadStarted.t()
          | ThreadArchived.t()
          | ThreadTokenUsageUpdated.t()
          | AccountUpdated.t()
          | AccountLoginCompleted.t()
          | AccountRateLimitsUpdated.t()
          | CommandExecutionRequestApproval.t()
          | FileChangeRequestApproval.t()
          | ApplyPatchApproval.t()
          | McpToolCallProgress.t()
          | Error.t()
          | Warning.t()

  @doc """
  Parses a raw Codex event map into a structured event struct.

  ## Parameters

  - `raw` - The raw event map with "method" and "params" keys

  ## Returns

  - `{:ok, event}` - Successfully parsed event struct
  - `{:error, reason}` - Failed to parse the event
  """
  @spec parse(map()) :: {:ok, event()} | {:error, term()}
  def parse(%{"method" => method, "params" => params}) do
    parse_event(method, params)
  end

  def parse(%{method: method, params: params}) do
    parse_event(method, params)
  end

  def parse(other) do
    {:error, {:invalid_event, other}}
  end

  defp parse_event(method, params) do
    if Application.get_env(:piano, :log_codex_event_debug, false) do
      Logger.debug(
        "DEBUG: Parsing event method=#{inspect(method, limit: 200)} is_binary=#{is_binary(method)} bytes=#{if is_binary(method), do: :binary.bin_to_list(method), else: :not_binary}"
      )
    end

    do_parse_event(method, params)
  end

  # Break down event parsing by category to reduce cyclomatic complexity

  defp do_parse_event("turn/started", params) do
    {:ok,
     %TurnStarted{
       turn_id: params["turnId"],
       thread_id: params["threadId"],
       input_items: get_in(params, ["turn", "input"]) || [],
       raw_params: params
     }}
  end

  defp do_parse_event("turn/completed", params) do
    status = parse_status(get_in(params, ["turn", "status"]))
    turn_id = params["turnId"] || get_in(params, ["turn", "id"])

    {:ok,
     %TurnCompleted{
       turn_id: turn_id,
       thread_id: params["threadId"],
       status: status,
       error: get_in(params, ["turn", "error"]),
       items: get_in(params, ["turn", "items"]) || [],
       usage: parse_usage(params),
       raw_params: params
     }}
  end

  defp do_parse_event("turn/diff/updated", params) do
    {:ok,
     %TurnDiffUpdated{
       turn_id: params["turnId"],
       thread_id: params["threadId"],
       diff: params["diff"] || "",
       raw_params: params
     }}
  end

  defp do_parse_event("turn/plan/updated", params) do
    {:ok,
     %TurnPlanUpdated{
       turn_id: params["turnId"],
       thread_id: params["threadId"],
       plan: params["plan"] || %{},
       raw_params: params
     }}
  end

  defp do_parse_event("item/started", params) do
    item = params["item"] || %{}

    {:ok,
     %ItemStarted{
       item_id: item["id"] || item["itemId"],
       turn_id: params["turnId"] || item["turnId"],
       thread_id: params["threadId"] || item["threadId"],
       type: map_item_type(item["type"]),
       item: item,
       raw_params: params
     }}
  end

  defp do_parse_event("item/completed", params) do
    item = params["item"] || %{}
    result = params["result"] || %{}

    {:ok,
     %ItemCompleted{
       item_id: item["id"] || item["itemId"],
       turn_id: params["turnId"] || item["turnId"],
       thread_id: params["threadId"] || item["threadId"],
       type: map_item_type(item["type"]),
       status: parse_item_status(item["status"]),
       item: item,
       result: result,
       raw_params: params
     }}
  end

  defp do_parse_event("item/agentMessage/delta", params) do
    {:ok,
     %AgentMessageDelta{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       delta: params["delta"] || "",
       raw_params: params
     }}
  end

  defp do_parse_event("item/reasoning/textDelta", params) do
    {:ok,
     %ReasoningDelta{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       delta: params["delta"] || "",
       raw_params: params
     }}
  end

  defp do_parse_event("item/commandExecution/outputDelta", params) do
    {:ok,
     %CommandOutputDelta{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       output: params["output"] || "",
       raw_params: params
     }}
  end

  defp do_parse_event("item/fileChange/outputDelta", params) do
    {:ok,
     %FileChangeOutputDelta{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       output: params["output"] || "",
       raw_params: params
     }}
  end

  defp do_parse_event("thread/started", params) do
    {:ok,
     %ThreadStarted{
       thread_id: get_in(params, ["thread", "id"]),
       raw_params: params
     }}
  end

  defp do_parse_event("thread/archived", params) do
    {:ok,
     %ThreadArchived{
       thread_id: get_in(params, ["thread", "id"]),
       raw_params: params
     }}
  end

  defp do_parse_event("thread/tokenUsage/updated", params) do
    {:ok,
     %ThreadTokenUsageUpdated{
       thread_id: params["threadId"],
       usage: parse_usage(params),
       rate_limits: params["rateLimits"],
       raw_params: params
     }}
  end

  defp do_parse_event("account/updated", params) do
    {:ok,
     %AccountUpdated{
       account: params["account"],
       raw_params: params
     }}
  end

  defp do_parse_event("account/login/completed", params) do
    {:ok,
     %AccountLoginCompleted{
       account: params["account"],
       raw_params: params
     }}
  end

  defp do_parse_event("account/rateLimits/updated", params) do
    {:ok,
     %AccountRateLimitsUpdated{
       rate_limits: params["rateLimits"],
       raw_params: params
     }}
  end

  defp do_parse_event("item/commandExecution/requestApproval", params) do
    {:ok,
     %CommandExecutionRequestApproval{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       thread_id: params["threadId"],
       command: params["command"] || [],
       reason: params["reason"],
       risk: params["risk"],
       raw_params: params
     }}
  end

  defp do_parse_event("item/fileChange/requestApproval", params) do
    {:ok,
     %FileChangeRequestApproval{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       thread_id: params["threadId"],
       path: params["path"] || "",
       reason: params["reason"],
       raw_params: params
     }}
  end

  defp do_parse_event("applyPatch/approval", params) do
    {:ok,
     %ApplyPatchApproval{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       thread_id: params["threadId"],
       patch: params["patch"] || "",
       reason: params["reason"],
       raw_params: params
     }}
  end

  defp do_parse_event("item/mcpToolCall/progress", params) do
    {:ok,
     %McpToolCallProgress{
       item_id: params["itemId"],
       turn_id: params["turnId"],
       tool: params["tool"] || "",
       progress: params["progress"] || %{},
       raw_params: params
     }}
  end

  defp do_parse_event("error", params) do
    {:ok,
     %Error{
       message: params["message"] || params["error"] || "Unknown error",
       codex_error_info: params["codexErrorInfo"],
       turn_id: params["turnId"],
       thread_id: params["threadId"],
       will_retry: params["willRetry"],
       raw_params: params
     }}
  end

  defp do_parse_event("warning", params) do
    {:ok,
     %Warning{
       message: params["message"] || "Unknown warning",
       raw_params: params
     }}
  end

  # Legacy v1 event names (forward to current handlers)
  defp do_parse_event("codex/event/task_started", params),
    do: do_parse_event("turn/started", params)

  defp do_parse_event("codex/event/task_completed", params),
    do: do_parse_event("turn/completed", params)

  defp do_parse_event("codex/event/item_started", params),
    do: do_parse_event("item/started", params)

  defp do_parse_event("codex/event/item_completed", params),
    do: do_parse_event("item/completed", params)

  defp do_parse_event("codex/event/agent_message", params) do
    {:ok,
     %AgentMessage{
       turn_id: params["id"],
       thread_id: params["conversationId"],
       message: get_in(params, ["msg", "message"]),
       raw_params: params
     }}
  end

  defp do_parse_event("codex/event/user_message", params) do
    {:ok,
     %UserMessage{
       turn_id: params["id"],
       thread_id: params["conversationId"],
       message: get_in(params, ["msg", "message"]),
       images: get_in(params, ["msg", "images"]) || [],
       local_images: get_in(params, ["msg", "local_images"]) || [],
       text_elements: get_in(params, ["msg", "text_elements"]) || [],
       raw_params: params
     }}
  end

  defp do_parse_event("codex/event/task_complete", params) do
    do_parse_event("turn/completed", %{
      "turnId" => params["id"],
      "threadId" => params["conversationId"],
      "turn" => %{
        "id" => params["id"],
        "threadId" => params["conversationId"],
        "status" => "completed",
        "result" => %{"text" => get_in(params, ["msg", "last_agent_message"])}
      }
    })
  end

  defp do_parse_event("codex/event/mcp_tool_call_begin", params) do
    do_parse_event("item/started", %{
      "itemId" => get_in(params, ["msg", "call_id"]),
      "turnId" => params["conversationId"],
      "threadId" => params["conversationId"],
      "item" => %{
        "id" => get_in(params, ["msg", "call_id"]),
        "type" => "mcpToolCall",
        "content" => get_in(params, ["msg", "invocation"])
      }
    })
  end

  defp do_parse_event("codex/event/mcp_tool_call_end", params) do
    do_parse_event("item/completed", %{
      "itemId" => get_in(params, ["msg", "call_id"]),
      "turnId" => params["conversationId"],
      "threadId" => params["conversationId"],
      "item" => %{
        "id" => get_in(params, ["msg", "call_id"]),
        "type" => "mcpToolCall",
        "content" => get_in(params, ["msg", "result"])
      }
    })
  end

  # Events to ignore
  defp do_parse_event("codex/event/mcp_startup_update", _), do: {:ok, :ignored}
  defp do_parse_event("codex/event/mcp_startup_complete", _), do: {:ok, :ignored}
  defp do_parse_event("codex/event/token_count", _), do: {:ok, :ignored}
  defp do_parse_event("codex/event/view_image_tool_call", _), do: {:ok, :ignored}
  defp do_parse_event("codex/event/stream_error", _), do: {:ok, :ignored}

  # Unknown event
  defp do_parse_event(method, params), do: {:error, {:unknown_event_method, method, params}}

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Extracts the turn ID from event parameters.
  """
  @spec extract_turn_id(map()) :: String.t() | nil
  def extract_turn_id(params) when is_map(params) do
    params["turnId"]
  end

  def extract_turn_id(_), do: nil

  @doc """
  Extracts the thread ID from event parameters.
  """
  @spec extract_thread_id(map()) :: String.t() | nil
  def extract_thread_id(params) when is_map(params) do
    params["threadId"]
  end

  def extract_thread_id(_), do: nil

  @doc """
  Extracts text content from various item content formats.
  """
  @spec extract_text_from_content(any()) :: String.t() | nil
  def extract_text_from_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "outputText", "text" => text} -> text
      %{"type" => "inputText", "text" => text} -> text
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")
  end

  def extract_text_from_content(%{"text" => text}) when is_binary(text), do: text
  def extract_text_from_content(text) when is_binary(text), do: text
  def extract_text_from_content(_), do: nil

  # Private helpers

  defp parse_status("completed"), do: :completed
  defp parse_status("success"), do: :completed
  defp parse_status("ok"), do: :completed
  defp parse_status("failed"), do: :failed
  defp parse_status("error"), do: :failed
  defp parse_status("interrupted"), do: :interrupted
  defp parse_status("cancelled"), do: :interrupted
  defp parse_status("canceled"), do: :interrupted
  defp parse_status(_), do: :completed

  defp parse_item_status("completed"), do: :completed
  defp parse_item_status("success"), do: :completed
  defp parse_item_status("failed"), do: :failed
  defp parse_item_status("error"), do: :failed
  defp parse_item_status("declined"), do: :declined
  defp parse_item_status(_), do: :completed

  defp parse_usage(params) do
    usage =
      get_in(params, ["turn", "usage"]) ||
        params["usage"]

    case usage do
      nil ->
        nil

      %{} = u ->
        %TokenUsage{
          input_tokens: normalize_int(u["inputTokens"]),
          output_tokens: normalize_int(u["outputTokens"]),
          total_tokens: normalize_int(u["totalTokens"])
        }
    end
  end

  defp normalize_int(nil), do: nil
  defp normalize_int(v) when is_integer(v), do: v

  defp normalize_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp normalize_int(_), do: nil
end

# ============================================================================
# Transcript Serializers - each event knows how to serialize itself
# ============================================================================

defimpl Piano.Transcript.Serializer, for: Piano.Codex.Events.AgentMessage do
  def to_transcript(event) do
    if event.message && event.message != "" do
      "🤖 **Assistant:**\n#{event.message}"
    end
  end
end

defimpl Piano.Transcript.Serializer, for: Piano.Codex.Events.ItemCompleted do
  def to_transcript(%{type: :user_message, item: item}) when is_map(item) do
    text = item["text"] || item["message"] || ""
    if text != "", do: "👤 **You:**\n#{text}"
  end

  def to_transcript(%{type: :agent_message, item: item, result: result}) when is_map(item) do
    text =
      item["text"] || item["message"] ||
        (is_map(result) && (result["text"] || result["message"])) ||
        ""

    if text != "", do: "🤖 **Assistant:**\n#{text}"
  end

  def to_transcript(%{type: :command_execution, item: item, result: result}) do
    cmd = (item && item["command"]) || []
    cmd_str = if is_list(cmd), do: Enum.join(cmd, " "), else: inspect(cmd)
    output = (result && result["output"]) || ""
    "💻 **Command:** `#{cmd_str}`\n```\n#{output}\n```"
  end

  def to_transcript(%{type: :file_change, item: item}) when is_map(item) do
    path = item["path"] || "unknown"
    change_type = item["changeType"] || "modified"
    emoji = if change_type in ["created", "added"], do: "📄", else: "📝"
    "#{emoji} **File:** `#{path}` (#{change_type})"
  end

  def to_transcript(%{type: :mcp_tool_call, item: item, result: result}) when is_map(item) do
    tool = item["tool"] || "unknown"
    # Extract result content if available
    result_text = extract_mcp_result_text(result)

    if result_text && result_text != "" do
      "🔌 **Tool:** `#{tool}`\n#{result_text}"
    else
      "🔌 **Tool:** `#{tool}`"
    end
  end

  # Fallback for mcp_tool_call without result field
  def to_transcript(%{type: :mcp_tool_call, item: item}) when is_map(item) do
    tool = item["tool"] || "unknown"
    "🔌 **Tool:** `#{tool}`"
  end

  def to_transcript(%{type: :web_search, item: item}) when is_map(item) do
    query = item["query"] || ""
    "🔍 **Search:** \"#{query}\""
  end

  def to_transcript(%{type: :reasoning, item: item}) when is_map(item) do
    text = extract_content_text(item["content"]) || item["text"] || ""
    if text != "", do: "💭 **Reasoning:**\n#{text}"
  end

  def to_transcript(_), do: nil

  defp extract_content_text([%{"type" => "text", "text" => text} | _]), do: text
  defp extract_content_text([%{"type" => "outputText", "text" => text} | _]), do: text
  defp extract_content_text([_ | rest]), do: extract_content_text(rest)
  defp extract_content_text(text) when is_binary(text), do: text
  defp extract_content_text(_), do: nil

  # Extract text from MCP tool call result
  # Handles various result formats from vision tools, etc.
  defp extract_mcp_result_text(nil), do: nil

  defp extract_mcp_result_text(%{"Ok" => %{"content" => content}}) when is_list(content) do
    # Extract text from content array
    result =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n", &(&1["text"] || ""))

    if result == "", do: nil, else: result
  end

  defp extract_mcp_result_text(%{"Ok" => ok_result}) when is_map(ok_result) do
    # Try to extract any text field from Ok result
    ok_result["text"] || ok_result["description"] || ok_result["result"]
  end

  defp extract_mcp_result_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_mcp_result_text(%{"description" => desc}) when is_binary(desc), do: desc
  defp extract_mcp_result_text(result) when is_binary(result), do: result
  defp extract_mcp_result_text(_), do: nil
end
