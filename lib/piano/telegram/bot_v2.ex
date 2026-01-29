defmodule Piano.Telegram.BotV2 do
  @moduledoc """
  Simplified Telegram bot using ExGram framework.

  Receives messages and delegates to Piano.Telegram.Handler.
  """

  use ExGram.Bot,
    name: __MODULE__,
    setup_commands: true

  require Logger

  alias Piano.Telegram.Handler

  command("start", description: "Welcome message")
  command("help", description: "Show help")
  command("newthread", description: "Start a new Codex thread for this chat")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot_token do
    config = Application.get_env(:piano, :telegram, [])
    config[:bot_token]
  end

  def handle({:command, :start, _msg}, context) do
    answer(context, "👋 Welcome! Send me a message and I'll respond.")
  end

  def handle({:command, :help, _msg}, context) do
    answer(context, "Just send any message to chat with me!")
  end

  def handle({:command, :newthread, msg}, context) do
    chat_id = msg.chat.id

    case Handler.force_new_thread(chat_id) do
      {:ok, _} ->
        answer(context, "✅ Starting a new thread for this chat.")

      {:error, reason} ->
        Logger.error("Failed to start new thread: #{inspect(reason)}")
        answer(context, "⚠️ Failed to start a new thread. Please try again.")
    end
  end

  def handle({:command, _command, _msg}, context) do
    answer(context, "Unknown command. Send /help for available commands.")
  end

  def handle({:text, text, msg}, _context) do
    chat_id = msg.chat.id

    case Handler.handle_message(chat_id, text) do
      {:ok, _interaction} ->
        :ok

      {:error, reason} ->
        Logger.error("Telegram handler failed: #{inspect(reason)}")
        :ok
    end
  end

  def handle(_event, _context), do: :ok
end
