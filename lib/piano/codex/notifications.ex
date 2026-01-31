defmodule Piano.Codex.Notifications do
  @moduledoc """
  Handles notifications to surfaces for Codex events.

  Provides a unified interface for notifying surfaces about events during
  interaction processing.
  """

  require Logger

  alias Piano.Codex.Events
  alias Piano.Core.Interaction
  alias Piano.Surface.Context

  @doc """
  Notify surfaces about an event.

  Takes an interaction and event, builds the appropriate context,
  and routes to the appropriate surface protocol callback.
  """
  @spec notify(Interaction.t() | nil, Events.event()) :: :ok
  def notify(nil, _event), do: :ok

  def notify(interaction, event) when is_struct(event) do
    context = Context.new(interaction, event.raw_params, event: event)

    with {:ok, surface} <- build_surface(interaction.reply_to),
         {:ok, callback} <- event_to_callback(event) do
      apply(Piano.Surface, callback, [surface, context, event.raw_params])
    end

    :ok
  rescue
    e ->
      Logger.error("Surface notification error for #{event.__struct__}: #{inspect(e)}")
      :ok
  end

  def notify(_interaction, _event), do: :ok

  # Map event structs to Surface protocol callback functions
  defp event_to_callback(event) do
    case event do
      %Events.TurnStarted{} -> {:ok, :on_turn_started}
      %Events.TurnCompleted{} -> {:ok, :on_turn_completed}
      %Events.ItemStarted{} -> {:ok, :on_item_started}
      %Events.ItemCompleted{} -> {:ok, :on_item_completed}
      %Events.AgentMessageDelta{} -> {:ok, :on_agent_message_delta}
      _ -> {:error, {:unsupported_event, event.__struct__}}
    end
  end

  @doc """
  Log an event for debugging/observability.
  """
  @spec log_event(Events.event(), Interaction.t() | nil) :: :ok
  def log_event(event, interaction) when is_struct(event) do
    case event do
      %Events.TurnStarted{} ->
        Logger.info(
          "Codex turn started",
          interaction_id: interaction && interaction.id,
          thread_id: interaction && interaction.thread_id,
          codex_thread_id: event.thread_id,
          turn_id: event.turn_id
        )

      %Events.TurnCompleted{} ->
        usage = event.usage || %{input_tokens: nil, output_tokens: nil, total_tokens: nil}

        status_str =
          case event.status do
            :completed -> "completed"
            :failed -> "failed"
            :interrupted -> "interrupted"
            _ -> "unknown"
          end

        item_count = length(event.items || [])

        metadata = [
          interaction_id: interaction && interaction.id,
          thread_id: interaction && interaction.thread_id,
          codex_thread_id: event.thread_id,
          turn_id: event.turn_id
        ]

        message = "Codex turn completed status=#{status_str} items=#{item_count} input_tokens=#{usage.input_tokens || "n/a"} output_tokens=#{usage.output_tokens || "n/a"}"

        if event.error do
          Logger.error("#{message} error=#{inspect(event.error)}", metadata)
        else
          Logger.info(message, metadata)
        end

      %Events.ThreadStarted{thread_id: thread_id} ->
        Logger.info("Codex thread started", codex_thread_id: thread_id)

      %Events.ThreadArchived{thread_id: thread_id} ->
        Logger.info("Codex thread archived", codex_thread_id: thread_id)

      _ ->
        :ok
    end
  end

  @doc """
  Log when an event cannot be mapped to an interaction.
  """
  @spec log_unmapped(Events.event(), term()) :: :ok
  def log_unmapped(event, error) when is_struct(event) do
    event_type = event.__struct__ |> Module.split() |> List.last()

    if event_type in ["TurnStarted", "TurnCompleted", "ItemStarted", "ItemCompleted"] do
      Logger.warning("Codex event ignored (unmapped #{event_type}) error=#{inspect(error)}")
    else
      Logger.debug("Codex event ignored (#{event_type}): #{inspect(error)}")
    end
  end

  def log_unmapped(_event, _error), do: :ok

  defp build_surface("telegram:" <> _ = reply_to) do
    Piano.Telegram.Surface.parse(reply_to)
  end

  defp build_surface(_), do: :error
end
