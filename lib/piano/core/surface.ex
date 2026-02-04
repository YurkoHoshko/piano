defmodule Piano.Core.Surface do
  @moduledoc """
  Core surface resource for external integrations.

  Surfaces represent connection points like Telegram chats, LiveView sessions,
  or mock agents. They can be single-user (DM) or multi-user (group chats).
  """
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "surfaces"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :app, :atom do
      constraints one_of: [:telegram, :liveview, :mock]
      allow_nil? false
      description "Surface type"
    end

    attribute :identifier, :string do
      allow_nil? false
      description "Provider-specific identifier (e.g., telegram chat_id, mock agent ID)"
    end

    attribute :single_user?, :boolean do
      default true
      allow_nil? false
      description "Whether this is a single-user surface (DM) or multi-user (group)"
    end

    attribute :config, :map do
      default %{}
      allow_nil? false
      description "Surface-specific configuration"
    end

    timestamps()
  end

  relationships do
    has_many :user_surfaces, Piano.Core.UserSurface

    many_to_many :users, Piano.Core.User do
      through Piano.Core.UserSurface
    end

    has_many :threads, Piano.Core.Thread
  end

  identities do
    identity :unique_app_identifier, [:app, :identifier]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:app, :identifier, :single_user?, :config]
      upsert? true
      upsert_identity :unique_app_identifier
    end

    create :find_or_create do
      accept [:app, :identifier, :single_user?, :config]
      upsert? true
      upsert_identity :unique_app_identifier
    end

    read :get_by_app_and_identifier do
      argument :app, :atom, allow_nil?: false
      argument :identifier, :string, allow_nil?: false

      filter expr(app == ^arg(:app) and identifier == ^arg(:identifier))

      get? true
    end
  end
end
