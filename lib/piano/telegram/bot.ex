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
  alias Piano.Pipeline.MessageProducer
  alias Piano.Telegram.{API, SessionMapper}

  command("start", description: "Welcome message and usage tips")
  command("help", description: "Show help and available commands")
  command("newthread", description: "Start a new thread")
  command("thread", description: "Switch to a thread by ID")
  command("status", description: "Show current session status")
  command("history", description: "Show recent messages")
  command("delete", description: "Delete current thread")
  command("cancel", description: "Cancel current request")
  command("agents", description: "List available agents")
  command("switch", description: "Switch to a specific agent")

  # Telegram message character limit
  @max_message_length 4096
  # Time before showing "Still working..." message
  @still_working_timeout 30_000

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

    answer_with_menu(context, welcome_message)
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

    answer_with_menu(context, help_message, parse_mode: "Markdown")
  end

  def handle({:command, :newthread, msg}, context) do
    chat_id = msg.chat.id
    SessionMapper.reset_thread(chat_id)
    answer_with_menu(context, "🆕 Started a new thread! Your next message will begin a fresh conversation.")
  end

  def handle({:command, :thread, %{text: text} = msg}, context) do
    chat_id = msg.chat.id

    case parse_thread_id(text) do
      {:ok, thread_id} ->
        case Ash.get(Thread, thread_id) do
          {:ok, thread} ->
            SessionMapper.set_thread(chat_id, thread.id)
            title = thread.title || "Untitled"
            answer_with_menu(context, "✅ Switched to thread: #{title}")

          {:error, _} ->
            answer_with_menu(context, "❌ Thread not found. Please check the ID and try again.")
        end

      :error ->
        answer_with_menu(context, "Usage: /thread <thread_id>\n\nExample: /thread abc123-def456-...")
    end
  end

  def handle({:command, :status, msg}, context) do
    chat_id = msg.chat.id

    case SessionMapper.get_thread(chat_id) do
      nil ->
        answer_with_menu(context, "No active thread. Send a message to start one!")

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

            answer_with_menu(context, status, parse_mode: "Markdown")

          {:error, _} ->
            answer_with_menu(context, "No active thread. Send a message to start one!")
        end
    end
  end

  def handle({:command, :history, msg}, context) do
    chat_id = msg.chat.id

    case SessionMapper.get_thread(chat_id) do
      nil ->
        answer_with_menu(context, "No active thread. Send a message to start one!")

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

            answer_with_menu(context, "📜 *Recent Messages*\n\n#{history}", parse_mode: "Markdown")

          {:ok, []} ->
            answer_with_menu(context, "No messages in this thread yet.")

          {:error, _} ->
            answer_with_menu(context, "Failed to load history.")
        end
    end
  end

  def handle({:command, :delete, %{text: text} = msg}, context) do
    chat_id = msg.chat.id

    case SessionMapper.get_thread(chat_id) do
      nil ->
        answer_with_menu(context, "No active thread to delete.")

      thread_id ->
        if String.contains?(text, "confirm") do
          case Ash.get(Thread, thread_id) do
            {:ok, thread} ->
              Ash.destroy!(thread)
              SessionMapper.reset_thread(chat_id)
              answer_with_menu(context, "🗑️ Thread deleted. Send a message to start a new conversation.")

            {:error, _} ->
              SessionMapper.reset_thread(chat_id)
              answer_with_menu(context, "Thread not found. Session cleared.")
          end
        else
          answer_with_menu(context, "⚠️ Are you sure? This will delete all messages in the current thread.\n\nReply /delete confirm to proceed.")
        end
    end
  end

  def handle({:command, :cancel, msg}, context) do
    chat_id = msg.chat.id

    pending_message_id = SessionMapper.get_pending_message_id(chat_id)

    case pending_message_id do
      nil ->
        answer_with_menu(context, "No pending request to cancel.")

      message_id ->
        ensure_pending_requests_table()
        ensure_cancelled_requests_table()

        case :ets.lookup(:piano_pending_requests, {chat_id, message_id}) do
          [{{^chat_id, ^message_id}, pid, placeholder_message_id}] ->
            send(pid, :cancelled)
            :ets.delete(:piano_pending_requests, {chat_id, message_id})
            :ets.insert(:piano_telegram_cancelled, {{chat_id, message_id}})
            SessionMapper.clear_pending_message_id(chat_id, message_id)
            token = bot_token()
            send_or_edit(chat_id, placeholder_message_id, "⏹️ Cancelled", token, message_id)
            answer_with_menu(context, "Request cancelled.")

          [] ->
            answer_with_menu(context, "No pending request to cancel.")
        end
    end
  end

  def handle({:command, :agents, msg}, context) do
    chat_id = msg.chat.id
    active_agent_id = SessionMapper.get_agent(chat_id)

    case Ash.read(Piano.Agents.Agent, action: :list) do
      {:ok, []} ->
        answer_with_menu(context, "No agents configured yet.")

      {:ok, agents} ->
        message = agents_message(agents, active_agent_id)
        answer(context, message, parse_mode: "Markdown", reply_markup: agents_keyboard(agents, active_agent_id))

      {:error, _reason} ->
        answer_with_menu(context, "Failed to load agents.")
    end
  end

  def handle({:command, :switch, %{text: text} = msg}, context) do
    chat_id = msg.chat.id

    case parse_agent_name(text) do
      {:ok, agent_name} ->
        case find_agent_by_name(agent_name) do
          {:ok, agent} ->
            case SessionMapper.set_agent(chat_id, agent.id) do
              :ok ->
                Logger.info("Telegram agent switch via /switch to #{agent.name} (#{agent.id})")
                answer_with_menu(context, "✅ Switched to #{agent.name}")

              {:error, _reason} ->
                answer_with_menu(context, "❌ Failed to switch agent. Please try again.")
            end

          {:error, :not_found} ->
            case Ash.read(Piano.Agents.Agent, action: :list) do
              {:ok, agents} when agents != [] ->
                names = Enum.map_join(agents, ", ", & &1.name)
                answer_with_menu(context, "❌ Agent not found. Available agents: #{names}")

              _ ->
                answer_with_menu(context, "❌ Agent not found. No agents configured.")
            end
        end

      :error ->
        case Ash.read(Piano.Agents.Agent, action: :list) do
          {:ok, agents} when agents != [] ->
            active_agent_id = SessionMapper.get_agent(chat_id)
            message = agents_message(agents, active_agent_id)
            answer(context, message, parse_mode: "Markdown", reply_markup: agents_keyboard(agents, active_agent_id))

          _ ->
            answer_with_menu(context, "Usage: /switch <agent_name>\n\nExample: /switch Assistant")
        end
    end
  end

  def handle({:callback_query, callback_query}, _context) do
    data = callback_query.data || ""

    case parse_switch_callback(data) do
      {:ok, agent_id} ->
        Logger.info("Telegram callback switch to agent #{agent_id}")
        chat_id = callback_query.message.chat.id

        case SessionMapper.set_agent(chat_id, agent_id) do
          :ok ->
            Logger.info("Telegram agent switch success for chat #{chat_id}")
            update_agents_message(callback_query, agent_id)
            API.answer_callback_query(callback_query.id, text: "Switched agent.")
            :ok

          {:error, _reason} ->
            Logger.warning("Telegram agent switch failed for chat #{chat_id}")
            API.answer_callback_query(callback_query.id, text: "Failed to switch agent.")
            :ok
        end

      :error ->
        Logger.warning("Telegram callback query ignored: #{inspect(data)}")
        API.answer_callback_query(callback_query.id, text: "Unknown action.")
        :ok
    end
  end

  def handle({:command, _command, _msg}, context) do
    answer_with_menu(context, "Unknown command. Send /help to see available commands.")
  end

  def handle({:deleted_business_messages, %{chat: %{id: chat_id}, message_ids: message_ids}}, _context) do
    Enum.each(message_ids, &handle_message_deleted(chat_id, &1))
    :ok
  end

  def handle({:text, text, msg}, _context) do
    chat_id = msg.chat.id
    user_message_id = Map.get(msg, :message_id)
    token = bot_token()
    ensure_pending_requests_table()
    ensure_cancelled_requests_table()

    pending_message_id = SessionMapper.get_pending_message_id(chat_id)

    placeholder_text =
      case pending_message_id do
        nil -> "⏳ Processing..."
        ^user_message_id -> "⏳ Processing..."
        _other -> "⏳ Your message is queued, please wait..."
      end

    if pending_message_id == nil and not is_nil(user_message_id) do
      SessionMapper.set_pending_message_id(chat_id, user_message_id)
    end

    placeholder_message_id =
      case API.send_message(chat_id, placeholder_text,
             token: token,
             reply_to_message_id: user_message_id
           ) do
        {:ok, %{message_id: mid}} ->
          ensure_last_text_table()
          :ets.insert(:piano_telegram_last_text, {{chat_id, mid}, placeholder_text})
          mid

        {:error, reason} ->
          Logger.warning("Telegram send_message failed for chat #{chat_id}: #{inspect(reason)}")
          nil

        other ->
          Logger.warning("Telegram send_message unexpected response for chat #{chat_id}: #{inspect(other)}")
          nil
      end

    case SessionMapper.get_or_create_thread(chat_id) do
      {:ok, thread_id} ->
        agent_id = SessionMapper.get_agent(chat_id)
        metadata = %{
          chat_id: chat_id,
          thread_id: thread_id,
          agent_id: agent_id,
          telegram_message_id: user_message_id
        }

        case ChatGateway.handle_incoming(text, :telegram, metadata) do
          {:ok, message} ->
            spawn(fn ->
              ensure_pending_requests_table()
              ensure_cancelled_requests_table()
              :ets.insert(:piano_pending_requests, {{chat_id, user_message_id}, self(), placeholder_message_id})
              Events.subscribe(message.thread_id)

              result =
                wait_for_response(
                  chat_id,
                  message.thread_id,
                  message.id,
                  token,
                  placeholder_message_id,
                  user_message_id
                )

              :ets.delete(:piano_pending_requests, {chat_id, user_message_id})
              result
            end)

          {:error, reason} ->
            Logger.error("Failed to handle Telegram message: #{inspect(reason)}")
            send_or_edit(chat_id, placeholder_message_id, "Sorry, something went wrong. Please try again.", token, user_message_id)
            SessionMapper.clear_pending_message_id(chat_id, user_message_id)
        end

      {:error, reason} ->
        Logger.error("Failed to get/create thread for chat #{chat_id}: #{inspect(reason)}")
        send_or_edit(chat_id, placeholder_message_id, "Sorry, something went wrong. Please try again.", token, user_message_id)
        SessionMapper.clear_pending_message_id(chat_id, user_message_id)
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

  defp parse_agent_name(text) do
    case String.split(text, " ", parts: 2) do
      ["/switch", agent_name] when agent_name != "" ->
        {:ok, String.trim(agent_name)}

      _ ->
        :error
    end
  end

  defp parse_switch_callback("switch:" <> agent_id) when agent_id != "", do: {:ok, agent_id}
  defp parse_switch_callback(_), do: :error

  defp find_agent_by_name(name) do
    case Ash.read(Piano.Agents.Agent, action: :list) do
      {:ok, agents} ->
        name_downcase = String.downcase(name)

        case Enum.find(agents, fn agent ->
               String.downcase(agent.name) == name_downcase
             end) do
          nil -> {:error, :not_found}
          agent -> {:ok, agent}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp wait_for_response(chat_id, thread_id, message_id, token, placeholder_message_id, user_message_id) do
    wait_for_response(chat_id, thread_id, message_id, token, placeholder_message_id, user_message_id, false, 0, [])
  end

  defp wait_for_response(
         chat_id,
         thread_id,
         message_id,
         token,
         placeholder_message_id,
         user_message_id,
         started?,
         elapsed,
         tool_calls
       ) do
    remaining = if started?, do: 120_000 - elapsed, else: @still_working_timeout
    timeout = min(@still_working_timeout, remaining)

    if started? and remaining <= 0 do
      Logger.warning("Response timeout for thread #{thread_id}")
      send_or_edit(chat_id, placeholder_message_id, "Sorry, the request timed out. Please try again.", token, user_message_id)
      Events.unsubscribe(thread_id)
      :timeout
    else
      receive do
        :cancelled ->
          Events.unsubscribe(thread_id)
          :cancelled

        {:processing_started, ^message_id} ->
          send_or_edit(chat_id, placeholder_message_id, "⏳ Processing...", token, user_message_id,
            allow_send: false
          )
          API.send_chat_action(chat_id, "typing", token: token)
          wait_for_response(
            chat_id,
            thread_id,
            message_id,
            token,
            placeholder_message_id,
            user_message_id,
            true,
            0,
            tool_calls
          )

        {:processing_started, _other_message_id} ->
          wait_for_response(
            chat_id,
            thread_id,
            message_id,
            token,
            placeholder_message_id,
            user_message_id,
            started?,
            elapsed,
            tool_calls
          )

        {:tool_call, ^message_id, tool_call} ->
          updated_tool_calls = tool_calls ++ [tool_call]
          send_or_edit(chat_id, placeholder_message_id, tool_calls_placeholder(updated_tool_calls), token, user_message_id,
            allow_send: false
          )
          wait_for_response(
            chat_id,
            thread_id,
            message_id,
            token,
            placeholder_message_id,
            user_message_id,
            started?,
            elapsed,
            updated_tool_calls
          )

        {:tool_call, _other_message_id, _tool_call} ->
          wait_for_response(
            chat_id,
            thread_id,
            message_id,
            token,
            placeholder_message_id,
            user_message_id,
            started?,
            elapsed,
            tool_calls
          )

        {:tool_call, tool_call} ->
          updated_tool_calls = tool_calls ++ [tool_call]
          send_or_edit(chat_id, placeholder_message_id, tool_calls_placeholder(updated_tool_calls), token, user_message_id,
            allow_send: false
          )
          wait_for_response(
            chat_id,
            thread_id,
            message_id,
            token,
            placeholder_message_id,
            user_message_id,
            started?,
            elapsed,
            updated_tool_calls
          )

        {:response_ready, ^message_id, agent_message} ->
          send_long_response(chat_id, placeholder_message_id, agent_message.content, token, tool_calls, user_message_id)
          Events.unsubscribe(thread_id)
          :ok

        {:response_ready, _other_message_id, _agent_message} ->
          wait_for_response(
            chat_id,
            thread_id,
            message_id,
            token,
            placeholder_message_id,
            user_message_id,
            started?,
            elapsed,
            tool_calls
          )

        {:response_ready, agent_message} ->
          send_long_response(chat_id, placeholder_message_id, agent_message.content, token, tool_calls, user_message_id)
          Events.unsubscribe(thread_id)
          :ok

        {:processing_error, ^message_id, reason} ->
          Logger.error("Processing error for thread #{thread_id}: #{inspect(reason)}")
          error_message = format_error_message(reason)
          send_or_edit(chat_id, placeholder_message_id, error_message, token, user_message_id)
          Events.unsubscribe(thread_id)
          :error

        {:processing_error, _other_message_id, _reason} ->
          wait_for_response(
            chat_id,
            thread_id,
            message_id,
            token,
            placeholder_message_id,
            user_message_id,
            started?,
            elapsed,
            tool_calls
          )
      after
        timeout ->
          if not started? do
            wait_for_response(
              chat_id,
              thread_id,
              message_id,
              token,
              placeholder_message_id,
              user_message_id,
              started?,
              elapsed,
              tool_calls
            )
          else
            if elapsed + timeout < 120_000 do
              send_or_edit(chat_id, placeholder_message_id, "⏳ Still working...", token, user_message_id,
                allow_send: false
              )
              API.send_chat_action(chat_id, "typing", token: token)
              wait_for_response(
                chat_id,
                thread_id,
                message_id,
                token,
                placeholder_message_id,
                user_message_id,
                started?,
                elapsed + timeout,
                tool_calls
              )
            else
              Logger.warning("Response timeout for thread #{thread_id}")
              send_or_edit(chat_id, placeholder_message_id, "Sorry, the request timed out. Please try again.", token, user_message_id)
              Events.unsubscribe(thread_id)
              :timeout
            end
          end
      end
    end
  end

  defp send_or_edit(chat_id, message_id, text, token, user_message_id, opts \\ [])

  defp send_or_edit(chat_id, nil, text, token, user_message_id, opts) do
    {allow_send, opts} = Keyword.pop(opts, :allow_send, true)

    if allow_send do
      opts =
        [token: token, reply_markup: main_keyboard(), reply_to_message_id: user_message_id]
        |> Keyword.merge(opts)

      Logger.debug("Telegram send_message (no placeholder) chat=#{chat_id} reply_to=#{user_message_id}")
      API.send_message(chat_id, text, opts)
    else
      :ok
    end
  end

  defp send_or_edit(chat_id, message_id, text, token, user_message_id, opts) do
    {allow_send, opts} = Keyword.pop(opts, :allow_send, true)
    ensure_last_text_table()

    if same_last_text?(chat_id, message_id, text) do
      :ok
    else
      edit_opts =
        [token: token]
        |> Keyword.merge(opts)

      send_opts =
        [token: token, reply_markup: main_keyboard(), reply_to_message_id: user_message_id]
        |> Keyword.merge(opts)

      Logger.debug("Telegram edit_message_text chat=#{chat_id} message_id=#{message_id}")
      case API.edit_message_text(chat_id, message_id, text, edit_opts) do
        {:ok, _} ->
          :ets.insert(:piano_telegram_last_text, {{chat_id, message_id}, text})
          :ok

        {:error, reason} ->
          if not_modified_error?(reason) do
            :ets.insert(:piano_telegram_last_text, {{chat_id, message_id}, text})
            :ok
          else
            Logger.warning("Telegram edit_message_text failed for chat #{chat_id}: #{inspect(reason)}")

            if allow_send and should_fallback_send?(reason) do
              Logger.debug("Telegram send_message fallback chat=#{chat_id} reply_to=#{user_message_id}")
              API.send_message(chat_id, text, send_opts)
            else
              :ok
            end
          end
      end
    end
  end

  defp send_long_response(chat_id, placeholder_message_id, content, token, tool_calls, user_message_id) do
    {chunks, parse_mode} =
      if tool_calls == [] do
        {split_message(content), nil}
      else
        build_html_response_chunks(content, tool_calls)
      end

    response_opts =
      case parse_mode do
        nil -> []
        value -> [parse_mode: value]
      end

    case chunks do
      [] ->
        send_or_edit(chat_id, placeholder_message_id, "No response generated.", token, user_message_id)

      [first | rest] ->
        send_or_edit(chat_id, placeholder_message_id, first, token, user_message_id, response_opts)

        Enum.each(rest, fn chunk ->
          Process.sleep(100)
          API.send_message(chat_id, chunk,
            [token: token, reply_markup: main_keyboard(), reply_to_message_id: user_message_id] ++ response_opts
          )
        end)
    end
  end

  defp split_message(content) when byte_size(content) <= @max_message_length do
    [content]
  end

  defp split_message(content) do
    content
    |> String.graphemes()
    |> Enum.chunk_every(@max_message_length - 50)
    |> Enum.map(&Enum.join/1)
    |> Enum.flat_map(&split_at_boundaries/1)
  end

  defp split_at_boundaries(chunk) when byte_size(chunk) <= @max_message_length do
    [chunk]
  end

  defp split_at_boundaries(chunk) do
    split_points = ["\n\n", "\n", ". ", " "]

    case find_split_point(chunk, split_points) do
      nil ->
        mid = div(String.length(chunk), 2)
        {left, right} = String.split_at(chunk, mid)
        [String.trim_trailing(left), String.trim_leading(right)]

      {pos, _delimiter} ->
        {left, right} = String.split_at(chunk, pos)
        [String.trim_trailing(left) | split_at_boundaries(String.trim_leading(right))]
    end
  end

  defp find_split_point(chunk, delimiters) do
    target = div(@max_message_length, 2)

    Enum.find_value(delimiters, fn delimiter ->
      case find_nearest_delimiter(chunk, delimiter, target) do
        nil -> nil
        pos -> {pos + String.length(delimiter), delimiter}
      end
    end)
  end

  defp find_nearest_delimiter(chunk, delimiter, target) do
    positions =
      chunk
      |> String.split(delimiter)
      |> Enum.reduce({0, []}, fn part, {offset, positions} ->
        new_offset = offset + String.length(part) + String.length(delimiter)
        {new_offset, [offset + String.length(part) | positions]}
      end)
      |> elem(1)
      |> Enum.reverse()
      |> Enum.drop(-1)

    positions
    |> Enum.filter(&(&1 > 100 and &1 < @max_message_length - 100))
    |> Enum.min_by(&abs(&1 - target), fn -> nil end)
  end

  defp main_keyboard do
    %ExGram.Model.ReplyKeyboardMarkup{
      keyboard: [
        [
          %ExGram.Model.KeyboardButton{text: "/newthread"},
          %ExGram.Model.KeyboardButton{text: "/agents"}
        ]
      ],
      resize_keyboard: true,
      one_time_keyboard: false,
      selective: false
    }
  end

  defp agents_message(agents, active_agent_id) do
    agent_list =
      Enum.map_join(agents, "\n", fn agent ->
        is_active = agent.id == active_agent_id
        status = if is_active, do: " _(active)_", else: ""
        description = agent.description || "No description"
        "🤖 *#{agent.name}*#{status}\n   #{description}"
      end)

    "📋 *Available Agents*\n\n#{agent_list}"
  end

  defp agents_keyboard(agents, active_agent_id) do
    rows =
      agents
      |> Enum.map(fn agent ->
        label =
          if agent.id == active_agent_id do
            "✅ #{agent.name}"
          else
            agent.name
          end

        %ExGram.Model.InlineKeyboardButton{text: label, callback_data: "switch:#{agent.id}"}
      end)
      |> Enum.chunk_every(2)

    %ExGram.Model.InlineKeyboardMarkup{inline_keyboard: rows}
  end

  defp update_agents_message(callback_query, active_agent_id) do
    with %{message: message} <- callback_query,
         %{chat: %{id: chat_id}, message_id: message_id} <- message,
         {:ok, agents} <- Ash.read(Piano.Agents.Agent, action: :list) do
      text = agents_message(agents, active_agent_id)
      keyboard = agents_keyboard(agents, active_agent_id)
      API.edit_message_text(chat_id, message_id, text, parse_mode: "Markdown", reply_markup: keyboard)
    else
      _ -> :ok
    end
  end

  defp format_error_message(reason) do
    case reason do
      :llm_failure ->
        "❌ Sorry, I couldn't generate a response. Please try again."

      :timeout ->
        "❌ The request timed out. Please try again."

      %{message: msg} when is_binary(msg) ->
        "❌ Error: #{String.slice(msg, 0, 200)}"

      _ ->
        "❌ Sorry, I encountered an error processing your message."
    end
  end

  defp tool_calls_placeholder(tool_calls) do
    header = "⏳ Processing..."
    preview = format_tool_calls_preview(tool_calls)

    if preview == "" do
      header
    else
      "#{header}\n\nTool calls so far:\n#{preview}"
    end
  end

  defp format_tool_calls_preview(tool_calls) do
    tool_calls
    |> Enum.take(-8)
    |> Enum.map_join("\n", &format_tool_call_line/1)
    |> String.slice(0, 1500)
  end

  defp format_tool_call_line(%{name: name, arguments: args}) when is_map(args) do
    rendered =
      args
      |> Enum.filter(fn {key, value} ->
        key in ["command", "path", "url", "query"] and value != nil
      end)
      |> Enum.map(fn {key, value} -> "#{key}=#{format_tool_call_value(value)}" end)
      |> Enum.join(", ")

    if rendered == "" do
      "- #{name}()"
    else
      "- #{name}(#{rendered})"
    end
  end

  defp format_tool_call_line(%{name: name}), do: "- #{name}()"
  defp format_tool_call_line(_), do: "- tool_call()"

  defp format_tool_call_value(value) when is_binary(value) do
    value
    |> String.replace("\n", " ")
    |> String.slice(0, 120)
  end

  defp format_tool_call_value(value), do: inspect(value, limit: 2, printable_limit: 120)

  defp build_html_response_chunks(content, tool_calls) do
    content_chunks = split_message(html_escape(content))
    tool_call_blocks = format_tool_calls_blocks(tool_calls)

    cond do
      tool_call_blocks == [] ->
        {content_chunks, "HTML"}

      content_chunks == [] ->
        {tool_call_blocks, "HTML"}

      true ->
        [first_block | rest_blocks] = tool_call_blocks
        last_chunk = List.last(content_chunks)

        if byte_size(last_chunk) + 2 + byte_size(first_block) <= @max_message_length do
          updated_chunks =
            List.replace_at(content_chunks, -1, last_chunk <> "\n\n" <> first_block)

          {updated_chunks ++ rest_blocks, "HTML"}
        else
          {content_chunks ++ tool_call_blocks, "HTML"}
        end
    end
  end

  defp format_tool_calls_blocks(tool_calls) do
    lines = tool_calls |> Enum.map(&format_tool_call_line/1) |> Enum.map(&html_escape/1)
    header = "<blockquote expandable>\n<b>🔧 Tool Calls</b>\n<pre>"
    footer = "</pre>\n</blockquote>"
    max_body_size = @max_message_length - byte_size(header) - byte_size(footer)

    if max_body_size <= 0 do
      [header <> footer]
    else
      {blocks, current} =
        Enum.reduce(lines, {[], ""}, fn line, {blocks, current} ->
          candidate = if current == "", do: line, else: current <> "\n" <> line

          if byte_size(candidate) <= max_body_size do
            {blocks, candidate}
          else
            {blocks ++ [current], line}
          end
        end)

      blocks = if current == "", do: blocks, else: blocks ++ [current]

      Enum.map(blocks, fn body ->
        header <> body <> footer
      end)
    end
  end

  defp answer_with_menu(context, text, opts \\ []) do
    answer(context, text, Keyword.put_new(opts, :reply_markup, main_keyboard()))
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp should_fallback_send?(_reason), do: false

  defp not_modified_error?(%{message: message}) when is_binary(message) do
    String.contains?(message, "message is not modified")
  end

  defp not_modified_error?(%{description: description}) when is_binary(description) do
    String.contains?(description, "message is not modified")
  end

  defp not_modified_error?(_reason), do: false

  defp handle_message_deleted(chat_id, message_id) do
    ensure_pending_requests_table()
    ensure_cancelled_requests_table()

    :ets.insert(:piano_telegram_cancelled, {{chat_id, message_id}})
    SessionMapper.clear_pending_message_id(chat_id, message_id)
    MessageProducer.cancel_telegram(chat_id, message_id)

    case :ets.lookup(:piano_pending_requests, {chat_id, message_id}) do
      [{{^chat_id, ^message_id}, pid, placeholder_message_id}] ->
        send(pid, :cancelled)
        :ets.delete(:piano_pending_requests, {chat_id, message_id})

        token = bot_token()
        send_or_edit(chat_id, placeholder_message_id, "⏹️ Cancelled", token, message_id)

      [] ->
        :ok
    end
  end

  defp ensure_pending_requests_table do
    case :ets.whereis(:piano_pending_requests) do
      :undefined ->
        :ets.new(:piano_pending_requests, [:named_table, :public, :set])

      _ref ->
        :ok
    end
  end

  defp ensure_cancelled_requests_table do
    case :ets.whereis(:piano_telegram_cancelled) do
      :undefined ->
        :ets.new(:piano_telegram_cancelled, [:named_table, :public, :set])

      _ref ->
        :ok
    end
  end

  defp ensure_last_text_table do
    case :ets.whereis(:piano_telegram_last_text) do
      :undefined ->
        :ets.new(:piano_telegram_last_text, [:named_table, :public, :set])

      _ref ->
        :ok
    end
  end

  defp same_last_text?(chat_id, message_id, text) when is_integer(message_id) do
    case :ets.lookup(:piano_telegram_last_text, {chat_id, message_id}) do
      [{{^chat_id, ^message_id}, ^text}] -> true
      _ -> false
    end
  end

  defp same_last_text?(_chat_id, _message_id, _text), do: false
end
