defmodule Piano.Core do
  @moduledoc """
  Core domain for surfaces, threads, and interactions.
  """
  use Ash.Domain

  resources do
    resource Piano.Core.Surface
    resource Piano.Core.Agent
    resource Piano.Core.Thread
    resource Piano.Core.Interaction
    resource Piano.Core.InteractionItem
  end
end
