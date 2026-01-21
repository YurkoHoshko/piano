defmodule Piano.Repo.Migrations.AddMaxIterationsToAgents do
  use Ecto.Migration

  def up do
    alter table(:agents) do
      add :max_iterations, :integer, null: false, default: 5
    end
  end

  def down do
    alter table(:agents) do
      remove :max_iterations
    end
  end
end
