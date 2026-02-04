defmodule Piano.Core.User do
  @moduledoc """
  User resource representing a Piano user.

  Users are identified across surfaces and can have multiple surface connections.
  """
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "users"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :display_name, :string do
      allow_nil? true
      description "User's display name (may come from surface)"
    end

    attribute :username, :string do
      allow_nil? true
      description "Username (e.g., Telegram username)"
    end

    attribute :metadata, :map do
      default %{}
      allow_nil? false
      description "Additional user metadata from surfaces"
    end

    timestamps()
  end

  relationships do
    has_many :user_surfaces, Piano.Core.UserSurface

    many_to_many :surfaces, Piano.Core.Surface do
      through Piano.Core.UserSurface
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:display_name, :username, :metadata]
    end

    update :update do
      accept [:display_name, :username, :metadata]
    end

    read :by_username do
      argument :username, :string, allow_nil?: false
      filter expr(username == ^arg(:username))
      get? true
    end
  end
end
