defmodule Piano.DataCase do
  @moduledoc """
  Test helpers for database-backed tests.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Piano.Repo
      import Piano.DataCase
    end
  end

  setup tags do
    Piano.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(_tags) do
    Piano.Repo.query!("DELETE FROM interaction_items")
    Piano.Repo.query!("DELETE FROM interactions")
    Piano.Repo.query!("DELETE FROM threads_v2")
    Piano.Repo.query!("DELETE FROM users_surfaces")
    Piano.Repo.query!("DELETE FROM users")
    Piano.Repo.query!("DELETE FROM surfaces")
    Piano.Repo.query!("DELETE FROM agents_v2")
    :ok
  end
end
