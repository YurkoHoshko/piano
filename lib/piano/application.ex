defmodule Piano.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    setup_admin_token()
    Piano.Observability.init()

    if Piano.Env.dev?() do
      log_dev_reload_status()
    end

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
        Piano.Observability.boot_log()
        schedule_codex_account_status_read()
        schedule_codex_config_read()
        {:ok, pid}

      other ->
        other
    end
  end

  defp telegram_children do
    telegram_config = Application.get_env(:piano, :telegram, [])

    if telegram_config[:enabled] && telegram_config[:bot_token] do
      token = telegram_config[:bot_token]

      Logger.info("Telegram bot enabled (polling)")

      [
        Piano.Telegram.ContextWindow,
        ExGram,
        {Piano.Telegram.BotV2, [method: :polling, token: token]}
      ]
    else
      Logger.info("Telegram bot disabled (set TELEGRAM_BOT_TOKEN to enable)")

      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    PianoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp setup_admin_token do
    configured = System.get_env("PIANO_ADMIN_TOKEN") || Application.get_env(:piano, :admin_token)

    token =
      if is_binary(configured) and configured != "" and configured != "piano_admin" do
        configured
      else
        :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
      end

    Application.put_env(:piano, :admin_token, token)

    if Piano.Env.dev?() do
      Logger.info("Admin dashboard token set: /admin/agents?token=#{token}")
    else
      if configured in [nil, "", "piano_admin"] do
        Logger.warning("Admin token was not configured; generated ephemeral token for this boot")
      end

      Logger.info("Admin dashboard token configured")
    end
  end

  defp log_dev_reload_status do
    endpoint_config = Application.get_env(:piano, PianoWeb.Endpoint, [])
    code_reloader = Keyword.get(endpoint_config, :code_reloader, false)
    live_reload_started = match?({:ok, _}, Application.ensure_all_started(:phoenix_live_reload))

    Logger.info(
      "Dev reload status code_reloader=#{code_reloader} phoenix_live_reload=#{live_reload_started}"
    )
  end

  defp schedule_codex_account_status_read do
    Task.start(fn ->
      wait_for_codex_ready(50)

      request_id = :erlang.unique_integer([:positive, :monotonic])
      :ok = Piano.Codex.RequestMap.put(request_id, %{type: :startup_account_read})
      :ok = Piano.Codex.Client.send_request("account/read", %{refreshToken: false}, request_id)
    end)
  end

  defp schedule_codex_config_read do
    Task.start(fn ->
      wait_for_codex_ready(50)
      _ = Piano.Codex.read_config()
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
