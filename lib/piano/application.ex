defmodule Piano.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_admin_token()

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

  defp setup_admin_token do
    token =
      :crypto.strong_rand_bytes(16)
      |> Base.url_encode64(padding: false)

    Application.put_env(:piano, :admin_token, token)

    IO.puts("""

    ═══════════════════════════════════════════════════════════════
    🔐 Admin Token Generated
    ═══════════════════════════════════════════════════════════════
    Access admin dashboard at: /admin/agents?token=#{token}
    ═══════════════════════════════════════════════════════════════
    """)
  end
end
