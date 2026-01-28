defmodule Piano.Surface do
  @moduledoc """
  Behaviour for Surface implementations.

  Surfaces are the interface between external messaging platforms
  (Telegram, LiveView, etc.) and the Piano orchestration system.
  """

  alias Piano.Core.{Surface, Interaction}

  @type event ::
          :turn_started
          | :turn_completed
          | :item_started
          | :item_completed
          | :agent_message_delta
          | :approval_required

  @type event_result :: {:ok, term()} | {:ok, :noop}

  @doc """
  Handle an event from the Codex turn.

  Events:
  - `:turn_started` - Turn has started processing
  - `:item_started` - An item (message, tool call, etc.) has started
  - `:item_completed` - An item has completed
  - `:agent_message_delta` - Streaming text delta from agent
  - `:turn_completed` - Turn has finished
  - `:approval_required` - Tool execution requires approval

  For `:approval_required`, return `{:ok, :accept}` or `{:ok, :decline}`.
  """
  @callback handle_event(Surface.t(), Interaction.t(), event(), params :: map()) :: event_result()

  @doc """
  Send a message to the surface.
  """
  @callback send_message(Surface.t(), message :: String.t()) :: :ok | {:error, term()}

  @doc """
  Send a typing indicator to the surface.
  """
  @callback send_typing(Surface.t()) :: :ok | {:error, term()}
end
