defprotocol Piano.Surface do
  @moduledoc """
  Protocol for Surface implementations.

  Surfaces are the interface between external messaging platforms
  (Telegram, LiveView, etc.) and the Piano orchestration system.
  """
  @fallback_to_any true

  alias Piano.Core.Interaction

  @spec on_turn_started(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_turn_started(surface, interaction, params)

  @spec on_turn_completed(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_turn_completed(surface, interaction, params)

  @spec on_item_started(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_item_started(surface, interaction, params)

  @spec on_item_completed(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_item_completed(surface, interaction, params)

  @spec on_agent_message_delta(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_agent_message_delta(surface, interaction, params)

  @spec on_approval_required(t(), Interaction.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_approval_required(surface, interaction, params)
end

defimpl Piano.Surface, for: Any do
  @moduledoc false

  def on_turn_started(_surface, _interaction, _params), do: {:ok, :noop}
  def on_turn_completed(_surface, _interaction, _params), do: {:ok, :noop}
  def on_item_started(_surface, _interaction, _params), do: {:ok, :noop}
  def on_item_completed(_surface, _interaction, _params), do: {:ok, :noop}
  def on_agent_message_delta(_surface, _interaction, _params), do: {:ok, :noop}
  def on_approval_required(_surface, _interaction, _params), do: {:ok, :noop}
end
