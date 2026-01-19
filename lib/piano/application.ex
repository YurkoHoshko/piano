defmodule Piano.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PianoWeb.Telemetry,
      Piano.Repo,
      {DNSCluster, query: Application.get_env(:piano, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Piano.PubSub},
      Piano.Pipeline.MessageProducer,
      Piano.Pipeline.AgentConsumer,
      PianoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Piano.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PianoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
