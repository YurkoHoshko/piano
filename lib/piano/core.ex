defmodule Piano.Core do
  @moduledoc """
  Core domain for users, surfaces, threads, and interactions.
  """
  use Ash.Domain

  resources do
    resource Piano.Core.User
    resource Piano.Core.Surface
    resource Piano.Core.UserSurface
    resource Piano.Core.Agent
    resource Piano.Core.Thread
    resource Piano.Core.Interaction
    resource Piano.Core.InteractionItem
  end
end
