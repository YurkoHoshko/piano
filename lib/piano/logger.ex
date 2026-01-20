defmodule Piano.Logger do
  @moduledoc """
  Structured logging helpers with module tagging.

  Provides consistent log formatting across all Piano subsystems with
  module-prefixed messages for easy filtering and debugging.

  ## Usage

      Piano.Logger.info(:llm, "Calling model qwen3:32b with 3 messages")
      # => [Piano.LLM] Calling model qwen3:32b with 3 messages

      Piano.Logger.error(:telegram, "Failed to send message", chat_id: 123)
      # => [Piano.Telegram] Failed to send message chat_id=123

  ## Supported Tags

  - `:llm` - LLM client operations
  - `:telegram` - Telegram bot operations
  - `:agents` - Agent execution and tool usage
  - `:pipeline` - Message processing pipeline
  - `:chat` - Chat and thread operations
  """

  require Logger

  @type tag :: :llm | :telegram | :agents | :pipeline | :chat | atom()
  @type level :: :debug | :info | :warning | :error

  @tag_prefixes %{
    llm: "Piano.LLM",
    telegram: "Piano.Telegram",
    agents: "Piano.Agents",
    pipeline: "Piano.Pipeline",
    chat: "Piano.Chat"
  }

  @doc """
  Logs a message with the given level and module tag.

  ## Parameters
    - level: Log level (:debug, :info, :warning, :error)
    - tag: Module tag atom (:llm, :telegram, :agents, :pipeline, :chat)
    - message: The log message (string or function returning string)
    - metadata: Optional keyword list of metadata to append

  ## Examples

      Piano.Logger.log(:info, :llm, "Calling model", model: "qwen3:32b")
      Piano.Logger.log(:error, :telegram, fn -> "Error: \#{inspect(reason)}" end)
  """
  @spec log(level(), tag(), String.t() | (-> String.t()), keyword()) :: :ok
  def log(level, tag, message, metadata \\ [])

  def log(level, tag, message, metadata) when is_function(message, 0) do
    Logger.log(level, fn -> format_message(tag, message.(), metadata) end)
  end

  def log(level, tag, message, metadata) when is_binary(message) do
    Logger.log(level, format_message(tag, message, metadata))
  end

  @doc "Log at debug level with module tag."
  @spec debug(tag(), String.t() | (-> String.t()), keyword()) :: :ok
  def debug(tag, message, metadata \\ []), do: log(:debug, tag, message, metadata)

  @doc "Log at info level with module tag."
  @spec info(tag(), String.t() | (-> String.t()), keyword()) :: :ok
  def info(tag, message, metadata \\ []), do: log(:info, tag, message, metadata)

  @doc "Log at warning level with module tag."
  @spec warning(tag(), String.t() | (-> String.t()), keyword()) :: :ok
  def warning(tag, message, metadata \\ []), do: log(:warning, tag, message, metadata)

  @doc "Log at error level with module tag."
  @spec error(tag(), String.t() | (-> String.t()), keyword()) :: :ok
  def error(tag, message, metadata \\ []), do: log(:error, tag, message, metadata)

  defp format_message(tag, message, metadata) do
    prefix = Map.get(@tag_prefixes, tag, "Piano.#{tag |> to_string() |> String.capitalize()}")
    metadata_str = format_metadata(metadata)

    if metadata_str == "" do
      "[#{prefix}] #{message}"
    else
      "[#{prefix}] #{message} #{metadata_str}"
    end
  end

  defp format_metadata([]), do: ""

  defp format_metadata(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(" ")
  end
end
