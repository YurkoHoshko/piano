defmodule Piano.Observability do
  @moduledoc false

  require Logger

  @table :piano_observability

  def init do
    _ = ensure_table()
    :ok
  end

  def put_account_status(status) when is_map(status) do
    _ = ensure_table()
    :ets.insert(@table, {:codex_account_status, status, System.system_time(:second)})
    :ok
  end

  def account_status do
    _ = ensure_table()

    case :ets.lookup(@table, :codex_account_status) do
      [{:codex_account_status, status, updated_at_s}] -> %{status: status, updated_at_s: updated_at_s}
      _ -> %{status: :unknown, updated_at_s: nil}
    end
  end

  def boot_log do
    report = status_report()
    Logger.info(format_report(report))
    :ok
  end

  def status_text do
    status_report() |> format_report()
  end

  def status_report do
    %{
      env: Piano.Env.current(),
      app_vsn: app_vsn(),
      elixir: System.version(),
      otp_release: System.otp_release(),
      log_level: Logger.level(),
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      codex: codex_config(),
      codex_client_ready: safe_codex_ready?(),
      telegram_enabled: telegram_enabled?(),
      db_counts: db_counts(),
      account: account_status()
    }
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        @table
    end
  end

  defp app_vsn do
    case Application.spec(:piano, :vsn) do
      nil -> "unknown"
      vsn -> List.to_string(vsn)
    end
  end

  defp telegram_enabled? do
    telegram_config = Application.get_env(:piano, :telegram, [])
    telegram_config[:enabled] == true and is_binary(telegram_config[:bot_token])
  end

  defp safe_codex_ready? do
    try do
      Piano.Codex.Client.ready?()
    rescue
      _ -> false
    end
  end

  defp codex_config do
    try do
      %{
        current_profile: Piano.Codex.Config.current_profile!(),
        profiles: Piano.Codex.Config.profile_names(),
        codex_command: Piano.Codex.Config.codex_command!()
      }
    rescue
      e ->
        %{error: Exception.message(e)}
    end
  end

  defp db_counts do
    %{
      threads: count_table("threads_v2"),
      interactions: count_table("interactions"),
      interaction_items: count_table("interaction_items")
    }
  end

  defp count_table(table) when table in ["threads_v2", "interactions", "interaction_items"] do
    case Ecto.Adapters.SQL.query(Piano.Repo, "select count(*) from #{table}", []) do
      {:ok, %{rows: [[count]]}} when is_integer(count) -> count
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  defp format_report(report) when is_map(report) do
    codex =
      case report.codex do
        %{error: message} ->
          "codex=ERROR(#{message})"

        %{current_profile: current, profiles: profiles, codex_command: cmd} ->
          profiles_str =
            profiles
            |> Enum.map(&Atom.to_string/1)
            |> Enum.join(",")

          "codex=#{cmd} profile=#{current} profiles=[#{profiles_str}]"

        other ->
          "codex=#{inspect(other)}"
      end

    counts = report.db_counts

    account =
      case report.account do
        %{status: :unknown} ->
          "account=unknown"

        %{status: status, updated_at_s: ts} when is_map(status) ->
          # keep it short; avoid printing secrets
          type = status["type"] || status[:type] || "unknown"
          state = status["state"] || status[:state] || status["status"] || status[:status] || "unknown"
          "account=#{type}:#{state} updated_at=#{inspect(ts)}"

        other ->
          "account=#{inspect(other)}"
      end

    [
      "boot env=#{report.env} vsn=#{report.app_vsn} elixir=#{report.elixir} otp=#{report.otp_release} level=#{report.log_level}",
      "runtime schedulers=#{report.schedulers_online} processes=#{report.process_count}",
      "db threads=#{counts.threads} interactions=#{counts.interactions} items=#{counts.interaction_items}",
      "integrations telegram=#{report.telegram_enabled} codex_ready=#{report.codex_client_ready} #{codex}",
      account
    ]
    |> Enum.join("\n")
  end
end

