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
  command("session", description: "Show Codex session info and MCP tools")

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
      /session - show Codex session info and MCP tools
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
    reply_to = TelegramSurface.build_reply_to(msg.chat.id, 0)

    :ok =
      RequestMap.put(request_id, %{
        type: :telegram_account_login_start,
        reply_to: reply_to
      })

    :ok = CodexClient.send_request("account/login/start", %{type: "chatgpt"}, request_id)
    answer(context, "Starting ChatGPT login... (waiting for auth URL)")
  end

  def handle({:command, :codexaccount, msg}, context) do
    log_inbound(:command, msg, "/codexaccount")
    request_id = new_request_id()
    reply_to = TelegramSurface.build_reply_to(msg.chat.id, 0)

    :ok =
      RequestMap.put(request_id, %{
        type: :telegram_account_read,
        reply_to: reply_to
      })

    :ok = CodexClient.send_request("account/read", %{refreshToken: false}, request_id)
    answer(context, "Reading Codex account...")
  end

  def handle({:command, :codexlogout, msg}, context) do
    log_inbound(:command, msg, "/codexlogout")
    request_id = new_request_id()
    reply_to = TelegramSurface.build_reply_to(msg.chat.id, 0)

    :ok =
      RequestMap.put(request_id, %{
        type: :telegram_account_logout,
        reply_to: reply_to
      })

    :ok = CodexClient.send_request("account/logout", %{}, request_id)
    answer(context, "Logging out Codex...")
  end

  def handle({:command, :transcript, msg}, _context) do
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

  def handle({:command, :session, _msg}, context) do
    codex_status = if CodexClient.ready?(), do: "✅ Ready", else: "⏳ Initializing"
    current_profile = CodexConfig.current_profile!() |> to_string()

    tools = [
      "browser_visit",
      "browser_click",
      "browser_input",
      "browser_find",
      "browser_screenshot",
      "browser_get_content",
      "browser_current_url",
      "browser_execute_script",
      "web_fetch",
      "web_extract_text",
      "web_extract_markdown",
      "web_extract_structured",
      "voice_transcribe",
      "vision_analyze",
      "vision_describe",
      "vision_extract_text"
    ]

    tool_list = Enum.map_join(tools, "\n", fn t -> "  • #{t}" end)

    message = """
    🔌 <b>Codex Session Info</b>

    <b>Status:</b> #{codex_status}
    <b>Profile:</b> #{current_profile}

    <b>MCP Tools Available (#{length(tools)}):</b>
    #{tool_list}

    <b>MCP Server:</b> piano@http://localhost:4000/mcp

    Use these tools by asking me to analyze websites or fetch content!
    """

    answer(context, message, parse_mode: "HTML")
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

  # Handle file/media messages (photos, documents, videos, audio, voice)
  # ExGram dispatches these as {:message, msg} - we pattern match on message fields
  def handle({:message, %{photo: photo_sizes} = msg}, context)
      when is_list(photo_sizes) and photo_sizes != [] do
    handle_file_message(:photo, photo_sizes, msg, context)
  end

  def handle({:message, %{document: document} = msg}, context) when not is_nil(document) do
    handle_file_message(:document, document, msg, context)
  end

  def handle({:message, %{video: video} = msg}, context) when not is_nil(video) do
    handle_file_message(:video, video, msg, context)
  end

  def handle({:message, %{audio: audio} = msg}, context) when not is_nil(audio) do
    handle_file_message(:audio, audio, msg, context)
  end

  def handle({:message, %{voice: voice} = msg}, context) when not is_nil(voice) do
    handle_file_message(:voice, voice, msg, context)
  end

  def handle(event, _context) do
    Logger.info("Telegram event ignored", event: summarize_event(event))
    :ok
  end

  defp handle_file_message(file_type, file_info, msg, context) do
    log_inbound(:file, msg, "#{file_type} received")
    chat_id = msg.chat.id

    # Get file ID - different structures for different file types
    file_id = extract_file_id(file_type, file_info)

    if file_id do
      # Send acknowledgment - use Telegram API directly to get message_id
      {:ok, ack_msg} = TelegramSurface.send_message(chat_id, "📎 Processing #{file_type}...")
      ack_msg_id = ack_msg.message_id

      # Create intake folder for this interaction
      interaction_id = "#{msg.message_id}_#{:erlang.unique_integer([:positive])}"
      intake_path = Path.join([Piano.Intake.base_dir(), "telegram", interaction_id])

      case Piano.Intake.create_interaction_folder("telegram", interaction_id) do
        {:ok, ^intake_path} ->
          # Download and save file
          case download_and_save_file(file_id, intake_path, file_type) do
            {:ok, file_path} ->
              # Get caption if any
              caption = Map.get(msg, :caption) || ""

              # Generate intake context
              intake_context = Piano.Intake.generate_context(intake_path)

              # Update message with success info
              TelegramSurface.edit_message_text(
                chat_id,
                ack_msg_id,
                "✅ File saved. Processing with agent...\n\n#{intake_context}"
              )

              # Create prompt with file context
              prompt = build_file_prompt(file_type, file_path, caption, intake_context)

              # Pass to handler
              case Handler.handle_message_with_intake(msg, prompt, intake_path) do
                {:ok, _interaction} ->
                  :ok

                {:error, reason} ->
                  Logger.error("Telegram handler failed for file: #{inspect(reason)}")
                  :ok
              end

            {:error, reason} ->
              Logger.error("Failed to download file: #{inspect(reason)}")

              TelegramSurface.edit_message_text(
                chat_id,
                ack_msg_id,
                "❌ Failed to download file: #{inspect(reason)}"
              )
          end

        {:error, reason} ->
          Logger.error("Failed to create intake folder: #{inspect(reason)}")

          TelegramSurface.edit_message_text(
            chat_id,
            ack_msg_id,
            "❌ Failed to create intake folder"
          )
      end
    else
      answer(context, "⚠️ Could not extract file information")
    end
  end

  defp extract_file_id(:photo, photo_sizes) do
    # Get the largest photo (last in the list is usually largest)
    photo_sizes
    |> List.last()
    |> case do
      %{file_id: id} -> id
      %{"file_id" => id} -> id
      _ -> nil
    end
  end

  defp extract_file_id(_type, file_info) when is_map(file_info) do
    # For documents, videos, audio, voice
    Map.get(file_info, :file_id) || Map.get(file_info, "file_id")
  end

  defp extract_file_id(_, _), do: nil

  defp download_and_save_file(file_id, intake_path, file_type) do
    # Get file info from Telegram
    token = bot_token()

    case ExGram.get_file(file_id, token: token) do
      {:ok, file_info} ->
        file_path = file_info.file_path

        # Determine extension based on file type
        ext = file_extension(file_type, file_path)
        filename = "#{file_type}_#{:erlang.unique_integer([:positive])}#{ext}"

        # Download file content
        download_url = "https://api.telegram.org/file/bot#{token}/#{file_path}"

        case Req.get(download_url) do
          {:ok, %{status: 200, body: body}} ->
            Piano.Intake.save_file(intake_path, filename, body)

          {:ok, %{status: status}} ->
            {:error, "Download failed with status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp file_extension(:photo, _), do: ".jpg"
  defp file_extension(:voice, _), do: ".ogg"

  defp file_extension(_, file_path) when is_binary(file_path) do
    ext = Path.extname(file_path)
    if ext != "", do: ext, else: ".bin"
  end

  defp file_extension(_, _), do: ".bin"

  defp build_file_prompt(file_type, file_path, caption, intake_context) do
    type_hint = file_type_hint(file_type)

    base =
      case file_type do
        :voice -> "🎤 User sent a voice message"
        :audio -> "🎵 User sent an audio file"
        :photo -> "📷 User sent a photo"
        :video -> "🎬 User sent a video"
        _ -> "📎 User sent a #{file_type} file"
      end

    with_caption = if caption != "", do: "#{base} with caption: \"#{caption}\"", else: base

    """
    #{with_caption}

    **File:** `#{file_path}`

    #{intake_context}

    #{type_hint}
    """
  end

  defp file_type_hint(:voice), do: "Use voice_transcribe tool to transcribe this audio to text."
  defp file_type_hint(:audio), do: "Use voice_transcribe tool to transcribe this audio to text."

  defp file_type_hint(:photo),
    do:
      "Use vision tools to analyze this image: vision_analyze (ask specific question), vision_describe (general description), or vision_extract_text (OCR)."

  defp file_type_hint(_), do: "Process this file as appropriate for the user's request."

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
  defp summarize_event({:photo, _, _msg}), do: :photo
  defp summarize_event({:document, _, _msg}), do: :document
  defp summarize_event({:video, _, _msg}), do: :video
  defp summarize_event({:audio, _, _msg}), do: :audio
  defp summarize_event({:voice, _, _msg}), do: :voice
  defp summarize_event(other), do: other
end
