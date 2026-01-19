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
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title]
    end

    update :archive do
      change set_attribute(:status, :archived)
    end
  end
end
