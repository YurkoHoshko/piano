defmodule Piano.TestHarness.CodexReplayHelpers do
  @moduledoc false

  def start_endpoint! do
    endpoint = PianoWeb.Endpoint

    config = Application.get_env(:piano, endpoint, [])
    Application.put_env(:piano, endpoint, Keyword.put(config, :server, true))

    case Process.whereis(endpoint) do
      nil ->
        _ = endpoint.start_link()

      pid ->
        # Ensure the HTTP server starts by restarting the endpoint with server: true.
        Supervisor.stop(pid)
        _ = endpoint.start_link()
    end

    :ok
  end

  def base_url do
    http =
      case Application.get_env(:piano, PianoWeb.Endpoint, []) do
        list when is_list(list) -> Keyword.get(list, :http, [])
        _ -> []
      end

    port = Keyword.get(http, :port, 4002)
    "http://127.0.0.1:#{port}/v1"
  end

  def with_replay_paths(paths, fun) when is_list(paths) do
    original = Application.get_env(:piano, :codex_replay_paths)
    Application.put_env(:piano, :codex_replay_paths, paths)

    try do
      fun.()
    after
      Application.put_env(:piano, :codex_replay_paths, original)
    end
  end
end
