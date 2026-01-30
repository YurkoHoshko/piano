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

  def on_turn_started(_surface, _interaction, _params) do
    {:ok, :noop}
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

  def on_item_started(_surface, _interaction, _params) do
    {:ok, :noop}
  end

  def on_item_completed(_surface, _interaction, _params) do
    {:ok, :noop}
  end

  def on_agent_message_delta(surface, _interaction, params) do
    case get_in(params, ["item", "text"]) do
      text when is_binary(text) and text != "" ->
        TelegramSurface.update_message(surface, text)

      _ ->
        {:ok, :noop}
    end
  end

  def on_approval_required(surface, _interaction, _params) do
    TelegramSurface.update_message(surface, "⚠️ Approval required")
  end

  def send_thread_transcript(surface, thread_data) do
    Transcript.send_transcript(surface.chat_id, thread_data)
  end
end
