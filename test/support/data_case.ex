defmodule Piano.DataCase do
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
    Piano.Repo.query!("DELETE FROM messages")
    Piano.Repo.query!("DELETE FROM threads")
    Piano.Repo.query!("DELETE FROM agents")
    :ok
  end
end
