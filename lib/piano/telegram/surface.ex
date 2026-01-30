defmodule Piano.Telegram.Surface do
  @moduledoc """
  Telegram surface implementation for the Piano.Surface protocol.

  Parses `reply_to` strings like "telegram:<chat_id>:<message_id>" and
  provides callbacks for updating Telegram messages during interaction lifecycle.
  """

  alias Piano.Telegram.API

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
    case API.send_message(chat_id, text) do
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
    API.edit_message_text(chat_id, message_id, text, opts)
  end
end

defimpl Piano.Surface, for: Piano.Telegram.Surface do
  alias Piano.Telegram.Surface, as: TelegramSurface
  alias Piano.Telegram.Transcript
  alias Piano.Core.InteractionItem
  require Ash.Query

  @telegram_output_preview_max 500

  def on_turn_started(surface, _interaction, _params) do
    TelegramSurface.update_message(surface, "⏳ Processing…\n\nstarted")
  end

  def on_turn_completed(surface, interaction, _params) do
    response = interaction.response || "✅ Done"
    tool_summary = build_tool_summary(interaction.id)
    message = format_completion_message(response, tool_summary)
    TelegramSurface.update_message(surface, message, parse_mode: "HTML")
  end

  # Build a summary of tool calls (commands, file changes, etc.) for the turn.
  # Returns nil if no tool calls were made.
  defp build_tool_summary(interaction_id) do
    tool_types = [:command_execution, :file_change, :mcp_tool_call]

    case Ash.read(InteractionItem, action: :list_by_interaction, args: %{interaction_id: interaction_id}) do
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

  defp format_tool_item(%{type: :command_execution, payload: payload}) do
    command = payload["command"] || payload[:command] || []
    cmd_str = if is_list(command), do: Enum.join(command, " "), else: inspect(command)
    "$ #{escape_html(cmd_str)}"
  end

  defp format_tool_item(%{type: :file_change, payload: payload}) do
    path = payload["path"] || payload[:path] || "unknown"
    "📝 #{escape_html(path)}"
  end

  defp format_tool_item(%{type: :mcp_tool_call, payload: payload}) do
    tool_name = payload["tool"] || payload[:tool] || payload["name"] || payload[:name] || "unknown"
    args = payload["arguments"] || payload[:arguments] || %{}
    args_str = if args == %{}, do: "", else: " #{inspect(args)}"
    "🔧 #{escape_html(to_string(tool_name))}#{escape_html(args_str)}"
  end

  defp format_tool_item(_), do: nil

  # Format the final message with optional collapsible tool summary.
  # Uses Telegram's <tg-spoiler> for the collapsible section.
  defp format_completion_message(response, nil), do: escape_html(response)

  defp format_completion_message(response, tool_items) do
    tool_lines =
      tool_items
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    if tool_lines == "" do
      escape_html(response)
    else
      """
      #{escape_html(response)}

      <b>Tools used:</b>
      <tg-spoiler>#{tool_lines}</tg-spoiler>
      """
    end
  end

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(other), do: escape_html(to_string(other))

  def on_item_started(surface, _interaction, params) do
    case summarize_item_event(params, :started) do
      nil ->
        {:ok, :noop}

      {line, output} ->
        TelegramSurface.update_message(surface, progress_message(line, output))
    end
  end

  def on_item_completed(surface, _interaction, params) do
    case summarize_item_event(params, :completed) do
      nil ->
        {:ok, :noop}

      {line, output} ->
        TelegramSurface.update_message(surface, progress_message(line, output))
    end
  end

  def on_agent_message_delta(surface, _interaction, params) do
    # Keep pending updates focused on milestones/tool output (no streaming spam).
    _ = surface
    _ = params
    {:ok, :noop}
  end

  def on_approval_required(surface, _interaction, _params) do
    TelegramSurface.update_message(surface, "⚠️ Approval required")
  end

  def send_thread_transcript(surface, thread_data) do
    Transcript.send_transcript(surface.chat_id, thread_data)
  end

  defp summarize_item_event(params, phase) when phase in [:started, :completed] do
    item = params["item"] || %{}
    type = item["type"] || params["type"]

    case type do
      "reasoning" ->
        text =
          get_in(params, ["item", "text"]) ||
            get_in(params, ["item", "summary"]) ||
            get_in(params, ["item", "content"])

        status_suffix = status_suffix(params, phase)
        {"thinking#{status_suffix}", coerce_text(text)}

      "commandExecution" ->
        cmd =
          get_in(params, ["item", "command"]) ||
            get_in(params, ["item", "input", "command"]) ||
            get_in(params, ["item", "payload", "command"])

        cmd_str =
          cond do
            is_list(cmd) -> Enum.join(cmd, " ")
            is_binary(cmd) -> cmd
            true -> nil
          end

        output = extract_item_output(params)
        base = if cmd_str, do: "$ #{truncate_line(cmd_str, 120)}", else: "command"
        {base <> status_suffix(params, phase), output}

      "fileChange" ->
        path =
          get_in(params, ["item", "path"]) ||
            get_in(params, ["item", "input", "path"]) ||
            get_in(params, ["item", "payload", "path"])

        output = extract_item_output(params)
        base = if is_binary(path), do: "file #{truncate_line(path, 160)}", else: "file change"
        {base <> status_suffix(params, phase), output}

      "mcpToolCall" ->
        tool =
          get_in(params, ["item", "tool"]) ||
            get_in(params, ["item", "name"]) ||
            get_in(params, ["item", "payload", "tool"]) ||
            get_in(params, ["item", "payload", "name"])

        output = extract_item_output(params)
        base = if tool, do: "tool #{truncate_line(to_string(tool), 80)}", else: "tool call"
        {base <> status_suffix(params, phase), output}

      "webSearch" ->
        query =
          get_in(params, ["item", "query"]) ||
            get_in(params, ["item", "input", "query"]) ||
            get_in(params, ["item", "payload", "query"])

        output = extract_item_output(params)
        base = if is_binary(query), do: "search #{truncate_line(query, 80)}", else: "search"
        {base <> status_suffix(params, phase), output}

      _ ->
        nil
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

  defp truncate_line(text, max_len) when is_binary(text) and is_integer(max_len) do
    text = String.trim(text)

    if String.length(text) <= max_len do
      text
    else
      String.slice(text, 0, max_len - 1) <> "…"
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
        get_in(params, ["output"])

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

  defp progress_message(line, output) do
    output =
      output
      |> String.trim()
      |> maybe_truncate_head(@telegram_output_preview_max)

    parts =
      ["⏳ Processing…", String.trim(line)]
      |> maybe_add_section(output)

    Enum.join(parts, "\n\n")
  end

  defp maybe_truncate_head(text, max_len) when is_binary(text) and is_integer(max_len) do
    if String.length(text) <= max_len do
      text
    else
      String.slice(text, 0, max_len - 1) <> "…"
    end
  end

  defp maybe_add_section(parts, ""), do: parts
  defp maybe_add_section(parts, nil), do: parts
  defp maybe_add_section(parts, section) when is_binary(section), do: parts ++ [section]
end
