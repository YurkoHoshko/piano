defmodule Piano.Telegram.Transcript do
  @moduledoc """
  Thread transcript formatting for Telegram.

  Converts Codex thread data into a human-readable Markdown transcript
  and sends it as a `.md` file attachment.

  ## Transcript Format

  The transcript is formatted as Markdown with:
  - Thread header with ID
  - Each turn numbered with its items
  - User messages, agent messages, reasoning, commands, and file changes
  """

  alias Piano.Telegram.API

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
    API.send_document(chat_id, document, caption: "Thread transcript")
  end

  @doc """
  Format thread data into a Markdown transcript string.

  ## Parameters

  - `thread_data` - Map with "thread" and "turns" keys from Codex `thread/read`

  ## Returns

  Formatted Markdown string with the full transcript.
  """
  @spec format_transcript(map()) :: String.t()
  def format_transcript(thread_data) do
    thread = thread_data["thread"] || %{}
    # Turns may be at top level or nested inside thread
    turns = thread_data["turns"] || thread["turns"] || []
    thread_id = thread["id"] || "unknown"

    header = "# Thread Transcript\n\nThread ID: `#{thread_id}`\n\n---\n\n"

    turns_text =
      turns
      |> Enum.with_index(1)
      |> Enum.map(fn {turn, idx} -> format_turn(turn, idx) end)
      |> Enum.join("\n---\n\n")

    if turns_text == "" do
      header <> "_No turns in this thread._"
    else
      header <> turns_text
    end
  end

  # Format a single turn with its items
  defp format_turn(turn, idx) do
    items = turn["items"] || []
    turn_id = turn["id"] || "unknown"

    items_text =
      items
      |> Enum.map(&format_item/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    """
    ## Turn #{idx}
    _Turn ID: #{turn_id}_

    #{items_text}
    """
  end

  # Format individual items based on their type
  defp format_item(%{"type" => "userMessage"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    "**User:**\n#{text}"
  end

  defp format_item(%{"type" => "agentMessage"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    "**Agent:**\n#{text}"
  end

  defp format_item(%{"type" => "message", "role" => "user"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    "**User:**\n#{text}"
  end

  defp format_item(%{"type" => "message", "role" => "assistant"} = item) do
    text = extract_text_content(item["content"]) || item["text"] || ""
    "**Agent:**\n#{text}"
  end

  defp format_item(%{"type" => "reasoning", "content" => content}) do
    text = extract_text_content(content)
    "_Reasoning:_ #{text}"
  end

  defp format_item(%{"type" => "commandExecution", "command" => command}) do
    cmd_str = if is_list(command), do: Enum.join(command, " "), else: inspect(command)
    "```\n$ #{cmd_str}\n```"
  end

  defp format_item(%{"type" => "fileChange", "path" => path}) do
    "`📝 File changed: #{path}`"
  end

  # Ignore other item types (mcpToolCall, webSearch, etc.)
  defp format_item(item) do
    require Logger
    Logger.debug("Unhandled transcript item type: #{inspect(item["type"])}")
    nil
  end

  # Extract text from content arrays or strings
  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "outputText", "text" => text} -> text
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp extract_text_content(content) when is_binary(content), do: content
  defp extract_text_content(_), do: ""

end
