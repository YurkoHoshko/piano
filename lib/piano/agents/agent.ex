defmodule Piano.Agents.Agent do
  use Ash.Resource,
    domain: Piano.Agents,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "agents"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :description, :string do
      allow_nil? true
    end

    attribute :model, :string do
      allow_nil? false
    end

    attribute :system_prompt, :string do
      allow_nil? true
    end

    attribute :enabled_tools, {:array, :string} do
      default []
      allow_nil? false
    end

    attribute :enabled_skills, {:array, :string} do
      default []
      allow_nil? false
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :model, :system_prompt, :enabled_tools, :enabled_skills]
    end

    update :update_config do
      accept [:name, :description, :model, :system_prompt, :enabled_tools, :enabled_skills]
    end
  end
end
