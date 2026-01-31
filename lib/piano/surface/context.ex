defmodule Piano.Surface.Context do
  @moduledoc """
  Context passed to surface implementations during event handling.

  This struct provides a unified interface to core constructs (Interaction, Turn, Thread)
  so that surface implementations can access the context they need regardless of
  which construct is currently being processed.

  ## Fields

  - `:interaction` - The `Piano.Core.Interaction` struct (may be nil for thread-level events)
  - `:turn_id` - The Codex turn ID (extracted from events)
  - `:thread_id` - The Codex thread ID (extracted from events)
  - `:thread` - The `Piano.Core.Thread` struct (if loaded)
  - `:event` - The parsed `Piano.Codex.Events` struct (if available)
  - `:raw_params` - The raw event parameters map

  ## Usage

  Surface implementations can pattern match on the context to access relevant info:

      def on_turn_started(surface, context, _params) do
        case context do
          %Piano.Surface.Context{interaction: %{id: id}, turn_id: turn_id} ->
            # Log the turn start
            Logger.info("Turn started", interaction_id: id, turn_id: turn_id)
        end
      end
  """

  alias Piano.Codex.Events
  alias Piano.Core.Interaction
  alias Piano.Core.Thread

  defstruct [
    :interaction,
    :turn_id,
    :thread_id,
    :thread,
    :event,
    :raw_params
  ]

  @type t :: %__MODULE__{
          interaction: Interaction.t() | nil,
          turn_id: String.t() | nil,
          thread_id: String.t() | nil,
          thread: Thread.t() | nil,
          event: Events.event() | nil,
          raw_params: map()
        }

  @doc """
  Creates a new context from an interaction and event parameters.

  ## Parameters

  - `interaction` - The Core.Interaction struct (may be nil)
  - `params` - The raw event parameters map
  - `opts` - Options including:
    - `:event` - Pre-parsed Events struct
    - `:thread` - Pre-loaded Thread struct

  ## Examples

      context = Piano.Surface.Context.new(interaction, params,
        event: parsed_event,
        thread: loaded_thread
      )
  """
  @spec new(Interaction.t() | nil, map(), keyword()) :: t()
  def new(interaction, params, opts \\ []) do
    event = opts[:event]

    %__MODULE__{
      interaction: interaction,
      turn_id: extract_turn_id(event, params),
      thread_id: extract_thread_id(event, params, interaction),
      thread: opts[:thread],
      event: event,
      raw_params: params
    }
  end

  @doc """
  Creates a context from an event with no associated interaction.
  Useful for thread-level or broadcast events.
  """
  @spec from_event(Events.event()) :: t()
  def from_event(event) when is_struct(event) do
    %__MODULE__{
      interaction: nil,
      turn_id: event_turn_id(event),
      thread_id: event_thread_id(event),
      thread: nil,
      event: event,
      raw_params: event.raw_params
    }
  end

  @doc """
  Returns true if the context has an associated interaction.
  """
  @spec has_interaction?(t()) :: boolean()
  def has_interaction?(%__MODULE__{interaction: nil}), do: false
  def has_interaction?(%__MODULE__{}), do: true

  @doc """
  Returns true if the context has an associated thread.
  """
  @spec has_thread?(t()) :: boolean()
  def has_thread?(%__MODULE__{thread: nil}), do: false
  def has_thread?(%__MODULE__{}), do: true

  @doc """
  Returns the interaction ID if available.
  """
  @spec interaction_id(t()) :: String.t() | nil
  def interaction_id(%__MODULE__{interaction: %{id: id}}), do: id
  def interaction_id(%__MODULE__{}), do: nil

  @doc """
  Returns the thread database ID if available.
  """
  @spec thread_db_id(t()) :: String.t() | nil
  def thread_db_id(%__MODULE__{thread: %{id: id}}), do: id
  def thread_db_id(%__MODULE__{interaction: %{thread_id: id}}), do: id
  def thread_db_id(%__MODULE__{}), do: nil

  @doc """
  Returns the reply_to identifier from the interaction or thread.
  """
  @spec reply_to(t()) :: String.t() | nil
  def reply_to(%__MODULE__{interaction: %{reply_to: reply_to}}), do: reply_to
  def reply_to(%__MODULE__{thread: %{reply_to: reply_to}}), do: reply_to
  def reply_to(%__MODULE__{}), do: nil

  # Private helpers

  defp extract_turn_id(nil, params) do
    Events.extract_turn_id(params)
  end

  defp extract_turn_id(event, _params) do
    event_turn_id(event)
  end

  defp extract_thread_id(nil, params, interaction) do
    Events.extract_thread_id(params) ||
      (interaction && interaction.thread && interaction.thread.codex_thread_id)
  end

  defp extract_thread_id(event, _params, _interaction) do
    event_thread_id(event)
  end

  # Extract turn_id from event structs
  defp event_turn_id(%Events.TurnStarted{turn_id: id}), do: id
  defp event_turn_id(%Events.TurnCompleted{turn_id: id}), do: id
  defp event_turn_id(%Events.TurnDiffUpdated{turn_id: id}), do: id
  defp event_turn_id(%Events.TurnPlanUpdated{turn_id: id}), do: id
  defp event_turn_id(%Events.ItemStarted{turn_id: id}), do: id
  defp event_turn_id(%Events.ItemCompleted{turn_id: id}), do: id
  defp event_turn_id(%Events.AgentMessageDelta{turn_id: id}), do: id
  defp event_turn_id(%Events.ReasoningDelta{turn_id: id}), do: id
  defp event_turn_id(%Events.CommandOutputDelta{turn_id: id}), do: id
  defp event_turn_id(%Events.FileChangeOutputDelta{turn_id: id}), do: id
  defp event_turn_id(%Events.CommandExecutionRequestApproval{turn_id: id}), do: id
  defp event_turn_id(%Events.FileChangeRequestApproval{turn_id: id}), do: id
  defp event_turn_id(%Events.ApplyPatchApproval{turn_id: id}), do: id
  defp event_turn_id(%Events.McpToolCallProgress{turn_id: id}), do: id
  defp event_turn_id(_), do: nil

  # Extract thread_id from event structs
  defp event_thread_id(%Events.TurnStarted{thread_id: id}), do: id
  defp event_thread_id(%Events.TurnCompleted{thread_id: id}), do: id
  defp event_thread_id(%Events.TurnDiffUpdated{thread_id: id}), do: id
  defp event_thread_id(%Events.TurnPlanUpdated{thread_id: id}), do: id
  defp event_thread_id(%Events.ItemStarted{thread_id: id}), do: id
  defp event_thread_id(%Events.ItemCompleted{thread_id: id}), do: id
  defp event_thread_id(%Events.ThreadStarted{thread_id: id}), do: id
  defp event_thread_id(%Events.ThreadArchived{thread_id: id}), do: id
  defp event_thread_id(%Events.ThreadTokenUsageUpdated{thread_id: id}), do: id
  defp event_thread_id(%Events.CommandExecutionRequestApproval{thread_id: id}), do: id
  defp event_thread_id(%Events.FileChangeRequestApproval{thread_id: id}), do: id
  defp event_thread_id(%Events.ApplyPatchApproval{thread_id: id}), do: id
  defp event_thread_id(_), do: nil
end
