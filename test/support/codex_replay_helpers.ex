defmodule Piano.TestHarness.CodexReplayHelpers do
  @moduledoc false

  def start_endpoint! do
    endpoint = PianoWeb.Endpoint

    config = Application.get_env(:piano, endpoint, [])
    Application.put_env(:piano, endpoint, Keyword.put(config, :server, true))

    case Process.whereis(endpoint) do
      nil ->
        start_supervised_endpoint(endpoint)

      _pid ->
        restart_supervised_endpoint(endpoint)
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

  defp start_supervised_endpoint(endpoint) do
    case Process.whereis(Piano.Supervisor) do
      nil ->
        case endpoint.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> raise "Failed to start #{inspect(endpoint)}: #{inspect(reason)}"
        end

      _pid ->
        case Supervisor.start_child(Piano.Supervisor, endpoint.child_spec([])) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> raise "Failed to start #{inspect(endpoint)}: #{inspect(reason)}"
        end
    end
  end

  defp restart_supervised_endpoint(endpoint) do
    case Process.whereis(Piano.Supervisor) do
      nil ->
        case endpoint.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> raise "Failed to start #{inspect(endpoint)}: #{inspect(reason)}"
        end

      _pid ->
        case Supervisor.terminate_child(Piano.Supervisor, endpoint) do
          :ok -> :ok
          {:error, :not_found} -> :ok
          {:error, reason} -> raise "Failed to stop #{inspect(endpoint)}: #{inspect(reason)}"
        end

        case Supervisor.restart_child(Piano.Supervisor, endpoint) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> raise "Failed to restart #{inspect(endpoint)}: #{inspect(reason)}"
        end
    end
  end
end
