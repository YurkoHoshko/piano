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
    defstruct [:message, :codex_error_info, :raw_params]

    @type t :: %__MODULE__{
            message: String.t(),
            codex_error_info: map() | nil,
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

    case method do
      # Turn events - IDs are at top level
      "turn/started" ->
        {:ok,
         %TurnStarted{
           turn_id: params["turnId"],
           thread_id: params["threadId"],
           input_items: get_in(params, ["turn", "input"]) || [],
           raw_params: params
         }}

      "turn/completed" ->
        status = parse_status(get_in(params, ["turn", "status"]))

        {:ok,
         %TurnCompleted{
           turn_id: params["turnId"],
           thread_id: params["threadId"],
           status: status,
           error: get_in(params, ["turn", "error"]),
           items: get_in(params, ["turn", "items"]) || [],
           usage: parse_usage(params),
           raw_params: params
         }}

      "turn/diff/updated" ->
        {:ok,
         %TurnDiffUpdated{
           turn_id: params["turnId"],
           thread_id: params["threadId"],
           diff: params["diff"] || "",
           raw_params: params
         }}

      "turn/plan/updated" ->
        {:ok,
         %TurnPlanUpdated{
           turn_id: params["turnId"],
           thread_id: params["threadId"],
           plan: params["plan"] || %{},
           raw_params: params
         }}

      # Item events - IDs can be in item or at top level
      "item/started" ->
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

      "item/completed" ->
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

      # Delta events - IDs are at top level
      "item/agentMessage/delta" ->
        {:ok,
         %AgentMessageDelta{
           item_id: params["itemId"],
           turn_id: params["turnId"],
           delta: params["delta"] || "",
           raw_params: params
         }}

      "item/reasoning/textDelta" ->
        {:ok,
         %ReasoningDelta{
           item_id: params["itemId"],
           turn_id: params["turnId"],
           delta: params["delta"] || "",
           raw_params: params
         }}

      "item/commandExecution/outputDelta" ->
        {:ok,
         %CommandOutputDelta{
           item_id: params["itemId"],
           turn_id: params["turnId"],
           output: params["output"] || "",
           raw_params: params
         }}

      "item/fileChange/outputDelta" ->
        {:ok,
         %FileChangeOutputDelta{
           item_id: params["itemId"],
           turn_id: params["turnId"],
           output: params["output"] || "",
           raw_params: params
         }}

      # Thread events - thread_id is nested in params["thread"]["id"]
      "thread/started" ->
        {:ok,
         %ThreadStarted{
           thread_id: get_in(params, ["thread", "id"]),
           raw_params: params
         }}

      "thread/archived" ->
        {:ok,
         %ThreadArchived{
           thread_id: get_in(params, ["thread", "id"]),
           raw_params: params
         }}

      "thread/tokenUsage/updated" ->
        {:ok,
         %ThreadTokenUsageUpdated{
           thread_id: params["threadId"],
           usage: parse_usage(params),
           rate_limits: params["rateLimits"],
           raw_params: params
         }}

      # Account events
      "account/updated" ->
        {:ok,
         %AccountUpdated{
           account: params["account"],
           raw_params: params
         }}

      "account/login/completed" ->
        {:ok,
         %AccountLoginCompleted{
           account: params["account"],
           raw_params: params
         }}

      "account/rateLimits/updated" ->
        {:ok,
         %AccountRateLimitsUpdated{
           rate_limits: params["rateLimits"],
           raw_params: params
         }}

      # Approval events - IDs are at top level
      "item/commandExecution/requestApproval" ->
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

      "item/fileChange/requestApproval" ->
        {:ok,
         %FileChangeRequestApproval{
           item_id: params["itemId"],
           turn_id: params["turnId"],
           thread_id: params["threadId"],
           path: params["path"] || "",
           reason: params["reason"],
           raw_params: params
         }}

      "applyPatch/approval" ->
        {:ok,
         %ApplyPatchApproval{
           item_id: params["itemId"],
           turn_id: params["turnId"],
           thread_id: params["threadId"],
           patch: params["patch"] || "",
           reason: params["reason"],
           raw_params: params
         }}

      # MCP tool events - IDs are at top level
      "item/mcpToolCall/progress" ->
        {:ok,
         %McpToolCallProgress{
           item_id: params["itemId"],
           turn_id: params["turnId"],
           tool: params["tool"] || "",
           progress: params["progress"] || %{},
           raw_params: params
         }}

      # Error/Warning events
      "error" ->
        {:ok,
         %Error{
           message: params["message"] || "Unknown error",
           codex_error_info: params["codexErrorInfo"],
           raw_params: params
         }}

      "warning" ->
        {:ok,
         %Warning{
           message: params["message"] || "Unknown warning",
           raw_params: params
         }}

      # Legacy v1 event names (for backward compatibility)
      "codex/event/task_started" ->
        parse_event("turn/started", params)

      "codex/event/task_completed" ->
        parse_event("turn/completed", params)

      "codex/event/item_started" ->
        parse_event("item/started", params)

      "codex/event/item_completed" ->
        parse_event("item/completed", params)

      # Legacy v1 agent message event
      "codex/event/agent_message" ->
        {:ok,
         %AgentMessage{
           turn_id: params["id"],
           thread_id: params["conversationId"],
           message: get_in(params, ["msg", "message"]),
           raw_params: params
         }}

      # Legacy v1 user message event (includes images)
      "codex/event/user_message" ->
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

      # Legacy v1 task complete event (like turn/completed with last message)
      "codex/event/task_complete" ->
        parse_event("turn/completed", %{
          "turnId" => params["id"],
          "threadId" => params["conversationId"],
          "turn" => %{
            "id" => params["id"],
            "threadId" => params["conversationId"],
            "status" => "completed",
            "result" => %{"text" => get_in(params, ["msg", "last_agent_message"])}
          }
        })

      # Unknown event
      _ ->
        {:error, {:unknown_event_method, method, params}}
    end
  end

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
end
