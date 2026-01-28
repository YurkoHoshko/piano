defmodule Piano.Core.Thread do
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "threads_v2"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :codex_thread_id, :string do
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
    belongs_to :agent, Piano.Core.Agent do
      allow_nil? true
    end

    belongs_to :surface, Piano.Core.Surface do
      allow_nil? false
    end

    has_many :interactions, Piano.Core.Interaction
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:codex_thread_id]

      argument :agent_id, :uuid, allow_nil?: true
      argument :surface_id, :uuid, allow_nil?: false

      change manage_relationship(:agent_id, :agent, type: :append)
      change manage_relationship(:surface_id, :surface, type: :append)
    end

    update :set_codex_thread_id do
      accept [:codex_thread_id]
    end

    update :archive do
      change set_attribute(:status, :archived)
    end

    read :find_recent_for_surface do
      argument :surface_id, :uuid, allow_nil?: false
      argument :since_minutes, :integer, default: 30

      filter expr(surface_id == ^arg(:surface_id) and status == :active)

      prepare fn query, _context ->
        since_minutes = Ash.Query.get_argument(query, :since_minutes)
        cutoff = DateTime.add(DateTime.utc_now(), -since_minutes, :minute)

        require Ash.Query

        query
        |> Ash.Query.filter(updated_at >= ^cutoff)
        |> Ash.Query.sort(updated_at: :desc)
        |> Ash.Query.limit(1)
      end
    end
  end
end
