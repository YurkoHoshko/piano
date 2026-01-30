defmodule Piano.Telegram.Handler do
  @moduledoc """
  Barebone Telegram message handler.

  Receives messages, sends placeholder, creates Interaction, and triggers the pipeline.
  """

  require Logger

  alias Piano.Core.Interaction
  alias Piano.Core.Thread
  alias Piano.Telegram.API
  alias Piano.Telegram.ContextWindow
  alias Piano.Telegram.Surface, as: TelegramSurface
  alias Piano.Telegram.Prompt
  alias Piano.Codex.Client, as: CodexClient
  alias Piano.Codex.RequestMap

  
  @doc """
  Handle an incoming Telegram text message.

  1. Sends a placeholder message
  2. Creates an Interaction with reply_to
  3. Starts the Codex turn
  """
  @spec handle_message(map(), String.t()) :: {:ok, term()} | {:error, term()}
  def handle_message(msg, text) when is_map(msg) and is_binary(text) do
    chat = Map.get(msg, :chat) || Map.get(msg, "chat")

    chat_id =
      if is_map(chat) do
        Map.get(chat, :id) || Map.get(chat, "id")
      else
        nil
      end

    if not is_integer(chat_id) do
      {:error, :invalid_chat_id}
    else
      chat_type = chat_type(msg)
      _ = ContextWindow.record(msg, text)

      if chat_type in ["group", "supergroup"] and not tagged_for_bot?(text) do
        Logger.info("Telegram group message ignored (not tagged)", chat_id: chat_id, chat_type: chat_type)
        {:ok, :ignored_not_tagged}
      else
        if chat_type in ["group", "supergroup"] do
          _ = ContextWindow.mark_tagged(chat_id, message_id(msg))
        end

        text = maybe_strip_bot_tag(text)
        participants = get_participant_count(chat_id)
        recent =
          if chat_type in ["group", "supergroup"] do
            ContextWindow.recent(chat_id,
              mode: :since_last_tag_or_last_n,
              limit: 15,
              exclude_message_id: message_id(msg)
            )
          else
            []
          end

        prompt = Prompt.build(msg, text, participants: participants, recent: recent)

        case maybe_handle_localhost_1455_link(chat_id, text) do
          :handled ->
            {:ok, :localhost_1455_checked}

          :not_handled ->
            with {:ok, reply_to} <- TelegramSurface.send_placeholder(chat_id),
                 {:ok, interaction} <- create_interaction(prompt, reply_to),
                 {:ok, interaction} <- start_turn(interaction) do
              Logger.info("Telegram message processed",
                chat_id: chat_id,
                interaction_id: interaction.id
              )

              {:ok, interaction}
            else
              {:error, reason} = error ->
                Logger.error("Failed to handle Telegram message",
                  chat_id: chat_id,
                  error: inspect(reason)
                )

                error
            end
        end
      end
    end
  end

  def handle_message(chat_id, text) when is_integer(chat_id) and is_binary(text) do
    # Backwards-compatible entrypoint.
    case maybe_handle_localhost_1455_link(chat_id, text) do
      :handled ->
        {:ok, :localhost_1455_checked}

      :not_handled ->
        with {:ok, reply_to} <- TelegramSurface.send_placeholder(chat_id),
             {:ok, interaction} <- create_interaction(text, reply_to),
             {:ok, interaction} <- start_turn(interaction) do
          Logger.info("Telegram message processed",
            chat_id: chat_id,
            interaction_id: interaction.id
          )

          {:ok, interaction}
        else
          {:error, reason} = error ->
            Logger.error("Failed to handle Telegram message",
              chat_id: chat_id,
              error: inspect(reason)
            )

            error
        end
    end
  end

  @doc """
  Force-start a new Codex thread for a Telegram chat.
  """
  @spec force_new_thread(integer()) :: {:ok, term()} | {:error, term()}
  def force_new_thread(chat_id) do
    reply_to = "telegram:#{chat_id}"

    case find_recent_thread(reply_to) do
      {:ok, thread} ->
        case Piano.Codex.force_start_thread(thread) do
          {:ok, request_id} -> {:ok, %{status: :started, request_id: request_id}}
          {:error, reason} -> {:error, {:codex_force_start_failed, reason}}
        end

      {:error, :not_found} ->
        case Ash.create(Thread, %{reply_to: reply_to}, action: :create) do
          {:ok, thread} ->
            {:ok, request_id} = Piano.Codex.start_thread(thread)
            {:ok, %{status: :started, request_id: request_id}}

          {:error, reason} ->
            {:error, {:thread_create_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:thread_lookup_failed, reason}}
    end
  end

  defp create_interaction(text, reply_to) do
    Ash.create(Interaction, %{original_message: text, reply_to: reply_to}, action: :create)
  end

  defp chat_type(msg) when is_map(msg) do
    chat = Map.get(msg, :chat) || Map.get(msg, "chat")

    if is_map(chat) do
      Map.get(chat, :type) || Map.get(chat, "type")
    else
      nil
    end
  end

  defp tagged_for_bot?(text) when is_binary(text) do
    bot_username =
      Application.get_env(:piano, :telegram, [])
      |> Keyword.get(:bot_username)

    if is_binary(bot_username) and bot_username != "" do
      String.contains?(String.downcase(text), "@" <> String.downcase(bot_username))
    else
      Logger.warning("TELEGRAM_BOT_USERNAME not set; group tag gating disabled")
      true
    end
  end

  defp maybe_strip_bot_tag(text) when is_binary(text) do
    bot_username =
      Application.get_env(:piano, :telegram, [])
      |> Keyword.get(:bot_username)

    if is_binary(bot_username) and bot_username != "" do
      text
      |> String.replace(~r/@#{Regex.escape(bot_username)}\b/i, "")
      |> String.trim()
    else
      text
    end
  end

  defp get_participant_count(chat_id) when is_integer(chat_id) do
    case API.get_chat_member_count(chat_id) do
      {:ok, count} when is_integer(count) -> count
      _ -> nil
    end
  end

  defp message_id(msg) when is_map(msg) do
    Map.get(msg, :message_id) || Map.get(msg, "message_id")
  end

  defp maybe_handle_localhost_1455_link(chat_id, text) when is_integer(chat_id) and is_binary(text) do
    url = String.trim(text)

    if String.starts_with?(url, "localhost") do
      Logger.info("Telegram localhost link detected", chat_id: chat_id)

      result = check_with_curl(ensure_url_scheme(url))

      _ =
        case result do
          {:ok, status} ->
            Piano.Telegram.API.send_message(
              chat_id,
              "✅ localhost:1455 reachable (HTTP #{status}). No need to retry.",
              []
            )

          {:not_ok, status} ->
            Piano.Telegram.API.send_message(
              chat_id,
              "⚠️ localhost:1455 responded (HTTP #{status}). Retrying won't help unless the service changes.",
              []
            )

          {:error, reason} ->
            Piano.Telegram.API.send_message(
              chat_id,
              "❌ Can't reach localhost:1455 from the server (#{inspect(reason)}). Check that the service is running on port 1455.",
              []
            )
        end

      :handled
    else
      :not_handled
    end
  end

  defp ensure_url_scheme(""), do: nil

  defp ensure_url_scheme(url) when is_binary(url) do
    if String.starts_with?(url, ["http://", "https://"]) do
      url
    else
      "http://" <> url
    end
  end

  defp check_with_curl(url) when is_binary(url) do
    case System.find_executable("curl") do
      nil ->
        {:error, :curl_not_found}

      curl ->
        args = [
          "--silent",
          "--show-error",
          "--location",
          "--max-time",
          "2",
          "--connect-timeout",
          "1",
          "--output",
          "/dev/null",
          "--write-out",
          "%{http_code}",
          url
        ]

        case System.cmd(curl, args, stderr_to_stdout: true) do
          {code_str, 0} ->
            status = code_str |> String.trim() |> parse_http_code()

            cond do
              is_integer(status) and status in 200..399 ->
                Logger.info("Telegram localhost:1455 check ok", status: status)
                {:ok, status}

              is_integer(status) ->
                Logger.warning("Telegram localhost:1455 check not ok", status: status)
                {:not_ok, status}

              true ->
                {:error, {:unexpected_curl_output, code_str}}
            end

          {output, exit_status} ->
            {:error, {:curl_failed, exit_status, String.trim(output)}}
        end
    end
  end

  defp parse_http_code(<<a, b, c>>) when a in ?0..?9 and b in ?0..?9 and c in ?0..?9 do
    (a - ?0) * 100 + (b - ?0) * 10 + (c - ?0)
  end

  defp parse_http_code(_), do: nil

  defp find_recent_thread(reply_to) do
    query = Ash.Query.for_read(Thread, :find_recent_for_reply_to, %{reply_to: reply_to})

    case Ash.read(query) do
      {:ok, [thread | _]} -> {:ok, thread}
      {:ok, []} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp start_turn(interaction) do
    case Piano.Codex.start_turn(interaction) do
      {:ok, interaction} -> {:ok, interaction}
      {:error, reason} -> {:error, {:codex_start_failed, reason}}
    end
  end

  @doc """
  Request transcript for the current thread of a Telegram chat.
  Returns {:ok, :pending} when request is sent, or {:error, reason} on failure.
  The actual transcript is delivered asynchronously via Telegram.
  """
  @spec get_thread_transcript(integer()) :: {:ok, :pending} | {:error, term()}
  def get_thread_transcript(chat_id) do
    reply_to = "telegram:#{chat_id}"

    case find_recent_thread(reply_to) do
      {:ok, %{codex_thread_id: nil}} ->
        {:error, :no_thread}

      {:ok, %{codex_thread_id: codex_thread_id}} ->
        request_id = :erlang.unique_integer([:positive, :monotonic])

        :ok =
          RequestMap.put(request_id, %{
            type: :telegram_thread_transcript,
            chat_id: chat_id,
            codex_thread_id: codex_thread_id
          })

        :ok =
          CodexClient.send_request("thread/read", %{threadId: codex_thread_id, includeTurns: true}, request_id)

        {:ok, :pending}

      {:error, :not_found} ->
        {:error, :no_thread}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
