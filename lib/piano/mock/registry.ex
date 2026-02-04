defmodule Piano.Mock.Registry do
  @moduledoc """
  Registry for mock surface agents.
  """

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end
