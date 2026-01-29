defmodule Piano.Agents do
  @moduledoc """
  Agents domain resources and helpers.
  """
  use Ash.Domain

  resources do
    resource Piano.Agents.Agent
  end
end
