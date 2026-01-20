defmodule Piano.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_admin_token()

    children =
      [
        PianoWeb.Telemetry,
        Piano.Repo,
        {DNSCluster, query: Application.get_env(:piano, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Piano.PubSub},
        Piano.Pipeline.MessageProducer,
        Piano.Pipeline.AgentConsumer,
        PianoWeb.Endpoint
      ] ++ telegram_children()

    opts = [strategy: :one_for_one, name: Piano.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp telegram_children do
    telegram_config = Application.get_env(:piano, :telegram, [])

    if telegram_config[:enabled] && telegram_config[:bot_token] do
      token = telegram_config[:bot_token]

      IO.puts("""

      ═══════════════════════════════════════════════════════════════
      🤖 Telegram Bot Starting
      ═══════════════════════════════════════════════════════════════
      Bot is configured and will start polling for updates.
      ═══════════════════════════════════════════════════════════════
      """)

      [
        ExGram,
        {Piano.Telegram.Bot, [method: :polling, token: token]}
      ]
    else
      IO.puts("""

      ═══════════════════════════════════════════════════════════════
      ℹ️  Telegram Bot Disabled
      ═══════════════════════════════════════════════════════════════
      Set TELEGRAM_BOT_TOKEN environment variable to enable.
      ═══════════════════════════════════════════════════════════════
      """)

      []
    end
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
