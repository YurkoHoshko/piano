defmodule Piano.Core.Interaction do
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "interactions"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :codex_turn_id, :string do
      allow_nil? true
    end

    attribute :original_message, :string do
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :in_progress, :complete, :interrupted, :failed]
      default :pending
      allow_nil? false
    end

    attribute :response, :string do
      allow_nil? true
    end

    timestamps()
  end

  relationships do
    belongs_to :thread, Piano.Core.Thread do
      allow_nil? true
    end

    belongs_to :surface, Piano.Core.Surface do
      allow_nil? false
    end

    has_many :items, Piano.Core.InteractionItem
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:original_message]

      argument :surface_id, :uuid, allow_nil?: false
      argument :thread_id, :uuid, allow_nil?: true

      change manage_relationship(:surface_id, :surface, type: :append)
      change manage_relationship(:thread_id, :thread, type: :append)
    end

    update :assign_thread do
      require_atomic? false
      argument :thread_id, :uuid, allow_nil?: false
      change manage_relationship(:thread_id, :thread, type: :append)
    end

    update :start do
      accept [:codex_turn_id]
      change set_attribute(:status, :in_progress)
    end

    update :complete do
      accept [:response]
      change set_attribute(:status, :complete)
    end

    update :fail do
      accept [:response]
      change set_attribute(:status, :failed)
    end

    update :interrupt do
      change set_attribute(:status, :interrupted)
    end
  end
end
