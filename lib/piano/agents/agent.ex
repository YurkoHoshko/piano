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

    attribute :soul, :string do
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
      accept [:name, :description, :model, :system_prompt, :soul, :enabled_tools, :enabled_skills]
    end

    read :list do
      prepare build(sort: [inserted_at: :asc])
    end

    update :update_config do
      accept [:name, :description, :model, :system_prompt, :soul, :enabled_tools, :enabled_skills]
    end

    update :append_soul do
      require_atomic? false
      accept [:soul]

      change fn changeset, _context ->
        incoming = Ash.Changeset.get_attribute(changeset, :soul) || ""
        current = changeset.data.soul || ""
        separator = if current == "" or incoming == "", do: "", else: "\n"
        Ash.Changeset.force_change_attribute(changeset, :soul, current <> separator <> incoming)
      end
    end

    update :edit_soul do
      accept [:soul]
    end

    update :rewrite_soul do
      accept [:soul]
    end
  end
end
