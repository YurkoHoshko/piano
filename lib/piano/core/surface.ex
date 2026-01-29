defmodule Piano.Core.Surface do
  @moduledoc """
  Core surface resource for external integrations.
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
      constraints one_of: [:telegram, :liveview]
      allow_nil? false
    end

    attribute :identifier, :string do
      allow_nil? false
    end

    attribute :config, :map do
      default %{}
      allow_nil? false
    end

    timestamps()
  end

  identities do
    identity :unique_app_identifier, [:app, :identifier]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:app, :identifier, :config]
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
