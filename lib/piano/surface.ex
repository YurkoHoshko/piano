defprotocol Piano.Surface do
  @moduledoc """
  Protocol for Surface implementations.

  Surfaces are the interface between external messaging platforms
  (Telegram, LiveView, etc.) and the Piano orchestration system.

  ## Lifecycle Callbacks

  These callbacks are invoked during interaction processing:
  - `on_turn_started/3` - Called when a Codex turn begins
  - `on_turn_completed/3` - Called when a Codex turn finishes
  - `on_item_started/3` - Called when an item (message, tool call, etc.) starts
  - `on_item_completed/3` - Called when an item completes
  - `on_agent_message_delta/3` - Called for streaming agent message updates
  - `on_approval_required/3` - Called when user approval is needed

  ## Thread Operations

  - `send_thread_transcript/2` - Sends a formatted thread transcript to the surface
  """
  @fallback_to_any true

  alias Piano.Core.Interaction

  @doc """
  Called when a Codex turn starts processing.
  """
  @spec on_turn_started(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_turn_started(surface, interaction, params)

  @doc """
  Called when a Codex turn completes.
  """
  @spec on_turn_completed(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_turn_completed(surface, interaction, params)

  @doc """
  Called when an item (message, tool call, file change, etc.) starts.
  """
  @spec on_item_started(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_item_started(surface, interaction, params)

  @doc """
  Called when an item completes.
  """
  @spec on_item_completed(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_item_completed(surface, interaction, params)

  @doc """
  Called for streaming agent message updates (deltas).
  """
  @spec on_agent_message_delta(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_agent_message_delta(surface, interaction, params)

  @doc """
  Called when user approval is required for a tool call or file change.
  """
  @spec on_approval_required(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_approval_required(surface, interaction, params)

  @doc """
  Send a thread transcript to the surface.

  The `thread_data` map contains the raw Codex `thread/read` response with:
  - `"thread"` - Thread metadata (id, etc.)
  - `"turns"` - List of turns, each containing items

  Implementations should format the transcript appropriately for their platform
  (e.g., Telegram may send as a file if too long).
  """
  @spec send_thread_transcript(t(), map()) :: {:ok, term()} | {:error, term()}
  def send_thread_transcript(surface, thread_data)
end

defimpl Piano.Surface, for: Any do
  @moduledoc false

  def on_turn_started(_surface, _interaction, _params), do: {:ok, :noop}
  def on_turn_completed(_surface, _interaction, _params), do: {:ok, :noop}
  def on_item_started(_surface, _interaction, _params), do: {:ok, :noop}
  def on_item_completed(_surface, _interaction, _params), do: {:ok, :noop}
  def on_agent_message_delta(_surface, _interaction, _params), do: {:ok, :noop}
  def on_approval_required(_surface, _interaction, _params), do: {:ok, :noop}
  def send_thread_transcript(_surface, _thread_data), do: {:ok, :noop}
end
