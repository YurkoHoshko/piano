defmodule Piano.Repo.Migrations.AddSoulToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :soul, :text
    end
  end
end
