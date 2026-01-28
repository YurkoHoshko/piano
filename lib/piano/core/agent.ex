defmodule Piano.Core.Agent do
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "agents_v2"
    repo Piano.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :model, :string do
      allow_nil? false
      default "o3"
    end

    attribute :workspace_path, :string do
      allow_nil? false
    end

    attribute :sandbox_policy, :atom do
      constraints one_of: [:read_only, :workspace_write, :full_access]
      default :workspace_write
      allow_nil? false
    end

    attribute :auto_approve_policy, :atom do
      constraints one_of: [:none, :safe, :all]
      default :none
      allow_nil? false
    end

    attribute :is_default, :boolean do
      default false
      allow_nil? false
    end

    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :model, :workspace_path, :sandbox_policy, :auto_approve_policy, :is_default]
    end

    update :update do
      accept [:name, :model, :workspace_path, :sandbox_policy, :auto_approve_policy, :is_default]
    end

    read :list do
      prepare build(sort: [inserted_at: :asc])
    end

    read :get_default do
      filter expr(is_default == true)
      get? true
    end
  end
end
