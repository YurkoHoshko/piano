defmodule Piano.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    setup_admin_token()
    log_dev_reload_status()

    children = [
      PianoWeb.Telemetry,
      Piano.Repo,
      {DNSCluster, query: Application.get_env(:piano, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Piano.PubSub},
      Piano.Codex.Client,
      Piano.Pipeline.CodexEventPipeline,
      PianoWeb.Endpoint
    ] ++ telegram_children()

    opts = [strategy: :one_for_one, name: Piano.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        log_codex_boot_info()
        schedule_codex_account_status_read()
        {:ok, pid}

      other ->
        other
    end
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
        {Piano.Telegram.BotV2, [method: :polling, token: token]}
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

  defp log_dev_reload_status do
    endpoint_config = Application.get_env(:piano, PianoWeb.Endpoint, [])
    code_reloader = Keyword.get(endpoint_config, :code_reloader, false)
    live_reload_started = match?({:ok, _}, Application.ensure_all_started(:phoenix_live_reload))

    IO.puts("""

    ═══════════════════════════════════════════════════════════════
    🔁 Dev Reload Status
    ═══════════════════════════════════════════════════════════════
    code_reloader: #{code_reloader}
    phoenix_live_reload started: #{live_reload_started}
    ═══════════════════════════════════════════════════════════════
    """)
  end

  defp log_codex_boot_info do
    # Keep this resilient: config errors should be obvious, but we don't want
    # startup logs to crash prod unless the config is truly required.
    profiles =
      try do
        Piano.Codex.Config.profile_names()
      rescue
        e ->
          Logger.error("Codex config missing/invalid: #{Exception.message(e)}")
          []
      end

    current =
      try do
        Piano.Codex.Config.current_profile!()
      rescue
        _ -> :unknown
      end

    IO.puts("""

    ═══════════════════════════════════════════════════════════════
    🧠 Codex
    ═══════════════════════════════════════════════════════════════
    current_profile: #{inspect(current)}
    profiles: #{inspect(profiles)}
    auth: (checking...)
    ═══════════════════════════════════════════════════════════════
    """)
  end

  defp schedule_codex_account_status_read do
    Task.start(fn ->
      wait_for_codex_ready(50)

      request_id = :erlang.unique_integer([:positive, :monotonic])
      :ok = Piano.Codex.RequestMap.put(request_id, %{type: :startup_account_read})
      :ok = Piano.Codex.Client.send_request("account/read", %{refreshToken: false}, request_id)
    end)
  end

  defp wait_for_codex_ready(0), do: :ok

  defp wait_for_codex_ready(attempts_left) do
    if Piano.Codex.Client.ready?() do
      :ok
    else
      Process.sleep(100)
      wait_for_codex_ready(attempts_left - 1)
    end
  end
end
