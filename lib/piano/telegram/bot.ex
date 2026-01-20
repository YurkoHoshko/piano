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
  command("cancel")
  command("agents")
  command("switch")

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

  def handle({:command, :cancel, msg}, context) do
    chat_id = msg.chat.id

    case :ets.lookup(:piano_pending_requests, chat_id) do
      [{^chat_id, pid, placeholder_message_id}] ->
        send(pid, :cancelled)
        :ets.delete(:piano_pending_requests, chat_id)
        token = bot_token()
        send_or_edit(chat_id, placeholder_message_id, "⏹️ Cancelled", token)
        answer(context, "Request cancelled.")

      [] ->
        answer(context, "No pending request to cancel.")
    end
  end

  def handle({:command, :agents, msg}, context) do
    chat_id = msg.chat.id
    active_agent_id = SessionMapper.get_agent(chat_id)

    case Ash.read(Piano.Agents.Agent, action: :list) do
      {:ok, []} ->
        answer(context, "No agents configured yet.")

      {:ok, agents} ->
        agent_list =
          Enum.map_join(agents, "\n", fn agent ->
            is_active = agent.id == active_agent_id
            status = if is_active, do: " _(active)_", else: ""
            description = agent.description || "No description"
            "🤖 *#{agent.name}*#{status}\n   #{description}"
          end)

        message = "📋 *Available Agents*\n\n#{agent_list}"
        answer(context, message, parse_mode: "Markdown")

      {:error, _reason} ->
        answer(context, "Failed to load agents.")
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
                answer(context, "✅ Switched to #{agent.name}")

              {:error, _reason} ->
                answer(context, "❌ Failed to switch agent. Please try again.")
            end

          {:error, :not_found} ->
            case Ash.read(Piano.Agents.Agent, action: :list) do
              {:ok, agents} when agents != [] ->
                names = Enum.map_join(agents, ", ", & &1.name)
                answer(context, "❌ Agent not found. Available agents: #{names}")

              _ ->
                answer(context, "❌ Agent not found. No agents configured.")
            end
        end

      :error ->
        answer(context, "Usage: /switch <agent_name>\n\nExample: /switch Assistant")
    end
  end

  def handle({:command, _command, _msg}, context) do
    answer(context, "Unknown command. Send /help to see available commands.")
  end

  def handle({:text, text, msg}, _context) do
    chat_id = msg.chat.id
    token = bot_token()

    placeholder_message_id =
      case API.send_message(chat_id, "⏳ Processing...", token: token) do
        {:ok, %{message_id: mid}} -> mid
        _ -> nil
      end

    case SessionMapper.get_or_create_thread(chat_id) do
      {:ok, thread_id} ->
        metadata = %{chat_id: chat_id, thread_id: thread_id}

        case ChatGateway.handle_incoming(text, :telegram, metadata) do
          {:ok, message} ->
            parent = self()

            spawn(fn ->
              ensure_pending_requests_table()
              :ets.insert(:piano_pending_requests, {chat_id, self(), placeholder_message_id})
              Events.subscribe(message.thread_id)

              result =
                wait_for_response(chat_id, message.thread_id, token, placeholder_message_id)

              :ets.delete(:piano_pending_requests, chat_id)
              send(parent, {:request_complete, chat_id, result})
            end)

          {:error, reason} ->
            Logger.error("Failed to handle Telegram message: #{inspect(reason)}")
            send_or_edit(chat_id, placeholder_message_id, "Sorry, something went wrong. Please try again.", token)
        end

      {:error, reason} ->
        Logger.error("Failed to get/create thread for chat #{chat_id}: #{inspect(reason)}")
        send_or_edit(chat_id, placeholder_message_id, "Sorry, something went wrong. Please try again.", token)
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

  defp wait_for_response(chat_id, thread_id, token, placeholder_message_id) do
    wait_for_response(chat_id, thread_id, token, placeholder_message_id, 0, [])
  end

  defp wait_for_response(chat_id, thread_id, token, placeholder_message_id, elapsed, tool_calls) do
    remaining = 120_000 - elapsed
    timeout = min(@still_working_timeout, remaining)

    if remaining <= 0 do
      Logger.warning("Response timeout for thread #{thread_id}")
      send_or_edit(chat_id, placeholder_message_id, "Sorry, the request timed out. Please try again.", token)
      Events.unsubscribe(thread_id)
      :timeout
    else
      receive do
        :cancelled ->
          Events.unsubscribe(thread_id)
          :cancelled

        {:processing_started, _message_id} ->
          API.send_chat_action(chat_id, "typing", token: token)
          wait_for_response(chat_id, thread_id, token, placeholder_message_id, elapsed, tool_calls)

        {:tool_call, tool_call} ->
          updated_tool_calls = tool_calls ++ [tool_call]
          send_or_edit(chat_id, placeholder_message_id, tool_calls_placeholder(updated_tool_calls), token)
          wait_for_response(chat_id, thread_id, token, placeholder_message_id, elapsed, updated_tool_calls)

        {:response_ready, agent_message} ->
          send_long_response(chat_id, placeholder_message_id, agent_message.content, token, tool_calls)
          Events.unsubscribe(thread_id)
          :ok

        {:processing_error, _message_id, reason} ->
          Logger.error("Processing error for thread #{thread_id}: #{inspect(reason)}")
          error_message = format_error_message(reason)
          send_or_edit(chat_id, placeholder_message_id, error_message, token)
          Events.unsubscribe(thread_id)
          :error
      after
        timeout ->
          if elapsed + timeout < 120_000 do
            send_or_edit(chat_id, placeholder_message_id, "⏳ Still working...", token)
            API.send_chat_action(chat_id, "typing", token: token)
            wait_for_response(chat_id, thread_id, token, placeholder_message_id, elapsed + timeout, tool_calls)
          else
            Logger.warning("Response timeout for thread #{thread_id}")
            send_or_edit(chat_id, placeholder_message_id, "Sorry, the request timed out. Please try again.", token)
            Events.unsubscribe(thread_id)
            :timeout
          end
      end
    end
  end

  defp send_or_edit(chat_id, nil, text, token) do
    API.send_message(chat_id, text, token: token)
  end

  defp send_or_edit(chat_id, message_id, text, token) do
    case API.edit_message_text(chat_id, message_id, text, token: token) do
      {:ok, _} ->
        :ok

      {:error, _reason} ->
        API.send_message(chat_id, text, token: token)
    end
  end

  defp send_long_response(chat_id, placeholder_message_id, content, token, tool_calls) do
    chunks = split_message(content)

    case chunks do
      [] ->
        send_or_edit(chat_id, placeholder_message_id, "No response generated.", token)

      [first | rest] ->
        send_or_edit(chat_id, placeholder_message_id, first, token)

        Enum.each(rest, fn chunk ->
          Process.sleep(100)
          API.send_message(chat_id, chunk, token: token, parse_mode: "Markdown")
        end)
    end

    if tool_calls != [] do
      send_tool_calls_drawer(chat_id, tool_calls, token)
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
        key in ["command", "path", "url", "query", "file", "name"] and value != nil
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

  defp send_tool_calls_drawer(chat_id, tool_calls, token) do
    body =
      tool_calls
      |> Enum.map_join("\n", &format_tool_call_line/1)
      |> html_escape()

    text = "<spoiler>Tool calls:\n#{body}</spoiler>"
    API.send_message(chat_id, text, token: token, parse_mode: "HTML")
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp ensure_pending_requests_table do
    case :ets.whereis(:piano_pending_requests) do
      :undefined ->
        :ets.new(:piano_pending_requests, [:named_table, :public, :set])

      _ref ->
        :ok
    end
  end
end
