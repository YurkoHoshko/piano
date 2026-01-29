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

      _ ->
        if is_binary(method) and String.starts_with?(method, "codex/event/") do
          Logger.debug(
            "Codex event received #{method} params=#{inspect(Map.take(params, ["turnId", "turn", "item", "type"]))}"
          )
        end

        with {:ok, interaction} <- fetch_interaction(params),
             {:ok, interaction} <- Ash.load(interaction, [:surface, :thread]) do
          dispatch(interaction, method, params)
          :ok
        else
          {:error, _} = error ->
            Logger.debug("Codex event ignored (#{method}): #{inspect(error)}")
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
        with {:ok, thread} <- fetch_thread(thread_id),
             {:ok, interaction} <- fetch_interaction_by_turn(thread.id, turn_id) do
          {:ok, interaction}
        else
          {:error, :not_found} ->
            with {:ok, thread} <- fetch_thread(thread_id) do
              fetch_latest_interaction(thread.id)
            end

          {:error, _} = error ->
            error
        end

      is_binary(turn_id) ->
        fetch_interaction_by_turn(nil, turn_id)

      is_binary(thread_id) ->
        with {:ok, thread} <- fetch_thread(thread_id),
             {:ok, interaction} <- fetch_latest_interaction(thread.id) do
          {:ok, interaction}
        end

      true ->
        {:error, :missing_turn_id}
    end
  end

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
    notify_surface(interaction, :turn_started, params)
  end

  defp dispatch(interaction, "turn/completed", params) do
    notify_surface(interaction, :turn_completed, params)
    finalize_interaction(interaction)
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
    surface = interaction.surface

    case event do
      :turn_started -> Piano.Surface.on_turn_started(surface, interaction, params)
      :turn_completed -> Piano.Surface.on_turn_completed(surface, interaction, params)
      :item_started -> Piano.Surface.on_item_started(surface, interaction, params)
      :item_completed -> Piano.Surface.on_item_completed(surface, interaction, params)
      :agent_message_delta -> Piano.Surface.on_agent_message_delta(surface, interaction, params)
    end
  rescue
    e ->
      Logger.error("Surface event error: #{inspect(e)}")
      :ok
  end

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
        case Ash.update(record, %{payload: params}, action: :complete) do
          {:ok, _} -> :ok
          {:error, _} ->
            _ =
              Ash.create(InteractionItem, %{
                codex_item_id: item_id,
                type: type,
                payload: params,
                interaction_id: interaction.id
              })
        end

        maybe_update_response_from_item(interaction, params)
        :ok

      {:error, _} ->
        case Ash.create(InteractionItem, %{
               codex_item_id: item_id,
               type: type,
               payload: params,
               interaction_id: interaction.id
             }) do
          {:ok, record} ->
            _ = Ash.update(record, %{payload: params}, action: :complete)
            maybe_update_response_from_item(interaction, params)
            :ok

          _ ->
            :ok
        end
    end
  end

  defp handle_message_delta(_params), do: :ok

  defp handle_response(params) do
    case RequestMap.pop(params["id"]) do
      {:ok, %{type: :thread_start, thread_id: thread_id, client: client}} ->
        Logger.debug("Codex thread/start response mapped request_id=#{inspect(params["id"])} thread_id=#{thread_id}")
        handle_thread_start_response(thread_id, params, client)

      {:ok, %{type: :turn_start, interaction_id: interaction_id}} ->
        Logger.debug("Codex turn/start response mapped request_id=#{inspect(params["id"])} interaction_id=#{interaction_id}")
        handle_turn_start_response(interaction_id, params)

      _ ->
        Logger.debug("Codex RPC response ignored (no mapping) request_id=#{inspect(params["id"])}")
        :ok
    end
  end

  defp handle_thread_start_response(thread_id, params, client) do
    codex_thread_id =
      get_in(params, ["result", "thread", "id"]) ||
        get_in(params, ["result", "threadId"]) ||
        get_in(params, ["result", "thread", "threadId"])

    Logger.debug(
      "Codex thread/start response received thread_id=#{thread_id} codex_thread_id=#{inspect(codex_thread_id)}"
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
        Logger.debug(
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
          :ok

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp mark_interaction_started(interaction, params) do
    turn_id = params["turnId"] || get_in(params, ["turn", "id"])

    if is_binary(turn_id) and interaction.codex_turn_id != turn_id do
      _ = Ash.update(interaction, %{codex_turn_id: turn_id}, action: :start)
    end

    :ok
  end

  defp finalize_interaction(interaction) do
    response = interaction.response || extract_response_from_items(interaction.id)
    _ = Ash.update(interaction, %{response: response}, action: :complete)
    :ok
  end

  defp extract_response_from_items(interaction_id) do
    with {:ok, items} <- list_items_by_interaction(interaction_id) do
      items
      |> Enum.filter(&(&1.type == :agent_message))
      |> Enum.sort_by(& &1.inserted_at)
      |> Enum.map(&extract_item_text/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    else
      _ -> nil
    end
  end

  defp extract_item_text(item) do
    get_in(item.payload, ["item", "text"]) ||
      extract_text_from_content(get_in(item.payload, ["item", "content"]))
  end

  defp maybe_update_response_from_item(%Interaction{} = interaction, params) do
    item_type =
      params
      |> Map.get("item", %{})
      |> Map.get("type", params["type"])
      |> map_item_type()

    if item_type == :agent_message do
      text =
        get_in(params, ["item", "text"]) ||
          extract_text_from_content(get_in(params, ["item", "content"]))

      if is_binary(text) and text != "" do
        response =
          case interaction.response do
            nil -> text
            "" -> text
            existing -> existing <> "\n" <> text
          end

        action = if interaction.status == :complete, do: :complete, else: :set_response
        _ = Ash.update(interaction, %{response: response}, action: action)
      end
    end

    :ok
  end

  defp maybe_update_response_from_item(_interaction, _params), do: :ok

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
