defmodule Piano.Telegram.BotV2 do
  @moduledoc """
  Simplified Telegram bot using ExGram framework.

  Receives messages and delegates to Piano.Telegram.Handler.
  """

  use ExGram.Bot,
    name: __MODULE__,
    setup_commands: true

  require Logger

  alias Piano.Codex.Client, as: CodexClient
  alias Piano.Codex.Config, as: CodexConfig
  alias Piano.Codex.RequestMap
  alias Piano.Observability
  alias Piano.Telegram.Handler
  alias Piano.Telegram.Surface, as: TelegramSurface

  command("start", description: "Welcome message")
  command("help", description: "Show help")
  command("newthread", description: "Start a new Codex thread for this chat")
  command("profiles", description: "List available Codex profiles")
  command("profile", description: "Show current Codex profile")
  command("switchprofile", description: "Switch Codex profile (requires restart)")
  command("restartcodex", description: "Restart Codex app-server process")
  command("codexlogin", description: "Start Codex ChatGPT login flow (returns auth URL)")
  command("codexaccount", description: "Show Codex account/auth status")
  command("codexlogout", description: "Logout Codex")
  command("transcript", description: "Get transcript of current thread")
  command("status", description: "Show server status/boot info")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot_token do
    config = Application.get_env(:piano, :telegram, [])
    config[:bot_token]
  end

  def handle({:command, :start, _msg}, context) do
    answer(context, "👋 Welcome! Send me a message and I'll respond.")
  end

  def handle({:command, :help, _msg}, context) do
    answer(
      context,
      """
      Send any message to chat with me.

      Commands:
      /newthread - start a new thread for this chat
      /profiles - list available Codex profiles
      /profile - show current Codex profile
      /switchprofile <name> - switch profile (run /restartcodex to apply)
      /restartcodex - restart Codex app-server
      /codexlogin - start ChatGPT login (returns a link you open in a browser)
      /codexaccount - show Codex auth status
      /codexlogout - logout Codex
      /transcript - get transcript of current thread
      /status - show server status
      """
    )
  end

  def handle({:command, :newthread, msg}, context) do
    log_inbound(:command, msg, "/newthread")
    chat_id = msg.chat.id

    case Handler.force_new_thread(chat_id) do
      {:ok, _} ->
        answer(context, "✅ Starting a new thread for this chat.")

      {:error, reason} ->
        Logger.error("Failed to start new thread: #{inspect(reason)}")
        answer(context, "⚠️ Failed to start a new thread. Please try again.")
    end
  end

  def handle({:command, :profiles, _msg}, context) do
    profiles = CodexConfig.profile_names() |> Enum.map(&Atom.to_string/1)
    answer(context, "Available profiles:\n" <> Enum.join(profiles, "\n"))
  end

  def handle({:command, :profile, _msg}, context) do
    answer(context, "Current profile: #{CodexConfig.current_profile!()}")
  end

  def handle({:command, :switchprofile, msg}, context) do
    log_inbound(:command, msg, "/switchprofile")
    # ExGram passes just the argument in msg.text (e.g., "fast" not "/switchprofile fast")
    profile_str = (msg.text || "") |> String.trim()

    if profile_str == "" do
      answer(context, "Usage: /switchprofile <name>")
    else
      available_strings = CodexConfig.profile_names() |> Enum.map(&Atom.to_string/1)

      if profile_str in available_strings do
        profile = String.to_atom(profile_str)
        :ok = CodexConfig.set_current_profile!(profile)

        case CodexClient.restart() do
          :ok ->
            answer(context, "✅ Switched to #{profile} and restarted Codex.")

          {:error, reason} ->
            Logger.error("Failed to restart Codex after profile switch: #{inspect(reason)}")
            answer(context, "✅ Profile set to #{profile}, but restart failed. Run /restartcodex.")
        end
      else
        answer(context, "⚠️ Unknown profile: #{profile_str}\nUse /profiles to see available.")
      end
    end
  end

  def handle({:command, :restartcodex, _msg}, context) do
    case CodexClient.restart() do
      :ok ->
        answer(context, "🔁 Codex restarted. Current profile: #{CodexConfig.current_profile!()}")

      {:error, reason} ->
        Logger.error("Failed to restart Codex: #{inspect(reason)}")
        answer(context, "⚠️ Failed to restart Codex: #{inspect(reason)}")
    end
  end

  def handle({:command, :codexlogin, msg}, context) do
    log_inbound(:command, msg, "/codexlogin")
    # ChatGPT login is an interactive browser flow. We just return the authUrl,
    # and Codex completes the login when the callback is received.
    request_id = new_request_id()
    :ok = RequestMap.put(request_id, %{type: :telegram_account_login_start, chat_id: msg.chat.id})
    :ok = CodexClient.send_request("account/login/start", %{type: "chatgpt"}, request_id)
    answer(context, "Starting ChatGPT login... (waiting for auth URL)")
  end

  def handle({:command, :codexaccount, msg}, context) do
    log_inbound(:command, msg, "/codexaccount")
    request_id = new_request_id()
    :ok = RequestMap.put(request_id, %{type: :telegram_account_read, chat_id: msg.chat.id})
    :ok = CodexClient.send_request("account/read", %{refreshToken: false}, request_id)
    answer(context, "Reading Codex account...")
  end

  def handle({:command, :codexlogout, msg}, context) do
    log_inbound(:command, msg, "/codexlogout")
    request_id = new_request_id()
    :ok = RequestMap.put(request_id, %{type: :telegram_account_logout, chat_id: msg.chat.id})
    :ok = CodexClient.send_request("account/logout", %{}, request_id)
    answer(context, "Logging out Codex...")
  end

  def handle({:command, :transcript, msg}, context) do
    log_inbound(:command, msg, "/transcript")
    chat_id = msg.chat.id

    # Send placeholder and get message_id
    {:ok, %{message_id: message_id}} =
      TelegramSurface.send_message(chat_id, "⏳ Fetching transcript...")

    case Handler.get_thread_transcript(chat_id, message_id) do
      {:ok, :pending} ->
        :ok

      {:error, :no_thread} ->
        TelegramSurface.edit_message_text(
          chat_id,
          message_id,
          "No active thread found for this chat."
        )

      {:error, reason} ->
        Logger.error("Failed to get transcript: #{inspect(reason)}")
        TelegramSurface.edit_message_text(chat_id, message_id, "⚠️ Failed to get transcript.")
    end
  end

  def handle({:command, :status, _msg}, context) do
    answer(context, Observability.status_text())
  end

  def handle({:command, _command, _msg}, context) do
    answer(context, "Unknown command. Send /help for available commands.")
  end

  def handle({:text, text, msg}, _context) do
    log_inbound(:text, msg, text)

    case Handler.handle_message(msg, text) do
      {:ok, _interaction} ->
        :ok

      {:error, reason} ->
        Logger.error("Telegram handler failed: #{inspect(reason)}")
        :ok
    end
  end

  def handle(event, _context) do
    Logger.info("Telegram event ignored", event: summarize_event(event))
    :ok
  end

  defp new_request_id do
    :erlang.unique_integer([:positive, :monotonic])
  end

  defp log_inbound(kind, msg, text_or_cmd) do
    chat = Map.get(msg, :chat) || Map.get(msg, "chat")
    from = Map.get(msg, :from) || Map.get(msg, "from")

    chat_id = map_get(chat, :id)
    chat_type = map_get(chat, :type)
    from_id = map_get(from, :id)
    username = map_get(from, :username)

    preview =
      text_or_cmd
      |> to_string()
      |> String.trim()
      |> String.slice(0, 120)

    Logger.info("Telegram inbound",
      kind: kind,
      chat_id: chat_id,
      chat_type: chat_type,
      from_id: from_id,
      username: username,
      preview: preview
    )
  end

  defp map_get(nil, _key), do: nil

  defp map_get(data, key) when is_map(data) and is_atom(key) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key))
  end

  defp summarize_event({:text, _text, _msg}), do: :text
  defp summarize_event({:command, cmd, _msg}), do: {:command, cmd}
  defp summarize_event(other), do: other
end
