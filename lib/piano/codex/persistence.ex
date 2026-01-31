defmodule Piano.Codex.Persistence do
  @moduledoc """
  Handles persistence of Codex events to the database.

  This module provides a unified interface for saving events, interactions,
  and items to the database. It handles the complexity of mapping Codex
  events to Piano's core data models.
  """

  require Logger

  alias Piano.Codex.Events
  alias Piano.Core.{Interaction, InteractionItem, Thread}
  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  @doc """
  Process an event and persist it to the database.

  Returns the interaction if one was found/created, or nil if no
  persistence was needed.
  """
  @spec process_event(Events.event()) :: {:ok, Interaction.t() | nil} | {:error, term()}
  def process_event(event) when is_struct(event) do
    case event do
      %Events.TurnStarted{} ->
        with {:ok, interaction} <- find_or_create_interaction(event),
             {:ok, _} <- mark_interaction_started(interaction, event.turn_id) do
          {:ok, interaction}
        end

      %Events.TurnCompleted{} ->
        with {:ok, interaction} <- fetch_by_turn_or_thread(event.turn_id, event.thread_id),
             {:ok, _} <- finalize_interaction(interaction, event) do
          {:ok, interaction}
        end

      %Events.ItemStarted{} ->
        with {:ok, interaction} <- fetch_by_turn_or_thread(event.turn_id, event.thread_id),
             {:ok, _} <- create_interaction_item(interaction, event) do
          {:ok, interaction}
        end

      %Events.ItemCompleted{} ->
        with {:ok, interaction} <- fetch_by_turn_or_thread(event.turn_id, event.thread_id),
             {:ok, _} <- complete_interaction_item(interaction, event) do
          maybe_update_response_from_item(interaction, event)
          {:ok, interaction}
        end

      %Events.AgentMessageDelta{} ->
        fetch_by_turn_or_thread(event.turn_id, event.thread_id)

      %Events.AgentMessage{} ->
        with {:ok, interaction} <- fetch_by_turn_or_thread(event.turn_id, event.thread_id),
             {:ok, _} <- update_interaction_response(interaction, event.message) do
          {:ok, interaction}
        end

      %Events.ThreadStarted{} ->
        {:ok, nil}

      %Events.ThreadArchived{} ->
        {:ok, nil}

      _ ->
        Logger.debug("Unhandled event type for persistence: #{event.__struct__}")
        {:ok, nil}
    end
  end

  # ============================================================================
  # Interaction Management
  # ============================================================================

  defp find_or_create_interaction(%{turn_id: turn_id, thread_id: thread_id}) do
    case find_by_turn_id(turn_id) do
      {:ok, interaction} -> {:ok, interaction}
      {:error, :not_found} -> fetch_by_turn_or_thread(turn_id, thread_id)
    end
  end

  defp fetch_by_turn_or_thread(nil, nil), do: {:error, :missing_ids}

  defp fetch_by_turn_or_thread(turn_id, nil) when is_binary(turn_id) do
    fetch_interaction_by_turn(nil, turn_id)
  end

  defp fetch_by_turn_or_thread(turn_id, thread_id) when is_binary(turn_id) and is_binary(thread_id) do
    fetch_interaction_by_turn_and_thread(turn_id, thread_id)
  end

  defp fetch_by_turn_or_thread(nil, thread_id) when is_binary(thread_id) do
    fetch_latest_for_thread(thread_id)
  end

  defp fetch_by_turn_or_thread(_, _), do: {:error, :invalid_ids}

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
  defp maybe_fallback_latest({:error, :not_found}, thread_id), do: fetch_latest_interaction(thread_id)
  defp maybe_fallback_latest({:error, _} = error, _thread_id), do: error

  defp fetch_latest_for_thread(codex_thread_id) do
    with {:ok, thread} <- fetch_thread(codex_thread_id) do
      fetch_latest_interaction(thread.id)
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

  defp find_by_turn_id(turn_id) do
    query =
      Interaction
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(codex_turn_id == ^turn_id))
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)

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

  defp mark_interaction_started(interaction, turn_id) do
    if is_binary(turn_id) and interaction.codex_turn_id != turn_id do
      Ash.update(interaction, %{codex_turn_id: turn_id}, action: :start)
    else
      {:ok, interaction}
    end
  end

  defp finalize_interaction(interaction, %Events.TurnCompleted{} = event) do
    response = interaction.response || extract_response_from_items(interaction.id)
    action = interaction_action_from_event(event)

    attrs =
      case action do
        :interrupt -> %{}
        _ -> %{response: response}
      end

    Ash.update(interaction, attrs, action: action)
  end

  defp interaction_action_from_event(%Events.TurnCompleted{status: :failed}), do: :fail
  defp interaction_action_from_event(%Events.TurnCompleted{status: :interrupted}), do: :interrupt
  defp interaction_action_from_event(%Events.TurnCompleted{}), do: :complete

  defp update_interaction_response(interaction, message) when is_binary(message) and message != "" do
    response = append_response_text(interaction.response, message)
    action = response_action(interaction.status)
    Ash.update(interaction, %{response: response}, action: action)
  end

  defp update_interaction_response(interaction, _), do: {:ok, interaction}

  # ============================================================================
  # Item Management
  # ============================================================================

  defp create_interaction_item(interaction, %Events.ItemStarted{} = event) do
    Ash.create(InteractionItem, %{
      codex_item_id: event.item_id,
      type: event.type,
      payload: event.raw_params,
      interaction_id: interaction.id
    })
  end

  defp complete_interaction_item(interaction, %Events.ItemCompleted{} = event) do
    case find_item(interaction.id, event.item_id) do
      {:ok, record} ->
        case Ash.update(record, %{payload: event.raw_params}, action: :complete) do
          {:ok, _} -> {:ok, record}
          {:error, _} -> create_interaction_item_completed(interaction, event)
        end

      {:error, :not_found} ->
        create_interaction_item_completed(interaction, event)

      {:error, _} = error ->
        error
    end
  end

  defp create_interaction_item_completed(interaction, %Events.ItemCompleted{} = event) do
    Ash.create(InteractionItem, %{
      codex_item_id: event.item_id,
      type: event.type,
      payload: event.raw_params,
      interaction_id: interaction.id
    })
  end

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

  defp maybe_update_response_from_item(interaction, %Events.ItemCompleted{type: :agent_message} = event) do
    text =
      Events.extract_text_from_content(Kernel.get_in(event.raw_params, ["item", "content"])) ||
        Kernel.get_in(event.raw_params, ["item", "message"]) ||
        Kernel.get_in(event.raw_params, ["result", "text"])

    if is_binary(text) and text != "" do
      response = append_response_text(interaction.response, text)
      action = response_action(interaction.status)
      Ash.update(interaction, %{response: response}, action: action)
    else
      {:ok, interaction}
    end
  end

  defp maybe_update_response_from_item(_interaction, _event), do: {:ok, nil}

  defp append_response_text(nil, text), do: text
  defp append_response_text("", text), do: text
  defp append_response_text(existing, text), do: existing <> "\n" <> text

  defp response_action(:complete), do: :complete
  defp response_action(_), do: :set_response

  # ============================================================================
  # Response Extraction
  # ============================================================================

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
    item.payload["item"]["text"] ||
      Events.extract_text_from_content(item.payload["item"]["content"]) ||
      item.payload["item"]["message"]
  end
end
