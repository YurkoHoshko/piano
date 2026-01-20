defmodule Piano.Telegram.Bot do
  @moduledoc """
  Telegram bot using ExGram framework.

  Handles incoming Telegram messages and forwards them to the chat pipeline.
  """

  use ExGram.Bot,
    name: __MODULE__,
    setup_commands: true

  require Logger

  alias Piano.{ChatGateway, Events}
  alias Piano.Chat.{Message, Thread}
  alias Piano.Telegram.{API, SessionMapper}

  command("start")
  command("help")
  command("newthread")
  command("thread")
  command("status")
  command("history")
  command("delete")

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

  def handle({:command, :help, _msg}, context) do
    help_message = """
    📚 *Available Commands*

    /start - Welcome message and getting started
    /help - Show this help message
    /newthread - Start a fresh conversation
    /thread <id> - Switch to an existing thread
    /status - Show current session info
    /history - Show recent messages in current thread

    💬 Just send any message to chat with me!
    """

    answer(context, help_message, parse_mode: "Markdown")
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

  def handle({:command, :status, msg}, context) do
    chat_id = msg.chat.id

    case SessionMapper.get_thread(chat_id) do
      nil ->
        answer(context, "No active thread. Send a message to start one!")

      thread_id ->
        case Ash.get(Thread, thread_id) do
          {:ok, thread} ->
            query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: thread_id})
            message_count = case Ash.read(query) do
              {:ok, messages} -> length(messages)
              _ -> 0
            end

            title = thread.title || "Untitled"
            created = Calendar.strftime(thread.inserted_at, "%Y-%m-%d %H:%M")

            status = """
            📊 *Session Status*

            🧵 Thread: #{title}
            🆔 ID: `#{thread_id}`
            📝 Messages: #{message_count}
            📅 Created: #{created}
            """

            answer(context, status, parse_mode: "Markdown")

          {:error, _} ->
            answer(context, "No active thread. Send a message to start one!")
        end
    end
  end

  def handle({:command, :history, msg}, context) do
    chat_id = msg.chat.id

    case SessionMapper.get_thread(chat_id) do
      nil ->
        answer(context, "No active thread. Send a message to start one!")

      thread_id ->
        query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: thread_id})

        case Ash.read(query) do
          {:ok, messages} when messages != [] ->
            sorted = Enum.sort_by(messages, & &1.inserted_at, DateTime)
            recent = Enum.take(sorted, -10)

            history =
              Enum.map_join(recent, "\n\n", fn msg ->
                prefix = if msg.role == :user, do: "👤 You", else: "🤖 Bot"
                content = String.slice(msg.content, 0, 100)
                content = if String.length(msg.content) > 100, do: content <> "...", else: content
                "#{prefix}: #{content}"
              end)

            answer(context, "📜 *Recent Messages*\n\n#{history}", parse_mode: "Markdown")

          {:ok, []} ->
            answer(context, "No messages in this thread yet.")

          {:error, _} ->
            answer(context, "Failed to load history.")
        end
    end
  end

  def handle({:command, :delete, %{text: text} = msg}, context) do
    chat_id = msg.chat.id

    case SessionMapper.get_thread(chat_id) do
      nil ->
        answer(context, "No active thread to delete.")

      thread_id ->
        if String.contains?(text, "confirm") do
          case Ash.get(Thread, thread_id) do
            {:ok, thread} ->
              Ash.destroy!(thread)
              SessionMapper.reset_thread(chat_id)
              answer(context, "🗑️ Thread deleted. Send a message to start a new conversation.")

            {:error, _} ->
              SessionMapper.reset_thread(chat_id)
              answer(context, "Thread not found. Session cleared.")
          end
        else
          answer(context, "⚠️ Are you sure? This will delete all messages in the current thread.\n\nReply /delete confirm to proceed.")
        end
    end
  end

  def handle({:command, _command, _msg}, context) do
    answer(context, "Unknown command. Send /help to see available commands.")
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
            Logger.error("Failed to handle Telegram message: #{inspect(reason)}")
            API.send_message(chat_id, "Sorry, something went wrong. Please try again.", token: token)
        end

      {:error, reason} ->
        Logger.error("Failed to get/create thread for chat #{chat_id}: #{inspect(reason)}")
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
        Logger.error("Processing error for thread #{thread_id}: #{inspect(reason)}")
        API.send_message(chat_id, "Sorry, I encountered an error processing your message.", token: token)
        Events.unsubscribe(thread_id)
    after
      120_000 ->
        Logger.warning("Response timeout for thread #{thread_id}")
        API.send_message(chat_id, "Sorry, the request timed out. Please try again.", token: token)
        Events.unsubscribe(thread_id)
    end
  end
end
