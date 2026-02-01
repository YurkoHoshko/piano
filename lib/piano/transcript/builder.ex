defmodule Piano.Transcript.Builder do
  @moduledoc """
  Builds transcripts directly from thread/read response.

  No event conversion - just formats the raw response data.
  """

  @doc """
  Builds transcript from thread/read response.
  """
  @spec from_thread_response(map()) :: String.t()
  def from_thread_response(response) when is_map(response) do
    # Handle both result wrapped and unwrapped responses
    result = response["result"] || response
    thread = result["thread"] || %{}
    turns = result["turns"] || thread["turns"] || []

    header = format_header(thread)

    turns_text =
      turns
      |> Enum.with_index(1)
      |> Enum.map(fn {turn, idx} -> format_turn(turn, idx) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

    if turns_text == "" do
      header <> "\n📝 _No messages in this thread._"
    else
      header <> "\n\n" <> turns_text <> "\n\n🏁 **End of Transcript**"
    end
  end

  defp format_header(thread) do
    thread_id = thread["id"] || "unknown"
    created = thread["createdAt"] || "unknown"

    """
    📄 **THREAD TRANSCRIPT**
    ════════════════════════════════════════

    🆔 **Thread ID:** `#{thread_id}`
    📅 **Created:** #{created}
    """
  end

  defp format_turn(turn, idx) do
    items = turn["items"] || []

    entries =
      items
      |> Enum.map(&format_item/1)
      |> Enum.reject(&is_nil/1)

    case entries do
      [] ->
        nil

      _ ->
        status = turn["status"] || "unknown"
        status_emoji = status_emoji(status)

        """
        🔄 **Turn #{idx}** #{status_emoji}
        ────────────────────────────────────────

        #{Enum.join(entries, "\n\n")}
        """
        |> String.trim()
    end
  end

  defp status_emoji("completed"), do: "✅"
  defp status_emoji("failed"), do: "❌"
  defp status_emoji("interrupted"), do: "⏹️"
  defp status_emoji(_), do: "❓"

  defp format_item(%{"type" => "userMessage"} = item) do
    text = item["text"] || extract_content(item["content"]) || ""
    if text != "", do: "👤 **You:**\n#{text}"
  end

  defp format_item(%{"type" => "agentMessage"} = item) do
    text = item["text"] || extract_content(item["content"]) || ""
    if text != "", do: "🤖 **Assistant:**\n#{text}"
  end

  defp format_item(%{"type" => "commandExecution"} = item) do
    cmd = item["command"] || []
    cmd_str = if is_list(cmd), do: Enum.join(cmd, " "), else: inspect(cmd)
    output = (item["result"] && item["result"]["output"]) || item["stdout"] || ""

    if output != "" do
      "💻 **Command:** `#{cmd_str}`\n```\n#{output}\n```"
    else
      "💻 **Command:** `#{cmd_str}`"
    end
  end

  defp format_item(%{"type" => "fileChange"} = item) do
    path = item["path"] || "unknown"
    change_type = item["changeType"] || "modified"
    emoji = if change_type in ["created", "added"], do: "📄", else: "📝"
    "#{emoji} **File:** `#{path}` (#{change_type})"
  end

  defp format_item(%{"type" => "mcpToolCall"} = item) do
    format_mcp_tool_call(item)
  end

  defp format_item(%{"type" => "mcp_tool_call"} = item) do
    format_mcp_tool_call(item)
  end

  defp format_item(%{"type" => "webSearch"} = item) do
    query = item["query"] || ""
    "🔍 **Search:** \"#{query}\""
  end

  defp format_item(%{"type" => "reasoning"} = item) do
    text = item["text"] || extract_content(item["content"]) || ""
    if text != "", do: "💭 **Reasoning:**\n#{text}"
  end

  defp format_item(_), do: nil

  # Helper functions must come after all format_item clauses
  defp format_mcp_tool_call(item) do
    tool = item["tool"] || item["name"] || "unknown"
    server = item["server"] || "unknown"
    arguments = item["arguments"] || item["params"] || %{}
    result = item["result"]

    args_str =
      if map_size(arguments) > 0 do
        Enum.map_join(arguments, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
      else
        ""
      end

    base = "🔌 **MCP Tool:** `#{tool}` (server: `#{server}`)"

    with_args = if args_str != "", do: "#{base}\n  Args: #{args_str}", else: base

    if result do
      result_str =
        case result do
          %{"content" => [%{"text" => text}]} ->
            # Truncate long results
            if String.length(text) > 200 do
              String.slice(text, 0, 200) <> "..."
            else
              text
            end

          other ->
            inspect(other, limit: 100)
        end

      "#{with_args}\n  Result: #{result_str}"
    else
      with_args
    end
  end

  defp extract_content([%{"type" => "text", "text" => text} | _]), do: text
  defp extract_content([%{"type" => "outputText", "text" => text} | _]), do: text
  defp extract_content([_ | rest]), do: extract_content(rest)
  defp extract_content(text) when is_binary(text), do: text
  defp extract_content(_), do: nil
end
