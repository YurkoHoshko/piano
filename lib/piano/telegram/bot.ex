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

  command("start")

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

  def handle({:command, _command, _msg}, context) do
    answer(context, "Unknown command. Send /start to see available options.")
  end

  def handle({:text, text, msg}, _context) do
    chat_id = msg.chat.id
    token = bot_token()

    ExGram.send_chat_action(chat_id, "typing", token: token)

    metadata = %{chat_id: chat_id}

    case ChatGateway.handle_incoming(text, :telegram, metadata) do
      {:ok, message} ->
        thread_id = message.thread_id
        Events.subscribe(thread_id)

        spawn(fn -> wait_for_response(chat_id, thread_id, token) end)

      {:error, reason} ->
        Logger.error("Failed to handle Telegram message: #{inspect(reason)}")
        ExGram.send_message(chat_id, "Sorry, something went wrong. Please try again.", token: token)
    end

    :ok
  end

  def handle(_update, _context) do
    :ok
  end

  defp wait_for_response(chat_id, thread_id, token) do
    receive do
      {:processing_started, _message_id} ->
        ExGram.send_chat_action(chat_id, "typing", token: token)
        wait_for_response(chat_id, thread_id, token)

      {:response_ready, agent_message} ->
        ExGram.send_message(chat_id, agent_message.content, token: token)
        Events.unsubscribe(thread_id)

      {:processing_error, _message_id, reason} ->
        Logger.error("Processing error for thread #{thread_id}: #{inspect(reason)}")
        ExGram.send_message(chat_id, "Sorry, I encountered an error processing your message.", token: token)
        Events.unsubscribe(thread_id)
    after
      120_000 ->
        Logger.warning("Response timeout for thread #{thread_id}")
        ExGram.send_message(chat_id, "Sorry, the request timed out. Please try again.", token: token)
        Events.unsubscribe(thread_id)
    end
  end
end
