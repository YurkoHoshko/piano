defmodule Piano.Telegram.Bot do
  @moduledoc """
  Telegram bot using ExGram framework.

  Handles incoming Telegram messages and forwards them to the chat pipeline.
  """

  use ExGram.Bot,
    name: __MODULE__,
    setup_commands: true

  alias Piano.{ChatGateway, Events, Logger}
  alias Piano.Chat.Thread
  alias Piano.Telegram.{API, SessionMapper}

  command("start")
  command("newthread")
  command("thread")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot_token do
    config = Application.get_env(:piano, :telegram, [])
    config[:bot_token]
  end

  def handle({:command, :start, _msg}, context) do
    welcome_message = """
    👋 Welcome to Piano!

    I'm an AI assistant powered by Piano's multi-agent chat system.

    Just send me a message and I'll respond. You can:
    • Chat with me about anything
    • Use /newthread to start a fresh conversation
    • Use /thread <id> to switch to an existing thread

    Let's get started!
    """

    answer(context, welcome_message)
  end

  def handle({:command, :newthread, msg}, context) do
    chat_id = msg.chat.id
    SessionMapper.reset_thread(chat_id)
    answer(context, "🆕 Started a new thread! Your next message will begin a fresh conversation.")
  end

  def handle({:command, :thread, %{text: text} = msg}, context) do
    chat_id = msg.chat.id

    case parse_thread_id(text) do
      {:ok, thread_id} ->
        case Ash.get(Thread, thread_id) do
          {:ok, thread} ->
            SessionMapper.set_thread(chat_id, thread.id)
            title = thread.title || "Untitled"
            answer(context, "✅ Switched to thread: #{title}")

          {:error, _} ->
            answer(context, "❌ Thread not found. Please check the ID and try again.")
        end

      :error ->
        answer(context, "Usage: /thread <thread_id>\n\nExample: /thread abc123-def456-...")
    end
  end

  def handle({:command, _command, _msg}, context) do
    answer(context, "Unknown command. Send /start to see available options.")
  end

  def handle({:text, text, msg}, _context) do
    chat_id = msg.chat.id
    token = bot_token()

    API.send_chat_action(chat_id, "typing", token: token)

    case SessionMapper.get_or_create_thread(chat_id) do
      {:ok, thread_id} ->
        metadata = %{chat_id: chat_id, thread_id: thread_id}

        case ChatGateway.handle_incoming(text, :telegram, metadata) do
          {:ok, message} ->
            spawn(fn ->
              Events.subscribe(message.thread_id)
              wait_for_response(chat_id, message.thread_id, token)
            end)

          {:error, reason} ->
            Logger.error(:telegram, "Failed to handle message", chat_id: chat_id, reason: reason)
            API.send_message(chat_id, "Sorry, something went wrong. Please try again.", token: token)
        end

      {:error, reason} ->
        Logger.error(:telegram, "Failed to get/create thread", chat_id: chat_id, reason: reason)
        API.send_message(chat_id, "Sorry, something went wrong. Please try again.", token: token)
    end

    :ok
  end

  def handle(_update, _context) do
    :ok
  end

  defp parse_thread_id(text) do
    case String.split(text, " ", parts: 2) do
      ["/thread", thread_id] when thread_id != "" ->
        {:ok, String.trim(thread_id)}

      _ ->
        :error
    end
  end

  defp wait_for_response(chat_id, thread_id, token) do
    receive do
      {:processing_started, _message_id} ->
        API.send_chat_action(chat_id, "typing", token: token)
        wait_for_response(chat_id, thread_id, token)

      {:response_ready, agent_message} ->
        API.send_message(chat_id, agent_message.content, token: token)
        Events.unsubscribe(thread_id)

      {:processing_error, _message_id, reason} ->
        Logger.error(:telegram, "Processing error", thread_id: thread_id, reason: reason)
        API.send_message(chat_id, "Sorry, I encountered an error processing your message.", token: token)
        Events.unsubscribe(thread_id)
    after
      120_000 ->
        Logger.warning(:telegram, "Response timeout", thread_id: thread_id)
        API.send_message(chat_id, "Sorry, the request timed out. Please try again.", token: token)
        Events.unsubscribe(thread_id)
    end
  end
end
