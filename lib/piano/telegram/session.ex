defmodule Piano.Telegram.Session do
  use Ash.Resource,
    domain: Piano.Telegram,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "telegram_sessions"
    repo Piano.Repo
  end

  attributes do
    attribute :chat_id, :integer do
      primary_key? true
      allow_nil? false
    end

    attribute :pending_message_id, :integer do
      allow_nil? true
    end

    attribute :thread_id, :uuid do
      allow_nil? false
    end

    attribute :agent_id, :uuid do
      allow_nil? true
    end

    timestamps()
  end

  relationships do
    belongs_to :thread, Piano.Chat.Thread do
      source_attribute :thread_id
      destination_attribute :id
      define_attribute? false
    end

    belongs_to :agent, Piano.Agents.Agent do
      source_attribute :agent_id
      destination_attribute :id
      define_attribute? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:chat_id, :thread_id, :agent_id]
    end

    update :update do
      accept [:thread_id, :agent_id, :pending_message_id]
    end

    read :by_chat_id do
      argument :chat_id, :integer, allow_nil?: false
      get? true
      filter expr(chat_id == ^arg(:chat_id))
    end
  end

  identities do
    identity :unique_chat_id, [:chat_id]
  end
end
