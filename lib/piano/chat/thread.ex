defmodule Piano.Chat.Thread do
  use Ash.Resource,
    domain: Piano.Chat,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "threads"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :archived]
      default :active
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    has_many :messages, Piano.Chat.Message

    belongs_to :primary_agent, Piano.Agents.Agent do
      allow_nil? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title]

      argument :primary_agent_id, :uuid, allow_nil?: true
      change manage_relationship(:primary_agent_id, :primary_agent, type: :append)
    end

    read :list do
      prepare build(sort: [inserted_at: :desc])
    end

    update :archive do
      change set_attribute(:status, :archived)
    end
  end
end
