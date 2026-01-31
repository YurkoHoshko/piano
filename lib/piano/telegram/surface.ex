defmodule Piano.Telegram.Surface do
  @moduledoc """
  Telegram surface implementation for the Piano.Surface protocol.

  Parses `reply_to` strings like "telegram:<chat_id>:<message_id>" and
  provides callbacks for updating Telegram messages during interaction lifecycle.

  Also provides direct API wrappers for ExGram functions.

  ## Features

  - Rich progress updates with emoji indicators
  - Expandable tool call details (<tg-spoiler> for tool calls)
  - First 100 chars preview of tool calls
  - Complete transcript generation including all agent actions
  """

  defstruct [:chat_id, :message_id]

  @type t :: %__MODULE__{
          chat_id: integer(),
          message_id: integer()
        }

  @doc """
  Parse a reply_to string into a Telegram surface struct.

  ## Examples

      iex> Piano.Telegram.Surface.parse("telegram:123456:-789")
      {:ok, %Piano.Telegram.Surface{chat_id: 123456, message_id: -789}}

      iex> Piano.Telegram.Surface.parse("liveview:abc")
      :error
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse("telegram:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [chat_id_str, message_id_str] ->
        with {chat_id, ""} <- Integer.parse(chat_id_str),
             {message_id, ""} <- Integer.parse(message_id_str) do
          {:ok, %__MODULE__{chat_id: chat_id, message_id: message_id}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def parse(_), do: :error

  @doc """
  Build a reply_to string from chat_id and message_id.
  """
  @spec build_reply_to(integer(), integer()) :: String.t()
  def build_reply_to(chat_id, message_id) do
    "telegram:#{chat_id}:#{message_id}"
  end

  @doc """
  Send a placeholder message and return the reply_to string.
  """
  @spec send_placeholder(integer(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def send_placeholder(chat_id, text \\ "⏳ Processing...") do
    case send_message(chat_id, text) do
      {:ok, %{message_id: message_id}} ->
        {:ok, build_reply_to(chat_id, message_id)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Update the placeholder message with new text.
  """
  @spec update_message(t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def update_message(%__MODULE__{chat_id: chat_id, message_id: message_id}, text, opts \\ []) do
    edit_message_text(chat_id, message_id, text, opts)
  end

  @doc """
  Send a message to a chat.
  """
  @spec send_message(integer(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def send_message(chat_id, text, opts \\ []) do
    ExGram.send_message(chat_id, text, opts)
  end

  @doc """
  Send a chat action (typing, etc.).
  """
  @spec send_chat_action(integer(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def send_chat_action(chat_id, action, opts \\ []) do
    ExGram.send_chat_action(chat_id, action, opts)
  end

  @doc """
  Edit an existing message text.
  """
  @spec edit_message_text(integer(), integer(), String.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def edit_message_text(chat_id, message_id, text, opts \\ []) do
    ExGram.edit_message_text(text, [chat_id: chat_id, message_id: message_id] ++ opts)
  end

  @doc """
  Answer a callback query.
  """
  @spec answer_callback_query(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def answer_callback_query(callback_query_id, opts \\ []) do
    ExGram.answer_callback_query(callback_query_id, opts)
  end

  @doc """
  Send a document to a chat.
  """
  @spec send_document(integer(), any(), keyword()) :: {:ok, any()} | {:error, any()}
  def send_document(chat_id, document, opts \\ []) do
    ExGram.send_document(chat_id, document, opts)
  end

  @doc """
  Build a prompt for the given Telegram message.
  Handles fetching participant count and chat history internally.
  """
  @spec prompt(map() | struct(), String.t()) :: String.t()
  def prompt(%{chat: %{id: chat_id, type: chat_type}} = msg, text) do
    participants = 
      if chat_type in ["group", "supergroup"] do
        case ExGram.get_chat_member_count(chat_id) do
          {:ok, count} when is_integer(count) -> count
          _ -> nil
        end
      else
        nil
      end

    recent =
      if chat_type in ["group", "supergroup"] do
        message_id = Map.get(msg, :message_id) || Map.get(msg, "message_id")
        Piano.Telegram.ContextWindow.recent(chat_id,
          mode: :since_last_tag_or_last_n,
          limit: 15,
          exclude_message_id: message_id
        )
      else
        []
      end

    Piano.Telegram.Prompt.build(msg, text, participants: participants, recent: recent)
  end
end

defimpl Piano.Surface, for: Piano.Telegram.Surface do
  alias Piano.Telegram.Surface, as: TelegramSurface
  alias Piano.Telegram.Transcript
  alias Piano.Surface.Context
  alias Piano.Codex.Events
  require Ash.Query

  @telegram_output_preview_max 500
  @tool_preview_max 100

  # ============================================================================
  # Turn Lifecycle
  # ============================================================================

  def on_turn_started(surface, context, _params) do
    emoji = pick_emoji(context)
    status_line = format_status_line(context, "thinking...")
    
    message = "#{emoji} <b>Processing</b>\n\n#{status_line}"
    TelegramSurface.update_message(surface, message, parse_mode: "HTML")
  end

  def on_turn_completed(surface, context, params) do
    response = extract_response(context, params)
    tool_summary = build_tool_summary(context)
    
    message = format_completion_message(response, tool_summary, context)
    TelegramSurface.update_message(surface, message, parse_mode: "HTML")
  end

  # ============================================================================
  # Item Lifecycle with Rich Updates
  # ============================================================================

  def on_item_started(surface, context, params) do
    case summarize_item_event(context, params, :started) do
      nil ->
        {:ok, :noop}

      {emoji, line, details} ->
        message = format_progress_message(context, emoji, line, details, :started)
        TelegramSurface.update_message(surface, message, parse_mode: "HTML")
    end
  end

  def on_item_completed(surface, context, params) do
    case summarize_item_event(context, params, :completed) do
      nil ->
        {:ok, :noop}

      {emoji, line, details} ->
        message = format_progress_message(context, emoji, line, details, :completed)
        TelegramSurface.update_message(surface, message, parse_mode: "HTML")
    end
  end

  def on_agent_message_delta(_surface, _context, _params) do
    # Keep pending updates focused on milestones/tool output (no streaming spam).
    {:ok, :noop}
  end

  def on_approval_required(surface, _context, params) do
    item_type = get_in(params, ["item", "type"]) || params["type"]
    emoji = approval_emoji(item_type)
    
    message = "#{emoji} <b>Approval Required</b>\n\n#{format_approval_details(params)}"
    TelegramSurface.update_message(surface, message, parse_mode: "HTML")
  end

  def send_thread_transcript(surface, thread_data) do
    Transcript.send_transcript(surface.chat_id, thread_data)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Pick appropriate emoji based on context/event type
  defp pick_emoji(%Context{event: %Events.TurnStarted{}}), do: "⏳"
  defp pick_emoji(%Context{event: %Events.TurnCompleted{status: :failed}}), do: "❌"
  defp pick_emoji(%Context{event: %Events.TurnCompleted{status: :interrupted}}), do: "⏹️"
  defp pick_emoji(%Context{}), do: "🤖"
  defp pick_emoji(_), do: "⏳"

  defp approval_emoji("commandExecution"), do: "⚠️"
  defp approval_emoji("fileChange"), do: "📝"
  defp approval_emoji("applyPatch"), do: "🔧"
  defp approval_emoji(_), do: "⚠️"

  # Format status line showing context
  defp format_status_line(%Context{interaction: %{original_message: msg}}, status) do
    preview = truncate_line(msg, 50)
    "<i>#{escape_html(preview)}</i>\n#{status}"
  end

  defp format_status_line(%Context{turn_id: turn_id}, status) when is_binary(turn_id) do
    "Turn: <code>#{truncate_line(turn_id, 30)}</code>\n#{status}"
  end

  defp format_status_line(_context, status), do: status

  # Extract response text from context/params
  defp extract_response(%Context{interaction: %{response: response}}, _params) when is_binary(response) do
    response
  end

  defp extract_response(_context, params) do
    params["response"] ||
      get_in(params, ["turn", "result", "text"]) ||
      get_in(params, ["result", "text"]) ||
      "✅ Done"
  end

  # Build tool summary from interaction items
  defp build_tool_summary(%Context{interaction: nil}), do: nil
  
  defp build_tool_summary(%Context{interaction: interaction}) do
    tool_types = [:command_execution, :file_change, :mcp_tool_call]

    case Ash.read(Piano.Core.InteractionItem, action: :list_by_interaction, args: %{interaction_id: interaction.id}) do
      {:ok, items} ->
        tool_items = Enum.filter(items, &(&1.type in tool_types))

        if Enum.empty?(tool_items) do
          nil
        else
          Enum.map(tool_items, &format_tool_item/1)
        end

      {:error, _} ->
        nil
    end
  end

  defp build_tool_summary(_context), do: nil

  # Format individual tool items with emoji and preview
  defp format_tool_item(%{type: :command_execution, payload: payload}) do
    command = payload["item"]["command"] || payload["command"] || []
    cmd_str = if is_list(command), do: Enum.join(command, " "), else: inspect(command)
    preview = truncate_line(cmd_str, @tool_preview_max)
    
    "<b>⚙️ Command:</b> <tg-spoiler><code>#{escape_html(preview)}</code></tg-spoiler>"
  end

  defp format_tool_item(%{type: :file_change, payload: payload}) do
    path = payload["item"]["path"] || payload["path"] || "unknown"
    "<b>📝 File:</b> <code>#{escape_html(path)}</code>"
  end

  defp format_tool_item(%{type: :mcp_tool_call, payload: payload}) do
    tool_name = payload["item"]["tool"] || payload["tool"] || payload["name"] || "unknown"
    args = payload["item"]["arguments"] || payload["arguments"] || %{}
    args_preview = if args == %{}, do: "", else: " #{truncate_line(inspect(args), @tool_preview_max - 20)}"
    
    "<b>🔧 Tool:</b> <code>#{escape_html(to_string(tool_name))}</code> <tg-spoiler>#{escape_html(args_preview)}</tg-spoiler>"
  end

  defp format_tool_item(%{type: :web_search, payload: payload}) do
    query = payload["item"]["query"] || payload["query"] || "search"
    "<b>🔍 Search:</b> #{escape_html(truncate_line(query, @tool_preview_max))}"
  end

  defp format_tool_item(_), do: nil

  # Format the final completion message
  defp format_completion_message(response, nil, context) do
    emoji = pick_emoji(context)
    "#{emoji}\n\n#{escape_html(response)}"
  end

  defp format_completion_message(response, tool_items, context) do
    emoji = pick_emoji(context)
    
    tool_lines =
      tool_items
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    if tool_lines == "" do
      "#{emoji}\n\n#{escape_html(response)}"
    else
      """
      #{emoji}

      #{escape_html(response)}

      <b>Actions taken:</b>
      #{tool_lines}
      """
    end
  end

  # Summarize item events with emoji indicators
  defp summarize_item_event(_context, params, phase) do
    item = params["item"] || %{}
    type = item["type"] || params["type"]

    case type do
      "reasoning" ->
        text = get_in(item, ["text"]) || get_in(item, ["summary"]) || get_in(item, ["content"])
        emoji = if phase == :completed, do: "✨", else: "💭"
        {emoji, "thinking#{status_suffix(params, phase)}", format_thinking_preview(text)}

      "commandExecution" ->
        cmd = get_in(item, ["command"]) || get_in(item, ["input", "command"]) || get_in(item, ["payload", "command"])
        cmd_str = cond do
          is_list(cmd) -> Enum.join(cmd, " ")
          is_binary(cmd) -> cmd
          true -> "command"
        end
        
        output = extract_item_output(params)
        emoji = if phase == :completed, do: "✅", else: "⚙️"
        preview = truncate_line(cmd_str, @tool_preview_max)
        {emoji, "executing: #{preview}#{status_suffix(params, phase)}", output}

      "fileChange" ->
        path = get_in(item, ["path"]) || get_in(item, ["input", "path"]) || get_in(item, ["payload", "path"])
        output = extract_item_output(params)
        emoji = if phase == :completed, do: "✅", else: "📝"
        display = if is_binary(path), do: path, else: "file change"
        {emoji, "editing: #{truncate_line(display, @tool_preview_max)}#{status_suffix(params, phase)}", output}

      "mcpToolCall" ->
        tool = get_in(item, ["tool"]) || get_in(item, ["name"]) || get_in(item, ["payload", "tool"])
        output = extract_item_output(params)
        emoji = if phase == :completed, do: "✅", else: "🔧"
        display = if tool, do: "tool: #{tool}", else: "tool call"
        {emoji, "#{display}#{status_suffix(params, phase)}", output}

      "webSearch" ->
        query = get_in(item, ["query"]) || get_in(item, ["input", "query"]) || get_in(item, ["payload", "query"])
        output = extract_item_output(params)
        emoji = if phase == :completed, do: "✅", else: "🔍"
        display = if is_binary(query), do: "search: #{query}", else: "search"
        {emoji, "#{display}#{status_suffix(params, phase)}", output}

      "agentMessage" ->
        # Don't show progress for agent messages - they'll appear in final output
        nil

      _ ->
        nil
    end
  end

  defp format_thinking_preview(nil), do: ""
  defp format_thinking_preview(text) when is_binary(text), do: truncate_line(text, @tool_preview_max)
  defp format_thinking_preview(_), do: ""

  defp format_progress_message(context, emoji, line, details, phase) do
    status_line = format_status_line(context, "")
    phase_indicator = if phase == :started, do: "<i>in progress...</i>", else: ""
    
    output_preview = 
      if details && details != "" do
        preview = truncate_line(details, @telegram_output_preview_max)
        "\n\n<tg-spoiler><code>#{escape_html(preview)}</code></tg-spoiler>"
      else
        ""
      end

    """
    #{emoji} <b>#{escape_html(String.capitalize(line))}</b> #{phase_indicator}
    #{if status_line != "", do: "\n" <> status_line, else: ""}
    #{output_preview}
    """
    |> String.trim()
  end

  defp format_approval_details(params) do
    item = params["item"] || %{}
    item_type = item["type"] || params["type"]
    
    case item_type do
      "commandExecution" ->
        cmd = item["command"] || []
        cmd_str = if is_list(cmd), do: Enum.join(cmd, " "), else: inspect(cmd)
        reason = params["reason"] || item["reason"]
        
        details = "<code>#{escape_html(cmd_str)}</code>"
        details = if reason, do: details <> "\n<i>#{escape_html(reason)}</i>", else: details
        details
        
      "fileChange" ->
        path = item["path"] || "unknown"
        reason = params["reason"] || item["reason"]
        
        details = "File: <code>#{escape_html(path)}</code>"
        details = if reason, do: details <> "\n<i>#{escape_html(reason)}</i>", else: details
        details
        
      _ ->
        "This action requires your approval."
    end
  end

  defp status_suffix(params, phase) do
    if phase == :completed do
      status =
        get_in(params, ["item", "status"]) ||
          params["status"] ||
          get_in(params, ["result", "status"])

      cond do
        status in ["failed", "error"] -> " (failed)"
        status in ["declined"] -> " (declined)"
        status in ["completed", "success", "ok"] -> " (done)"
        is_binary(status) -> " (#{status})"
        Map.has_key?(params, "error") -> " (failed)"
        true -> " (done)"
      end
    else
      ""
    end
  end

  defp extract_item_output(params) do
    output =
      get_in(params, ["item", "output"]) ||
        get_in(params, ["item", "result"]) ||
        get_in(params, ["item", "stdout"]) ||
        get_in(params, ["item", "stderr"]) ||
        get_in(params, ["item", "message"]) ||
        get_in(params, ["result", "output"]) ||
        get_in(params, ["result"]) ||
        params["output"]

    coerce_text(output)
  end

  defp coerce_text(nil), do: ""
  defp coerce_text(text) when is_binary(text), do: text
  defp coerce_text(%{"text" => text}) when is_binary(text), do: text
  defp coerce_text(%{text: text}) when is_binary(text), do: text
  defp coerce_text(other) when is_map(other) or is_list(other) do
    inspect(other, limit: 50, printable_limit: 800)
  end
  defp coerce_text(other), do: to_string(other)

  defp truncate_line(text, max_len) when is_binary(text) and is_integer(max_len) do
    text = String.trim(text)

    if String.length(text) <= max_len do
      text
    else
      String.slice(text, 0, max_len - 1) <> "…"
    end
  end

  defp truncate_line(other, _max_len), do: truncate_line(to_string(other), 50)

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(other), do: escape_html(to_string(other))
end
