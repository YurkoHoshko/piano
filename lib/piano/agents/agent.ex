defmodule Piano.Agents.Agent do
  @moduledoc """
  Agent configuration resource for LLM behavior.
  """
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

    attribute :max_iterations, :integer do
      default 5
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    has_many :messages, Piano.Chat.Message
    has_many :telegram_sessions, Piano.Telegram.Session
  end

  actions do
    defaults [:read]

    destroy :destroy do
      primary? true
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          import Ecto.Query
          agent_id = changeset.data.id

          Piano.Repo.delete_all(from(m in "messages", where: m.agent_id == ^agent_id))
          Piano.Repo.delete_all(from(s in "telegram_sessions", where: s.agent_id == ^agent_id))

          changeset
        end)
      end
    end

    create :create do
      accept [
        :name,
        :description,
        :model,
        :system_prompt,
        :soul,
        :enabled_tools,
        :enabled_skills,
        :max_iterations
      ]
    end

    read :list do
      prepare build(sort: [inserted_at: :asc])
    end

    update :update_config do
      accept [
        :name,
        :description,
        :model,
        :system_prompt,
        :soul,
        :enabled_tools,
        :enabled_skills,
        :max_iterations
      ]
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
