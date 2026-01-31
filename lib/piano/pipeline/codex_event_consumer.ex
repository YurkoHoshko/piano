defmodule Piano.Pipeline.CodexEventConsumer do
  @moduledoc """
  Consumes parsed Codex events from the pipeline.

  This module is now a thin orchestration layer that:
  1. Receives parsed events from the pipeline
  2. Persists them via Piano.Codex.Persistence
  3. Notifies surfaces via Piano.Codex.Notifications
  4. Handles RPC responses
  """

  require Logger
  require Ash.Query

  import Ash.Expr, only: [expr: 1]


  alias Piano.Codex.Notifications
  alias Piano.Codex.Persistence
  alias Piano.Codex.RequestMap
  alias Piano.Codex.Responses

  @doc """
  Process an event from the pipeline.

  Events are maps with:
  - `:type` - :event or :rpc_response
  - `:event` - The parsed %Events{} struct (for :event type)
  - `:payload` - Raw map (for :rpc_response type)
  """
  @spec process(map()) :: :ok
  def process(%{type: :rpc_response, payload: payload}) do
    handle_response(payload)
    :ok
  end

  def process(%{type: :event, event: event}) when is_struct(event) do
    # Persist the event and get the associated interaction
    case Persistence.process_event(event) do
      {:ok, interaction} ->
        # Log the event for observability
        Notifications.log_event(event, interaction)
        # Notify surfaces
        if interaction do
          Notifications.notify(interaction, event)
        end
        :ok

      {:error, error} ->
        Notifications.log_unmapped(event, error)
        :ok
    end
  end

  def process(%{type: :event, event: %{method: method} = _raw_event}) do
    # Handle unparsed events (fallback)
    Logger.warning("Received unparsed event: #{method}")
    :ok
  end

  def process(other) do
    Logger.warning("Unknown event format: #{inspect(other)}")
    :ok
  end

  # ============================================================================
  # RPC Response Handling
  # ============================================================================

  defp handle_response(%{"id" => id} = payload) do
    case RequestMap.pop(id) do
      {:ok, %{type: request_type} = request_info} ->
        # Parse response once based on request type
        response = Responses.parse(request_type, payload)
        # Dispatch based on response struct type
        dispatch_response(response, request_info)

      _ ->
        Logger.debug("Codex RPC response ignored (no mapping) request_id=#{inspect(id)}")
        :ok
    end
  end

  defp dispatch_response(%Responses.ThreadStartResponse{} = response, %{thread_id: thread_id, client: client}) do
    handle_thread_start_response(thread_id, response, client)
  end

  defp dispatch_response(%Responses.TurnStartResponse{error: nil} = response, %{interaction_id: id}) do
    handle_turn_start_response(id, response)
  end

  defp dispatch_response(%Responses.TurnStartResponse{error: error} = _response, %{thread_id: tid, interaction_id: iid, client: client}) when not is_nil(error) do
    handle_turn_start_error(tid, iid, error, client)
  end

  defp dispatch_response(%Responses.LoginStartResponse{} = response, %{chat_id: chat_id}) do
    handle_telegram_account_login_start(chat_id, response)
  end

  defp dispatch_response(%Responses.AccountReadResponse{} = response, %{chat_id: chat_id, type: :telegram_account_read}) do
    handle_telegram_account_read(chat_id, response)
  end

  defp dispatch_response(%Responses.AccountReadResponse{} = response, %{type: :startup_account_read}) do
    handle_startup_account_read(response)
  end

  defp dispatch_response(%Responses.GenericResponse{} = response, %{chat_id: chat_id, type: :telegram_account_logout}) do
    handle_telegram_account_logout(chat_id, response)
  end

  defp dispatch_response(%Responses.ThreadTranscriptResponse{} = response, %{chat_id: chat_id, placeholder_message_id: msg_id}) do
    handle_telegram_thread_transcript(chat_id, response, msg_id)
  end
  
  defp dispatch_response(%Responses.ThreadTranscriptResponse{} = response, %{chat_id: chat_id}) do
    handle_telegram_thread_transcript(chat_id, response, nil)
  end

  defp dispatch_response(%Responses.ConfigReadResponse{} = response, %{type: :config_read}) do
    handle_config_read(response)
  end

  defp dispatch_response(response, request_info) do
    Logger.warning("Unhandled response type: #{response.__struct__} for request: #{inspect(request_info.type)}")
    :ok
  end

  # ============================================================================
  # Response Handlers
  # ============================================================================

  defp handle_thread_start_response(thread_id, %Responses.ThreadStartResponse{} = response, client) do
    codex_thread_id = response.thread_id

    Logger.info(
      "Codex thread/start response mapped",
      thread_id: thread_id,
      codex_thread_id: codex_thread_id
    )

    cond do
      not is_binary(thread_id) ->
        :ok

      not is_binary(codex_thread_id) ->
        Logger.warning("Codex thread/start response missing thread id: #{inspect(response.raw_response)}")
        :ok

      true ->
        with {:ok, thread} <- Piano.Core.Thread |> Ash.get(thread_id),
             {:ok, _updated} <- Ash.update(thread, %{codex_thread_id: codex_thread_id}, action: :set_codex_thread_id) do
          start_pending_interactions(thread, client)
        else
          _ -> :ok
        end
    end
  end

  defp handle_turn_start_response(interaction_id, %Responses.TurnStartResponse{} = response) do
    turn_id = response.turn_id

    if is_binary(turn_id) do
      case Piano.Core.Interaction |> Ash.get(interaction_id) do
        {:ok, interaction} ->
          _ = Ash.update(interaction, %{codex_turn_id: turn_id}, action: :start)
          Logger.info("Interaction started (turn id assigned)", interaction_id: interaction.id, turn_id: turn_id)
          :ok

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp handle_turn_start_error(thread_id, interaction_id, error, client) do
    msg = error["message"] || inspect(error)

    Logger.warning(
      "Codex turn/start failed",
      interaction_id: interaction_id,
      thread_id: thread_id,
      error: msg
    )

    if thread_missing_error?(msg) do
      Logger.warning(
        "Codex thread appears missing after reboot; force-starting a new Codex thread and retrying pending interactions",
        thread_id: thread_id
      )

      _ = Piano.Codex.force_start_thread(thread_id, client)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp thread_missing_error?(msg) when is_binary(msg) do
    down = String.downcase(msg)

    String.contains?(down, "thread") and
      (String.contains?(down, "not found") or String.contains?(down, "missing") or
         String.contains?(down, "unknown") or String.contains?(down, "invalid"))
  end

  defp thread_missing_error?(_), do: false

  defp start_pending_interactions(thread, client) do
    query =
      Piano.Core.Interaction
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(thread_id == ^thread.id and status == :pending))
      |> Ash.Query.sort(inserted_at: :asc)

    case Ash.read(query) do
      {:ok, interactions} ->
        Logger.info(
          "Starting pending interactions thread_id=#{thread.id} count=#{length(interactions)}"
        )

        Enum.each(interactions, fn interaction ->
          _ = Piano.Codex.start_turn(interaction, client: client)
        end)

      {:error, reason} ->
        Logger.debug(
          "Failed to load pending interactions thread_id=#{thread.id} reason=#{inspect(reason)}"
        )
        :ok

      _ ->
        :ok
    end
  end

  # ============================================================================
  # Account Handlers
  # ============================================================================

  defp handle_startup_account_read(%Responses.AccountReadResponse{} = response) do
    if response.error do
      Logger.warning("Codex auth status check failed: #{inspect(response.error)}")
    else
      Piano.Observability.put_account_status(response.account)
      Logger.info("Codex auth status: #{inspect(response.account)}")

      if response.requires_openai_auth and safe_current_profile() in [:fast, :smart] do
        Logger.warning(
          "Codex reports requiresOpenaiAuth=true under a local profile; check CODEX_HOME/config and profile selection",
          current_profile: safe_current_profile()
        )
      end
    end

    :ok
  end

  defp handle_config_read(%Responses.ConfigReadResponse{} = response) do
    if response.error do
      Logger.warning("Codex config/read failed: #{inspect(response.error)}")
    else
      summary =
        if is_map(response.config) do
          Map.take(response.config, ["profile", "model", "model_provider", "approval_policy", "sandbox_mode"])
        else
          %{}
        end

      Logger.info("Codex config/read #{inspect(summary)}")
    end

    :ok
  end

  defp handle_telegram_account_login_start(chat_id, %Responses.LoginStartResponse{} = response) do
    cond do
      response.error ->
        Piano.Telegram.Surface.send_message(chat_id, "Failed to start login: #{inspect(response.error)}", [])

      response.auth_url ->
        Piano.Telegram.Surface.send_message(
          chat_id,
          """
          Open this URL in a browser to finish ChatGPT login:
          #{response.auth_url}

          loginId: #{inspect(response.login_id)}
          After completing login, run /codexaccount to confirm.
          """,
          []
        )

      true ->
        Piano.Telegram.Surface.send_message(chat_id, "Unexpected login response", [])
    end

    :ok
  end

  defp handle_telegram_account_read(chat_id, %Responses.AccountReadResponse{} = response) do
    if response.error do
      Piano.Telegram.Surface.send_message(chat_id, "Failed to read account: #{inspect(response.error)}", [])
    else
      Piano.Observability.put_account_status(response.account)
      Piano.Telegram.Surface.send_message(chat_id, "Codex account: #{inspect(response.account)}", [])
    end

    :ok
  end

  defp handle_telegram_account_logout(chat_id, %Responses.GenericResponse{} = response) do
    if response.error do
      Piano.Telegram.Surface.send_message(chat_id, "Failed to logout: #{inspect(response.error)}", [])
    else
      Piano.Telegram.Surface.send_message(chat_id, "✅ Logged out. Run /codexaccount to confirm.", [])
    end

    :ok
  end

  defp handle_telegram_thread_transcript(chat_id, %Responses.ThreadTranscriptResponse{} = response, placeholder_msg_id) do
    if response.error do
      # Delete placeholder and send error
      if placeholder_msg_id do
        ExGram.delete_message(chat_id, placeholder_msg_id)
      end
      Piano.Telegram.Surface.send_message(chat_id, "Failed to get transcript: #{inspect(response.error)}", [])
    else
      # Delete placeholder message
      if placeholder_msg_id do
        ExGram.delete_message(chat_id, placeholder_msg_id)
      end
      
      # Build and send transcript
      thread_data = %{"thread" => response.thread, "turns" => response.turns}
      transcript = Piano.Transcript.Builder.from_thread_response(thread_data)

      thread_id = response.thread["id"] || "unknown"
      filename = "transcript_#{thread_id}.md"
      document = {:file_content, transcript, filename}

      Piano.Telegram.Surface.send_document(chat_id, document, caption: "📄 Thread transcript")
    end

    :ok
  end

  defp safe_current_profile do
    try do
      Piano.Codex.Config.current_profile!()
    rescue
      _ -> :unknown
    end
  end
end
