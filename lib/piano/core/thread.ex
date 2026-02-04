defmodule Piano.Core.Thread do
  @moduledoc """
  Core interaction thread resource.
  """
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

    attribute :reply_to, :string do
      allow_nil? false
      description "Surface reference like 'telegram:<chat_id>' for thread grouping"
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
      allow_nil? true
      description "The surface this thread belongs to"
    end

    has_many :interactions, Piano.Core.Interaction
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:codex_thread_id, :reply_to, :surface_id]

      argument :agent_id, :uuid, allow_nil?: true

      change manage_relationship(:agent_id, :agent, type: :append)
    end

    update :set_codex_thread_id do
      accept [:codex_thread_id]
    end

    update :archive do
      change set_attribute(:status, :archived)
    end

    read :find_recent_for_reply_to do
      argument :reply_to, :string, allow_nil?: false
      argument :since_minutes, :integer, default: 30

      prepare fn query, _context ->
        reply_to = Ash.Query.get_argument(query, :reply_to)
        since_minutes = Ash.Query.get_argument(query, :since_minutes)
        cutoff = DateTime.add(DateTime.utc_now(), -since_minutes, :minute)

        require Ash.Query

        base_reply_to = extract_base_reply_to(reply_to)

        query
        |> Ash.Query.filter(fragment("? LIKE ? || '%'", reply_to, ^base_reply_to))
        |> Ash.Query.filter(status == :active and updated_at >= ^cutoff)
        |> Ash.Query.sort(updated_at: :desc)
        |> Ash.Query.limit(1)
      end
    end
  end

  defp extract_base_reply_to("telegram:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [chat_id, _message_id] -> "telegram:#{chat_id}"
      [chat_id] -> "telegram:#{chat_id}"
    end
  end

  defp extract_base_reply_to(reply_to), do: reply_to
end
