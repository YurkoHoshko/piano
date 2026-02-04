defmodule Piano.Telegram.Transcript do
  @moduledoc """
  Thread transcript formatting for Telegram.

  Converts Codex thread data into a human-readable Markdown transcript
  and sends it as a `.md` file attachment.

  ## Transcript Format

  The transcript includes:
  - Thread header with ID and metadata
  - Each turn with all items (user messages, agent messages, tool calls, reasoning)
  - Tool execution details (commands, file changes, MCP calls)
  - Token usage statistics
  """

  alias Piano.Telegram.Surface

  @doc """
  Send a formatted transcript to a Telegram chat as a Markdown file.

  ## Parameters

  - `chat_id` - Telegram chat ID to send to
  - `thread_data` - Raw Codex `thread/read` response map

  ## Examples

      iex> send_transcript(123456, %{"thread" => %{"id" => "thr_abc"}, "turns" => []})
      {:ok, %{message_id: 789}}
  """
  @spec send_transcript(integer(), map()) :: {:ok, term()} | {:error, term()}
  def send_transcript(chat_id, thread_data) do
    transcript = format_transcript(thread_data)
    thread_id = get_in(thread_data, ["thread", "id"]) || "unknown"
    filename = "transcript_#{thread_id}.md"
    document = {:file_content, transcript, filename}
    Surface.send_document(chat_id, document, caption: "Thread transcript")
  end

  @doc """
  Format thread data into a Markdown transcript string.

  ## Parameters

  - `thread_data` - Map with "thread" and "turns" keys from Codex `thread/read`

  ## Returns

  Formatted Markdown string with the full transcript including all items.
  """
  @spec format_transcript(map()) :: String.t()
  def format_transcript(thread_data) do
    thread = thread_data["thread"] || %{}
    # Turns may be at top level or nested inside thread
    turns = thread_data["turns"] || thread["turns"] || []
    thread_id = thread["id"] || "unknown"
    metadata = format_thread_metadata(thread)

    header = """
    # Thread Transcript

    **Thread ID:** `#{thread_id}`
    #{metadata}

    ---

    """

    turns_text =
      turns
      |> Enum.with_index(1)
      |> Enum.map_join("\n---\n\n", fn {turn, idx} -> format_turn(turn, idx) end)

    if turns_text == "" do
      header <> "_No turns in this thread._"
    else
      header <> turns_text
    end
  end

  # Format thread metadata
  defp format_thread_metadata(thread) do
    lines = []

    lines =
      if thread["model"] do
        ["**Model:** #{thread["model"]}" | lines]
      else
        lines
      end

    lines =
      if thread["createdAt"] do
        ["**Created:** #{thread["createdAt"]}" | lines]
      else
        lines
      end

    lines =
      case get_in(thread, ["usage", "totalTokens"]) do
        nil -> lines
        tokens -> ["**Total Tokens:** #{tokens}" | lines]
      end

    if lines == [] do
      ""
    else
      "\n" <> Enum.join(Enum.reverse(lines), "\n")
    end
  end

  # Format a single turn with all its items
  defp format_turn(turn, idx) do
    items = turn["items"] || []
    turn_id = turn["id"] || "unknown"
    status = turn["status"] || "unknown"

    # Format turn header
    header_lines = [
      "## Turn #{idx}",
      "_Turn ID: #{turn_id} | Status: #{status}_",
      ""
    ]

    # Format items
    items_text =
      items
      |> Enum.map(&format_item/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    # Add usage if available
    usage_text = format_turn_usage(turn["usage"])

    # Combine everything
    body =
      if items_text == "" do
        "_No items in this turn._"
      else
        items_text
      end

    [
      header_lines,
      body,
      usage_text
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format_turn_usage(nil), do: ""

  defp format_turn_usage(%{} = usage) do
    tokens = usage["totalTokens"] || usage["total_tokens"]

    if tokens do
      "\n\n_Usage: #{tokens} tokens_"
    else
      ""
    end
  end

  # Format individual items based on their type
  # User messages
  defp format_item(%{"type" => "userMessage"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    images = item["images"] || []

    image_note =
      if images != [] do
        "\n\n_(#{length(images)} image(s) attached)_"
      else
        ""
      end

    "**User:**\n#{text}#{image_note}"
  end

  # Agent messages
  defp format_item(%{"type" => "agentMessage"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    "**Agent:**\n#{text}"
  end

  # Legacy message types
  defp format_item(%{"type" => "message", "role" => "user"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    "**User:**\n#{text}"
  end

  defp format_item(%{"type" => "message", "role" => "assistant"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    "**Agent:**\n#{text}"
  end

  # Reasoning
  defp format_item(%{"type" => "reasoning"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    summary = item["summary"]

    if summary && summary != text do
      """
      **Reasoning:**
      #{summary}

      <details>
      <summary>Full reasoning</summary>

      #{text}
      </details>
      """
    else
      "**Reasoning:**\n#{text}"
    end
  end

  # Command execution
  defp format_item(%{"type" => "commandExecution"} = item) do
    command = item["command"] || []
    cmd_str = if is_list(command), do: Enum.join(command, " "), else: inspect(command)

    output = item["output"] || item["stdout"] || ""
    exit_code = item["exitCode"] || item["exit_code"]
    status = item["status"] || "completed"

    output_section =
      if output != "" do
        """

        Output:
        ```
        #{truncate(output, 2000)}
        ```
        """
      else
        ""
      end

    status_indicator = if status == "failed" || (exit_code && exit_code != 0), do: "❌ ", else: ""

    """
    **#{status_indicator}Command:**
    ```bash
    #{cmd_str}
    ```
    #{if exit_code, do: "_Exit code: #{exit_code}_", else: ""}#{output_section}
    """
    |> String.trim()
  end

  # File changes
  defp format_item(%{"type" => "fileChange"} = item) do
    path = item["path"] || "unknown"
    change_type = item["changeType"] || item["change_type"] || "modified"
    diff = item["diff"] || ""

    diff_section =
      if diff != "" do
        """

        ```diff
        #{truncate(diff, 3000)}
        ```
        """
      else
        ""
      end

    "**File Change:** `#{path}` (#{change_type})#{diff_section}"
  end

  # MCP tool calls
  defp format_item(%{"type" => "mcpToolCall"} = item) do
    tool = item["tool"] || item["name"] || "unknown"
    args = item["arguments"] || %{}
    result = item["result"] || item["output"]

    args_str =
      if args == %{} do
        ""
      else
        "\n\nArguments:\n```json\n#{Jason.encode!(args, pretty: true)}\n```"
      end

    result_section =
      if result do
        """

        Result:
        ```
        #{truncate(inspect(result), 1000)}
        ```
        """
      else
        ""
      end

    "**MCP Tool:** `#{tool}`#{args_str}#{result_section}"
    |> String.trim()
  end

  # Web search
  defp format_item(%{"type" => "webSearch"} = item) do
    query = item["query"] || ""
    results = item["results"] || []

    results_section =
      results
      |> Enum.take(5)
      |> Enum.map_join("\n", fn result ->
        title = result["title"] || "Untitled"
        url = result["url"] || ""
        snippet = result["snippet"] || ""
        "- [#{title}](#{url})#{if snippet != "", do: "\n  #{snippet}"}"
      end)

    if results_section != "" do
      """
      **Web Search:** #{query}

      Results:
      #{results_section}
      """
    else
      "**Web Search:** #{query}"
    end
  end

  # Exec command (shell execution)
  defp format_item(%{"type" => "execCommand"} = item) do
    cmd = item["content"] || item["command"] || ""
    output = item["output"]

    output_section =
      if output && output != "" do
        "\n\nOutput:\n```\n#{truncate(output, 1000)}\n```"
      else
        ""
      end

    "**Shell:** `#{cmd}`#{output_section}"
    |> String.trim()
  end

  # Collab tool calls
  defp format_item(%{"type" => "collabToolCall"} = item) do
    tool = item["tool"] || item["name"] || "unknown"
    "**Collaboration Tool:** `#{tool}`"
  end

  # Image view
  defp format_item(%{"type" => "imageView"} = item) do
    path = item["path"] || item["url"] || "unknown"
    "**Viewed Image:** `#{path}`"
  end

  # Review mode
  defp format_item(%{"type" => "enteredReviewMode"}) do
    "**Entered Review Mode**"
  end

  defp format_item(%{"type" => "exitedReviewMode"}) do
    "**Exited Review Mode**"
  end

  # Compacted
  defp format_item(%{"type" => "compacted"}) do
    "**_Context Compacted_**"
  end

  # Unknown types
  defp format_item(item) do
    type = item["type"] || "unknown"

    require Logger
    Logger.debug("Unhandled transcript item type in transcript: #{type}")

    # Try to show something useful
    if item["text"] do
      "**#{type}:**\n#{item["text"]}"
    else
      nil
    end
  end

  # Extract text from content arrays or strings
  defp extract_text_content(nil), do: nil

  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "outputText", "text" => text} -> text
      %{"type" => "output_text", "text" => text} -> text
      %{"type" => "inputText", "text" => text} -> text
      %{"type" => "input_text", "text" => text} -> text
      %{"type" => _type, "text" => text} when is_binary(text) -> text
      %{type: :text, text: text} -> text
      %{type: :output_text, text: text} -> text
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp extract_text_content(%{"text" => text}) when is_binary(text), do: text
  defp extract_text_content(%{text: text}) when is_binary(text), do: text
  defp extract_text_content(content) when is_binary(content), do: content
  defp extract_text_content(_), do: nil

  # Truncate long strings
  defp truncate(text, max_len) when is_binary(text) do
    if String.length(text) <= max_len do
      text
    else
      String.slice(text, 0, max_len) <> "\n... (truncated)"
    end
  end

  defp truncate(other, max_len), do: truncate(inspect(other), max_len)
end
