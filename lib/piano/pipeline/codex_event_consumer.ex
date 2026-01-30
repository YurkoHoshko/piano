defmodule Piano.Pipeline.CodexEventConsumer do
  @moduledoc false

  require Logger

  alias Piano.Core.{Interaction, InteractionItem, Thread}
  alias Piano.Codex.RequestMap
  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  def process(%{method: method, params: params}) do
    method = normalize_method(method)

    case method do
      "rpc/response" ->
        handle_response(params)
        :ok

      m when m in ["account/updated", "account/login/completed", "account/rateLimits/updated"] ->
        handle_account_notification(m, params)
        :ok

      "thread/started" ->
        Logger.info("Codex thread started", codex_thread_id: extract_thread_id(params))
        :ok

      "thread/archived" ->
        Logger.info("Codex thread archived", codex_thread_id: extract_thread_id(params))
        :ok

      _ ->
        with {:ok, interaction} <- fetch_interaction(params),
             {:ok, interaction} <- Ash.load(interaction, [:thread]) do
          dispatch(interaction, method, params)
          :ok
        else
          {:error, _} = error ->
            if method in ["turn/started", "turn/completed", "item/started", "item/completed"] do
              Logger.warning(
                "Codex event ignored (unmapped #{method}) error=#{inspect(error)} params_keys=#{inspect(Map.keys(params))}"
              )
            else
              Logger.debug("Codex event ignored (#{method}): #{inspect(error)}")
            end
            :ok
        end
    end
  end

  defp fetch_interaction(params) do
    interaction_id = extract_interaction_id(params)
    turn_id = extract_turn_id(params)
    thread_id = extract_thread_id(params)

    cond do
      is_binary(interaction_id) ->
        Ash.get(Interaction, interaction_id)

      is_binary(turn_id) and is_binary(thread_id) ->
        fetch_interaction_by_turn_and_thread(turn_id, thread_id)

      is_binary(turn_id) ->
        fetch_interaction_by_turn(nil, turn_id)

      is_binary(thread_id) ->
        fetch_latest_for_thread(thread_id)

      true ->
        {:error, :missing_turn_id}
    end
  end

  defp fetch_latest_for_thread(codex_thread_id) do
    with {:ok, thread} <- fetch_thread(codex_thread_id) do
      fetch_latest_interaction(thread.id)
    end
  end

  defp fetch_interaction_by_turn_and_thread(turn_id, codex_thread_id) do
    case fetch_thread(codex_thread_id) do
      {:ok, thread} ->
        fetch_interaction_by_turn(thread.id, turn_id)
        |> maybe_fallback_latest(thread.id)

      {:error, _} = error ->
        error
    end
  end

  defp maybe_fallback_latest({:ok, interaction}, _thread_id), do: {:ok, interaction}

  defp maybe_fallback_latest({:error, :not_found}, thread_id) do
    fetch_latest_interaction(thread_id)
  end

  defp maybe_fallback_latest({:error, _} = error, _thread_id), do: error

  defp fetch_thread(codex_thread_id) do
    query =
      Thread
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(codex_thread_id == ^codex_thread_id))

    case Ash.read(query) do
      {:ok, [thread | _]} -> {:ok, thread}
      {:ok, []} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp fetch_latest_interaction(thread_id) do
    query =
      Interaction
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(thread_id == ^thread_id))
      |> Ash.Query.sort(inserted_at: :desc)

    case Ash.read(query) do
      {:ok, [interaction | _]} -> {:ok, interaction}
      {:ok, []} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp fetch_interaction_by_turn(thread_id, turn_id) do
    query =
      Interaction
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(
        expr(
          codex_turn_id == ^turn_id and
            (is_nil(^thread_id) or thread_id == ^thread_id)
        )
      )
      |> Ash.Query.sort(inserted_at: :desc)

    case Ash.read(query) do
      {:ok, [interaction | _]} -> {:ok, interaction}
      {:ok, []} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp dispatch(interaction, "turn/started", params) do
    mark_interaction_started(interaction, params)

    Logger.info(
      "Codex turn started",
      interaction_id: interaction.id,
      thread_id: interaction.thread_id,
      codex_thread_id: extract_thread_id(params),
      turn_id: extract_turn_id(params)
    )

    notify_surface(interaction, :turn_started, params)
  end

  defp dispatch(interaction, "turn/completed", params) do
    log_turn_completed(interaction, params)
    notify_surface(interaction, :turn_completed, params)
    finalize_interaction(interaction, params)
  end

  defp dispatch(interaction, "item/started", params) do
    notify_surface(interaction, :item_started, params)
    handle_item_started(interaction, params)
  end

  defp dispatch(interaction, "item/completed", params) do
    notify_surface(interaction, :item_completed, params)
    handle_item_completed(interaction, params)
  end

  defp dispatch(interaction, "item/agentMessage/delta", params) do
    notify_surface(interaction, :agent_message_delta, params)
    handle_message_delta(params)
  end

  defp dispatch(interaction, "codex/event/task_started", params) do
    dispatch(interaction, "turn/started", params)
  end

  defp dispatch(interaction, "codex/event/task_completed", params) do
    dispatch(interaction, "turn/completed", params)
  end

  defp dispatch(interaction, "codex/event/item_started", params) do
    dispatch(interaction, "item/started", params)
  end

  defp dispatch(interaction, "codex/event/item_completed", params) do
    dispatch(interaction, "item/completed", params)
  end

  defp dispatch(_interaction, _method, _params), do: :ok

  defp notify_surface(interaction, event, params) do
    case build_surface(interaction.reply_to) do
      {:ok, surface} ->
        case event do
          :turn_started -> Piano.Surface.on_turn_started(surface, interaction, params)
          :turn_completed -> Piano.Surface.on_turn_completed(surface, interaction, params)
          :item_started -> Piano.Surface.on_item_started(surface, interaction, params)
          :item_completed -> Piano.Surface.on_item_completed(surface, interaction, params)
          :agent_message_delta -> Piano.Surface.on_agent_message_delta(surface, interaction, params)
        end

      :error ->
        Logger.warning("Unknown surface type for reply_to: #{interaction.reply_to}")
        {:ok, :noop}
    end
  rescue
    e ->
      Logger.error("Surface event error: #{inspect(e)}")
      :ok
  end

  defp build_surface("telegram:" <> _ = reply_to) do
    Piano.Telegram.Surface.parse(reply_to)
  end

  defp build_surface(_), do: :error

  defp handle_item_started(interaction, params) do
    item = params["item"] || params
    item_id = item["id"] || item["itemId"]
    type = map_item_type(item["type"] || params["type"])

    Ash.create(InteractionItem, %{
      codex_item_id: item_id,
      type: type,
      payload: params,
      interaction_id: interaction.id
    })
    :ok
  end

  defp handle_item_completed(interaction, params) do
    item = params["item"] || params
    item_id = item["id"] || item["itemId"]
    type = map_item_type(item["type"] || params["type"])

    case find_item(interaction.id, item_id) do
      {:ok, record} ->
        handle_completed_item(record, interaction, item_id, type, params)

      {:error, _} ->
        handle_missing_completed_item(interaction, item_id, type, params)
    end
  end

  defp handle_completed_item(record, interaction, item_id, type, params) do
    case Ash.update(record, %{payload: params}, action: :complete) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        _ = create_interaction_item(interaction, item_id, type, params)
        :ok
    end

    maybe_update_response_from_item(interaction, params)
    :ok
  end

  defp handle_missing_completed_item(interaction, item_id, type, params) do
    case create_interaction_item(interaction, item_id, type, params) do
      {:ok, record} ->
        _ = Ash.update(record, %{payload: params}, action: :complete)
        maybe_update_response_from_item(interaction, params)
        :ok

      _ ->
        :ok
    end
  end

  defp create_interaction_item(interaction, item_id, type, params) do
    Ash.create(InteractionItem, %{
      codex_item_id: item_id,
      type: type,
      payload: params,
      interaction_id: interaction.id
    })
  end

  defp handle_message_delta(_params), do: :ok

  defp handle_response(params) do
    case RequestMap.pop(params["id"]) do
      {:ok, %{type: :thread_start, thread_id: thread_id, client: client}} ->
        Logger.info("Codex thread/start response mapped request_id=#{inspect(params["id"])} thread_id=#{thread_id}")
        handle_thread_start_response(thread_id, params, client)

      {:ok, %{type: :turn_start, interaction_id: interaction_id, thread_id: thread_id, client: client}} ->
        Logger.info("Codex turn/start response mapped request_id=#{inspect(params["id"])} interaction_id=#{interaction_id}")

        case params do
          %{"error" => error} ->
            handle_turn_start_error(thread_id, interaction_id, error, client)

          _ ->
            handle_turn_start_response(interaction_id, params)
        end

      {:ok, %{type: :telegram_account_login_start, chat_id: chat_id}} ->
        handle_telegram_account_login_start(chat_id, params)

      {:ok, %{type: :telegram_account_read, chat_id: chat_id}} ->
        handle_telegram_account_read(chat_id, params)

      {:ok, %{type: :telegram_account_logout, chat_id: chat_id}} ->
        handle_telegram_account_logout(chat_id, params)

      {:ok, %{type: :telegram_thread_transcript, chat_id: chat_id}} ->
        handle_telegram_thread_transcript(chat_id, params)

      {:ok, %{type: :config_read}} ->
        handle_config_read(params)
        :ok

      {:ok, %{type: :startup_account_read}} ->
        handle_startup_account_read(params)

      _ ->
        Logger.debug("Codex RPC response ignored (no mapping) request_id=#{inspect(params["id"])}")
        :ok
    end
  end

  defp handle_startup_account_read(%{"result" => result}) do
    Piano.Observability.put_account_status(result)
    Logger.info("Codex auth status: #{inspect(result)}")

    # If a local profile is selected but Codex says OpenAI auth is required, it
    # usually means the profile/config isn't being applied.
    requires_openai = result["requiresOpenaiAuth"] == true
    profile = safe_current_profile()

    if requires_openai and profile in [:fast, :smart] do
      Logger.warning(
        "Codex reports requiresOpenaiAuth=true under a local profile; check CODEX_HOME/config and profile selection",
        current_profile: profile
      )
    end

    :ok
  end

  defp handle_startup_account_read(%{"error" => error}) do
    Logger.warning("Codex auth status check failed: #{inspect(error)}")
    :ok
  end

  defp handle_startup_account_read(_params), do: :ok

  defp handle_config_read(%{"result" => result}) when is_map(result) do
    config = result["config"] || %{}

    # Keep it small; this can be large.
    summary =
      if is_map(config) do
        Map.take(config, ["profile", "model", "model_provider", "approval_policy", "sandbox_mode"])
      else
        %{}
      end

    Logger.info("Codex config/read #{inspect(summary)}")
    :ok
  end

  defp handle_config_read(%{"error" => error}) do
    Logger.warning("Codex config/read failed: #{inspect(error)}")
    :ok
  end

  defp handle_config_read(_), do: :ok

  defp safe_current_profile do
    try do
      Piano.Codex.Config.current_profile!()
    rescue
      _ -> :unknown
    end
  end

  defp handle_telegram_account_login_start(chat_id, %{"result" => result}) when is_integer(chat_id) do
    auth_url = result["authUrl"]
    login_id = result["loginId"]

    cond do
      is_binary(auth_url) ->
        Piano.Telegram.API.send_message(
          chat_id,
          """
          Open this URL in a browser to finish ChatGPT login:
          #{auth_url}

          loginId: #{inspect(login_id)}
          After completing login, run /codexaccount to confirm.
          """,
          []
        )

        :ok

      true ->
        Piano.Telegram.API.send_message(chat_id, "Unexpected login response: #{inspect(result)}", [])
        :ok
    end
  end

  defp handle_telegram_account_login_start(chat_id, %{"error" => error}) when is_integer(chat_id) do
    Piano.Telegram.API.send_message(chat_id, "Failed to start login: #{inspect(error)}", [])
    :ok
  end

  defp handle_telegram_account_login_start(_chat_id, _params), do: :ok

  defp handle_telegram_account_read(chat_id, %{"result" => result}) when is_integer(chat_id) do
    Piano.Observability.put_account_status(result)
    Piano.Telegram.API.send_message(chat_id, "Codex account: #{inspect(result)}", [])
    :ok
  end

  defp handle_telegram_account_read(chat_id, %{"error" => error}) when is_integer(chat_id) do
    Piano.Telegram.API.send_message(chat_id, "Failed to read account: #{inspect(error)}", [])
    :ok
  end

  defp handle_telegram_account_read(_chat_id, _params), do: :ok

  defp handle_telegram_account_logout(chat_id, %{"result" => _result}) when is_integer(chat_id) do
    Piano.Telegram.API.send_message(chat_id, "✅ Logged out. Run /codexaccount to confirm.", [])
    :ok
  end

  defp handle_telegram_account_logout(chat_id, %{"error" => error}) when is_integer(chat_id) do
    Piano.Telegram.API.send_message(chat_id, "Failed to logout: #{inspect(error)}", [])
    :ok
  end

  defp handle_telegram_account_logout(_chat_id, _params), do: :ok

  # Delegate transcript handling to the Surface protocol.
  # The surface is responsible for formatting and delivery (message vs file).
  defp handle_telegram_thread_transcript(chat_id, %{"result" => result}) when is_integer(chat_id) do
    Logger.debug("Transcript response keys: #{inspect(Map.keys(result))}")
    Logger.debug("Transcript response: #{inspect(result, limit: :infinity, printable_limit: :infinity)}")
    surface = %Piano.Telegram.Surface{chat_id: chat_id, message_id: 0}
    Piano.Surface.send_thread_transcript(surface, result)
    :ok
  end

  defp handle_telegram_thread_transcript(chat_id, %{"error" => error}) when is_integer(chat_id) do
    Piano.Telegram.API.send_message(chat_id, "Failed to get transcript: #{inspect(error)}", [])
    :ok
  end

  defp handle_telegram_thread_transcript(_chat_id, _params), do: :ok

  defp handle_thread_start_response(thread_id, params, client) do
    codex_thread_id =
      get_in(params, ["result", "thread", "id"]) ||
        get_in(params, ["result", "threadId"]) ||
        get_in(params, ["result", "thread", "threadId"])

    Logger.info(
      "Codex thread/start response mapped",
      thread_id: thread_id,
      codex_thread_id: codex_thread_id
    )

    cond do
      not is_binary(thread_id) ->
        :ok

      not is_binary(codex_thread_id) ->
        Logger.warning("Codex thread/start response missing thread id: #{inspect(params)}")
        :ok

      true ->
        with {:ok, thread} <- Ash.get(Thread, thread_id),
             {:ok, updated} <- Ash.update(thread, %{codex_thread_id: codex_thread_id}, action: :set_codex_thread_id) do
          start_pending_interactions(updated, client)
        else
          _ -> :ok
        end
    end
  end

  defp start_pending_interactions(thread, client) do
    query =
      Interaction
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

  defp handle_turn_start_response(interaction_id, params) do
    turn_id =
      get_in(params, ["result", "turn", "id"]) ||
        get_in(params, ["result", "turnId"])

    if is_binary(turn_id) do
      case Ash.get(Interaction, interaction_id) do
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

  defp mark_interaction_started(interaction, params) do
    turn_id = params["turnId"] || get_in(params, ["turn", "id"])

    if is_binary(turn_id) and interaction.codex_turn_id != turn_id do
      _ = Ash.update(interaction, %{codex_turn_id: turn_id}, action: :start)
    end

    :ok
  end

  defp finalize_interaction(interaction, params) do
    response = interaction.response || extract_response_from_items(interaction.id)
    action = interaction_action_from_turn(params)

    attrs =
      case action do
        :interrupt -> %{}
        _ -> %{response: response}
      end

    _ = Ash.update(interaction, attrs, action: action)
    :ok
  end

  defp interaction_action_from_turn(params) do
    status = params["status"] || get_in(params, ["turn", "status"])

    cond do
      status in ["failed", "error"] or is_map(get_in(params, ["turn", "error"])) ->
        :fail

      status in ["interrupted", "cancelled", "canceled"] ->
        :interrupt

      true ->
        :complete
    end
  end

  defp log_turn_completed(interaction, params) do
    usage = extract_usage(params)
    elapsed_ms = extract_elapsed_ms(params)
    item_summary = extract_items_summary(params)

    tps =
      cond do
        is_integer(usage.output_tokens) and is_number(elapsed_ms) and elapsed_ms > 0 ->
          usage.output_tokens / (elapsed_ms / 1000)

        is_number(item_summary.predicted_per_token_ms) and item_summary.predicted_per_token_ms > 0 ->
          1000 / item_summary.predicted_per_token_ms

        true ->
          nil
      end

    status =
      params["status"] || get_in(params, ["turn", "status"]) || "unknown"

    maybe_error = get_in(params, ["turn", "error"]) || params["error"]

    if is_map(maybe_error) do
      Logger.error(
        "Codex turn completed status=#{status} elapsed_ms=#{inspect(elapsed_ms)} usage=#{inspect(usage)} tps=#{format_float(tps)} items=#{item_summary.total_items} tools=#{item_summary.tool_types} error=#{inspect(maybe_error)}",
        interaction_id: interaction.id,
        thread_id: interaction.thread_id,
        codex_thread_id: extract_thread_id(params),
        turn_id: extract_turn_id(params)
      )
    else
      Logger.info(
        "Codex turn completed status=#{status} elapsed_ms=#{inspect(elapsed_ms)} usage=#{inspect(usage)} tps=#{format_float(tps)} items=#{item_summary.total_items} tools=#{item_summary.tool_types}",
        interaction_id: interaction.id,
        thread_id: interaction.thread_id,
        codex_thread_id: extract_thread_id(params),
        turn_id: extract_turn_id(params)
      )
    end
  end

  defp format_float(nil), do: "n/a"
  defp format_float(value) when is_number(value), do: :io_lib.format("~.2f", [value]) |> IO.iodata_to_binary()

  defp extract_usage(params) do
    usage =
      get_in(params, ["turn", "usage"]) ||
        params["usage"] ||
        get_in(params, ["result", "usage"]) ||
        get_in(params, ["turn", "result", "usage"])

    normalize_usage(usage)
  end

  defp normalize_usage(%{} = usage) do
    input =
      usage["input_tokens"] || usage["inputTokens"] || usage["prompt_tokens"] || usage["promptTokens"] ||
        usage[:input_tokens] || usage[:inputTokens] || usage[:prompt_tokens] || usage[:promptTokens]

    output =
      usage["output_tokens"] || usage["outputTokens"] || usage["completion_tokens"] || usage["completionTokens"] ||
        usage[:output_tokens] || usage[:outputTokens] || usage[:completion_tokens] || usage[:completionTokens]

    total =
      usage["total_tokens"] || usage["totalTokens"] || usage[:total_tokens] || usage[:totalTokens]

    %{
      input_tokens: int_or_nil(input),
      output_tokens: int_or_nil(output),
      total_tokens: int_or_nil(total)
    }
  end

  defp normalize_usage(_), do: %{input_tokens: nil, output_tokens: nil, total_tokens: nil}

  defp int_or_nil(nil), do: nil
  defp int_or_nil(value) when is_integer(value), do: value

  defp int_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp int_or_nil(_), do: nil

  defp extract_elapsed_ms(params) do
    params["elapsedMs"] ||
      params["elapsed_ms"] ||
      get_in(params, ["turn", "elapsedMs"]) ||
      get_in(params, ["turn", "elapsed_ms"]) ||
      get_in(params, ["turn", "metrics", "elapsedMs"]) ||
      get_in(params, ["turn", "metrics", "elapsed_ms"]) ||
      get_in(params, ["turn", "timings", "total_ms"]) ||
      get_in(params, ["turn", "timings", "totalMs"])
  end

  defp extract_items_summary(params) do
    items = get_in(params, ["turn", "items"]) || params["items"] || []

    counts =
      if is_list(items) do
        items
        |> Enum.map(&(&1["type"] || &1[:type]))
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(%{}, fn type, acc -> Map.update(acc, type, 1, &(&1 + 1)) end)
      else
        %{}
      end

    tool_types =
      counts
      |> Enum.reject(fn {k, _} -> k in ["userMessage", "agentMessage", "reasoning", :userMessage, :agentMessage, :reasoning] end)
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map_join(",", fn {k, v} -> "#{k}=#{v}" end)

    total_items = counts |> Map.values() |> Enum.sum()

    predicted_per_token_ms =
      get_in(params, ["turn", "timings", "predicted_per_token_ms"]) ||
        get_in(params, ["turn", "timings", "predictedPerTokenMs"])

    %{
      total_items: total_items,
      tool_types: tool_types,
      predicted_per_token_ms: predicted_per_token_ms
    }
  end

  defp handle_account_notification(method, params) do
    status = params["account"] || params
    Piano.Observability.put_account_status(status)
    Logger.info("Codex account notification #{method}")
    :ok
  rescue
    e ->
      Logger.warning("Codex account notification handler failed: #{Exception.message(e)}")
      :ok
  end

  defp extract_response_from_items(interaction_id) do
    case list_items_by_interaction(interaction_id) do
      {:ok, items} ->
        items
        |> Enum.filter(&(&1.type == :agent_message))
        |> Enum.sort_by(& &1.inserted_at)
        |> Enum.map(&extract_item_text/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      _ ->
        nil
    end
  end

  defp extract_item_text(item) do
    get_in(item.payload, ["item", "text"]) ||
      extract_text_from_content(get_in(item.payload, ["item", "content"]))
  end

  defp maybe_update_response_from_item(%Interaction{} = interaction, params) do
    case item_type_from_params(params) do
      :agent_message -> update_response_from_item(interaction, params)
      _ -> :ok
    end
  end

  defp maybe_update_response_from_item(_interaction, _params), do: :ok

  defp item_type_from_params(params) do
    params
    |> Map.get("item", %{})
    |> Map.get("type", params["type"])
    |> map_item_type()
  end

  defp update_response_from_item(interaction, params) do
    case extract_item_text_from_params(params) do
      text when is_binary(text) and text != "" ->
        response = append_response_text(interaction.response, text)
        action = response_action(interaction.status)
        _ = Ash.update(interaction, %{response: response}, action: action)
        :ok

      _ ->
        :ok
    end
  end

  defp extract_item_text_from_params(params) do
    get_in(params, ["item", "text"]) ||
      extract_text_from_content(get_in(params, ["item", "content"]))
  end

  defp append_response_text(nil, text), do: text
  defp append_response_text("", text), do: text
  defp append_response_text(existing, text), do: existing <> "\n" <> text

  defp response_action(:complete), do: :complete
  defp response_action(_), do: :set_response

  defp extract_text_from_content(content) when is_list(content) do
    content
    |> Enum.map(& &1["text"])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")
  end

  defp extract_text_from_content(_), do: nil

  defp find_item(interaction_id, item_id) do
    with {:ok, items} <- list_items_by_interaction(interaction_id) do
      case Enum.find(items, &(&1.codex_item_id == item_id)) do
        nil -> {:error, :not_found}
        item -> {:ok, item}
      end
    end
  end

  defp list_items_by_interaction(interaction_id) do
    InteractionItem
    |> Ash.Query.for_read(:list_by_interaction, %{interaction_id: interaction_id})
    |> Ash.read()
  end

  defp map_item_type("userMessage"), do: :user_message
  defp map_item_type("agentMessage"), do: :agent_message
  defp map_item_type("reasoning"), do: :reasoning
  defp map_item_type("commandExecution"), do: :command_execution
  defp map_item_type("fileChange"), do: :file_change
  defp map_item_type("mcpToolCall"), do: :mcp_tool_call
  defp map_item_type("webSearch"), do: :web_search
  defp map_item_type(_), do: :agent_message

  defp normalize_method(method) when is_binary(method) do
    String.replace(method, ".", "/")
  end

  defp normalize_method(method), do: method

  defp extract_interaction_id(params) do
    params["interactionId"]
  end

  defp extract_turn_id(params) do
    params["turnId"] ||
      get_in(params, ["turn", "id"]) ||
      get_in(params, ["turn", "turnId"]) ||
      get_in(params, ["item", "turnId"]) ||
      get_in(params, ["item", "turn", "id"])
  end

  defp extract_thread_id(%{"threadId" => thread_id}) when is_binary(thread_id), do: thread_id

  defp extract_thread_id(params) when is_map(params) do
    get_in(params, ["thread", "id"]) ||
      get_in(params, ["turn", "threadId"]) ||
      get_in(params, ["turn", "thread", "id"]) ||
      get_in(params, ["item", "threadId"]) ||
      get_in(params, ["item", "thread", "id"])
  end

  defp extract_thread_id(_), do: nil

end
