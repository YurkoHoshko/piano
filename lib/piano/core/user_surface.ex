defmodule Piano.Core.UserSurface do
  @moduledoc """
  Join table linking users to surfaces.

  Tracks which users are connected to which surfaces, with optional role.
  """
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "users_surfaces"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:owner, :member, :admin]
      default :member
      allow_nil? false
      description "User's role in this surface"
    end

    attribute :joined_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :metadata, :map do
      default %{}
      allow_nil? false
      description "Surface-specific user metadata"
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Piano.Core.User do
      allow_nil? false
    end

    belongs_to :surface, Piano.Core.Surface do
      allow_nil? false
    end
  end

  identities do
    identity :unique_user_surface, [:user_id, :surface_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:role, :metadata]
      argument :user_id, :uuid, allow_nil?: false
      argument :surface_id, :uuid, allow_nil?: false

      change manage_relationship(:user_id, :user, type: :append)
      change manage_relationship(:surface_id, :surface, type: :append)
    end

    create :link do
      accept [:role, :metadata]
      argument :user_id, :uuid, allow_nil?: false
      argument :surface_id, :uuid, allow_nil?: false

      change manage_relationship(:user_id, :user, type: :append)
      change manage_relationship(:surface_id, :surface, type: :append)

      upsert? true
      upsert_identity :unique_user_surface
    end
  end
end
