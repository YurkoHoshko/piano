defmodule Piano.Chat.Message do
  use Ash.Resource,
    domain: Piano.Chat,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "messages"
    repo Piano.Repo

    references do
      reference :thread, on_delete: :delete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :content, :string do
      allow_nil? false
    end

    attribute :role, :atom do
      constraints one_of: [:user, :agent]
      allow_nil? false
    end

    attribute :source, :atom do
      constraints one_of: [:web, :telegram]
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :thread, Piano.Chat.Thread do
      allow_nil? false
    end

    belongs_to :agent, Piano.Agents.Agent do
      allow_nil? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:content, :role, :source]

      argument :thread_id, :uuid, allow_nil?: false
      argument :agent_id, :uuid, allow_nil?: true

      change manage_relationship(:thread_id, :thread, type: :append)
      change manage_relationship(:agent_id, :agent, type: :append)
    end

    read :list_by_thread do
      argument :thread_id, :uuid, allow_nil?: false

      filter expr(thread_id == ^arg(:thread_id))
    end
  end
end
