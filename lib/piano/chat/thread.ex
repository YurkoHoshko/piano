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

    attribute :forked_from_thread_id, :uuid do
      allow_nil? true
    end

    attribute :forked_from_message_id, :uuid do
      allow_nil? true
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
    defaults [:read, :destroy]

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

    create :fork do
      argument :source_thread_id, :uuid, allow_nil?: false
      argument :fork_at_message_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        source_thread_id = Ash.Changeset.get_argument(changeset, :source_thread_id)
        fork_at_message_id = Ash.Changeset.get_argument(changeset, :fork_at_message_id)

        case Ash.get(Piano.Chat.Thread, source_thread_id) do
          {:ok, source_thread} ->
            changeset
            |> Ash.Changeset.change_attribute(:title, "Fork of #{source_thread.title || "Untitled"}")
            |> Ash.Changeset.change_attribute(:forked_from_thread_id, source_thread_id)
            |> Ash.Changeset.change_attribute(:forked_from_message_id, fork_at_message_id)

          {:error, _} ->
            Ash.Changeset.add_error(changeset, field: :source_thread_id, message: "Source thread not found")
        end
      end

      change after_action(fn changeset, new_thread, _context ->
        source_thread_id = Ash.Changeset.get_argument(changeset, :source_thread_id)
        fork_at_message_id = Ash.Changeset.get_argument(changeset, :fork_at_message_id)

        query =
          Ash.Query.for_read(Piano.Chat.Message, :list_by_thread, %{thread_id: source_thread_id})

        case Ash.read(query) do
          {:ok, messages} ->
            sorted = Enum.sort_by(messages, & &1.inserted_at, DateTime)

            fork_message = Enum.find(sorted, fn m -> m.id == fork_at_message_id end)

            messages_to_copy =
              if fork_message do
                Enum.take_while(sorted, fn m ->
                  DateTime.compare(m.inserted_at, fork_message.inserted_at) != :gt ||
                    m.id == fork_at_message_id
                end)
              else
                []
              end

            Enum.each(messages_to_copy, fn msg ->
              changeset =
                Ash.Changeset.for_create(Piano.Chat.Message, :create, %{
                  content: msg.content,
                  role: msg.role,
                  source: msg.source,
                  thread_id: new_thread.id,
                  agent_id: msg.agent_id
                })

              Ash.create!(changeset)
            end)

            {:ok, new_thread}

          {:error, error} ->
            {:error, error}
        end
      end)
    end
  end
end
