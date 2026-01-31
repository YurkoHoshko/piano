defmodule Piano.Env do
  @moduledoc false

  @spec current() :: :dev | :test | :prod
  def current do
    cond do
      Application.get_env(:piano, :test_routes, false) -> :test
      Application.get_env(:piano, :dev_routes, false) -> :dev
      true -> :prod
    end
  end

  @spec dev?() :: boolean()
  def dev?, do: current() == :dev
end
