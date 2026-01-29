defmodule Piano.Core.InteractionItem do
  @moduledoc """
  Stores individual interaction items for a Codex turn.
  """
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "interaction_items"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :codex_item_id, :string do
      allow_nil? false
    end

    attribute :type, :atom do
      constraints one_of: [
        :user_message,
        :agent_message,
        :reasoning,
        :command_execution,
        :file_change,
        :mcp_tool_call,
        :web_search
      ]
      allow_nil? false
    end

    attribute :payload, :map do
      default %{}
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [:started, :completed]
      default :started
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :interaction, Piano.Core.Interaction do
      allow_nil? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:codex_item_id, :type, :payload]

      argument :interaction_id, :uuid, allow_nil?: false
      change manage_relationship(:interaction_id, :interaction, type: :append)
    end

    update :complete do
      accept [:payload]
      change set_attribute(:status, :completed)
    end

    read :list_by_interaction do
      argument :interaction_id, :uuid, allow_nil?: false
      filter expr(interaction_id == ^arg(:interaction_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end
end
