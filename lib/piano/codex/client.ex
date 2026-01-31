defmodule Piano.Codex.Client do
  @moduledoc """
  GenServer wrapping the `codex app-server` process.

  Communicates via JSON-RPC 2.0 over stdio (JSONL).
  This client is a thin wrapper that forwards all inbound messages
  into the Codex event pipeline.
  """
  use GenServer

  require Logger
  alias Piano.Pipeline.CodexEventProducer
  alias Piano.Codex.RequestMap
  alias Piano.Core.Interaction
  alias Piano.Codex.Config
  import Ash.Expr, only: [expr: 1]
  require Ash.Query
  require Piano.Surface

  defstruct [
    :port,
    :buffer,
    :initialized,
    :initialize_id
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Restart the supervised Codex client (and its underlying `codex app-server` process).
  """
  def restart do
    sup = Piano.Supervisor

    if is_pid(Process.whereis(sup)) do
      _ = Supervisor.terminate_child(sup, __MODULE__)

      case Supervisor.restart_child(sup, __MODULE__) do
        {:ok, _pid} -> :ok
        {:ok, _pid, _info} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :supervisor_not_running}
    end
  end

  @doc """
  Send a JSON-RPC request (response is delivered via the event pipeline).
  """
  def send_request(client \\ __MODULE__, method, params, id) when not is_nil(id) do
    GenServer.cast(client, {:send, %{id: id, method: method, params: params}})
  end

  @doc """
  Send a JSON-RPC notification (no response expected).
  """
  def notify(client \\ __MODULE__, method, params) do
    GenServer.cast(client, {:send, %{method: method, params: params}})
  end

  @doc """
  Check if client is initialized and ready.
  """
  def ready?(client \\ __MODULE__) do
    GenServer.call(client, :ready?)
  end

  @doc """
  Stop the client gracefully.
  """
  def stop(client \\ __MODULE__) do
    GenServer.stop(client, :normal)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    codex_command = Keyword.get(opts, :codex_command, Config.codex_command!())
    codex_args = Keyword.get(opts, :codex_args, Config.codex_args!())
    env_overrides = Keyword.get(opts, :env, [])
    auto_initialize = Keyword.get(opts, :auto_initialize, true)
    initialize_id = Keyword.get(opts, :initialize_id, 1)

    Logger.info("Starting Codex: #{codex_command} #{Enum.join(codex_args, " ")}")

    env = build_port_env(env_overrides)
    codex_cwd = codex_cwd_from_env(env)

    Logger.info(
      "Codex environment codex_home=#{inspect(env_value(env, "CODEX_HOME"))} openai_base_url=#{inspect(env_value(env, "OPENAI_BASE_URL"))} openai_api_key?=#{env_value(env, "OPENAI_API_KEY") != nil}"
    )
    Logger.info("Codex cwd #{codex_cwd}")

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      {:line, 1_000_000},
      {:env, env},
      {:cd, String.to_charlist(codex_cwd)}
    ]

    port = Port.open({:spawn_executable, find_executable(codex_command)}, [
      {:args, codex_args} | port_opts
    ])

    state = %__MODULE__{
      port: port,
      buffer: "",
      initialized: false,
      initialize_id: initialize_id
    }

    if auto_initialize do
      send(self(), :do_initialize)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_cast({:send, message}, state) do
    log_outbound(message)
    send_json(state.port, message)
    {:noreply, state}
  end

  @impl true
  def handle_info(:do_initialize, state) do
    request = %{
      id: state.initialize_id,
      method: "initialize",
      params: %{
        clientInfo: %{
          name: "piano",
          version: "2.0.0"
        },
        capabilities: %{}
      }
    }

    send_json(state.port, request)

    {:noreply, state}
  end

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    handle_line(line, state)
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | buffer: state.buffer <> chunk}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Codex process exited with status #{status}")
    {:stop, {:codex_exit, status}, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{port: port}) when is_port(port) do
    Port.close(port)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Private Functions

  defp handle_line(line, state) do
    full_line = state.buffer <> line
    state = %{state | buffer: ""}

    case Jason.decode(full_line) do
      {:ok, message} ->
        handle_message(message, state)

      {:error, reason} ->
        Logger.warning("Failed to parse JSON-RPC message: #{inspect(reason)}, line: #{full_line}")
        {:noreply, state}
    end
  end

  defp handle_message(%{"id" => id, "result" => result}, state) when not is_nil(id) do
    state = maybe_handle_initialize(id, state)
    Logger.debug("Codex RPC response received id=#{inspect(id)} result=#{inspect(summarize(result))}")
    enqueue_response(%{"id" => id, "result" => result})
    {:noreply, state}
  end

  defp handle_message(%{"id" => id, "error" => error}, state) when not is_nil(id) do
    state = maybe_handle_initialize(id, state)
    Logger.debug("Codex RPC error received id=#{inspect(id)} error=#{inspect(error)}")
    enqueue_response(%{"id" => id, "error" => error})
    {:noreply, state}
  end

  defp handle_message(%{"id" => id, "method" => method} = message, state)
       when not is_nil(id) do
    params = Map.get(message, "params", %{})
    enqueue_event(method, params)

    method_norm =
      if is_binary(method) do
        String.replace(method, ".", "/")
      else
        method
      end

    response =
      case method_norm do
        "commandExecution/approve" ->
          %{id: id, result: %{decision: approval_decision(method, params)}}

        "fileChange/approve" ->
          %{id: id, result: %{decision: approval_decision(method, params)}}

        _ ->
          Logger.warning("Codex server request not supported",
            codex_method: method,
            codex_method_normalized: method_norm,
            codex_request_id: id
          )

          %{id: id, error: %{code: -32_601, message: "Method not supported"}}
      end

    send_json(state.port, response)
    {:noreply, state}
  end

  defp handle_message(%{"method" => method, "params" => params}, state) do
    Logger.debug(
      "Codex notification received method=#{method} params_keys=#{inspect(Map.keys(params))}"
    )

    if Application.get_env(:piano, :log_codex_event_payloads, false) do
      Logger.debug("Codex notification payload method=#{method} params=#{inspect(params, limit: 50)}")
    end

    enqueue_event(method, params)
    {:noreply, state}
  end

  defp handle_message(%{"method" => method}, state) do
    Logger.debug("Codex notification received method=#{method} (no params)")
    handle_message(%{"method" => method, "params" => %{}}, state)
  end

  defp handle_message(message, state) do
    Logger.warning("Unknown message format: #{inspect(message)}")
    {:noreply, state}
  end

  defp send_json(port, data) do
    json = Jason.encode!(data)
    Port.command(port, json <> "\n")
  end

  defp find_executable(command) do
    case System.find_executable(command) do
      nil -> raise "Could not find executable: #{command}"
      path -> path
    end
  end

  defp build_port_env(env_overrides) when is_list(env_overrides) do
    base =
      System.get_env()
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    overrides =
      env_overrides
      |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    merged =
      (base ++ overrides)
      |> Enum.reverse()
      |> Enum.uniq_by(fn {k, _v} -> k end)
      |> Enum.reverse()

    merged
  end

  defp env_value(env, key) when is_list(env) and is_binary(key) do
    k = String.to_charlist(key)

    case Enum.find(env, fn {ek, _} -> ek == k end) do
      {_, v} -> List.to_string(v)
      nil -> nil
    end
  end

  defp codex_cwd_from_env(env) when is_list(env) do
    case env_value(env, "CODEX_HOME") do
      home when is_binary(home) ->
        if String.ends_with?(home, "/.codex") do
          Path.dirname(home)
        else
          File.cwd!()
        end

      _ ->
        File.cwd!()
    end
  end

  defp maybe_handle_initialize(id, state) do
    if id == state.initialize_id and not state.initialized do
      send_json(state.port, %{method: "initialized", params: %{}})
      Logger.info("Codex client initialized")
      %{state | initialized: true}
    else
      state
    end
  end

  defp enqueue_response(response) do
    # RPC responses are handled specially, not parsed as events
    CodexEventProducer.enqueue(%{
      type: :rpc_response,
      payload: response,
      partition_key: extract_partition_key(response)
    })
  end

  defp enqueue_event(method, params) do
    # Parse the event into a structured struct immediately
    # Events.parse handles method normalization (e.g., "turn.started" -> "turn/started")
    event =
      case Piano.Codex.Events.parse(%{method: method, params: params}) do
        {:ok, parsed_event} ->
          parsed_event

        {:error, reason} ->
          Logger.warning("Failed to parse Codex event: #{inspect(reason)}, method: #{method}")
          # Fall back to raw event for unknown types
          %{method: method, params: params, parse_error: reason}
      end

    CodexEventProducer.enqueue(%{
      type: :event,
      event: event,
      partition_key: extract_partition_key(params)
    })
  end

  defp extract_partition_key(params) do
    extract_thread_id(params) ||
      extract_thread_id_from_response(params) ||
      "codex"
  end

  defp extract_thread_id(%{"threadId" => thread_id}) when is_binary(thread_id), do: thread_id

  defp extract_thread_id(params) when is_map(params) do
    get_in(params, ["thread", "id"]) ||
      get_in(params, ["turn", "threadId"]) ||
      get_in(params, ["turn", "thread", "id"]) ||
      get_in(params, ["item", "threadId"]) ||
      get_in(params, ["item", "thread", "id"])
  end

  defp extract_thread_id(_), do: nil

  defp extract_thread_id_from_response(%{"id" => id, "result" => result}) do
    extract_thread_id(result) || lookup_request_thread(id)
  end

  defp extract_thread_id_from_response(%{"id" => id}), do: lookup_request_thread(id)
  defp extract_thread_id_from_response(_), do: nil

  defp lookup_request_thread(id) do
    case RequestMap.get(id) do
      {:ok, %{thread_id: thread_id}} -> thread_id
      _ -> nil
    end
  end

  defp summarize(value) when is_map(value) do
    Map.take(value, ["threadId", "turnId", "thread", "turn"])
  end

  defp summarize(_), do: %{}

  defp log_outbound(%{method: method} = message) when method in ["thread/start", "turn/start"] do
    Logger.debug("Codex RPC request sent method=#{method} id=#{inspect(message[:id])}")
  end

  defp log_outbound(_), do: :ok

  defp approval_decision(method, params) do
    event = %{method: method, params: params}

    with {:ok, interaction} <- fetch_interaction_for_approval(params),
         {:ok, interaction} <- Ash.load(interaction, [:surface]) do
      case Piano.Surface.on_approval_required(interaction.surface, interaction, event) do
        {:ok, :accept} -> "accept"
        {:ok, :decline} -> "decline"
        {:ok, decision} when is_binary(decision) -> decision
        _ -> "decline"
      end
    else
      _ -> "decline"
    end
  end

  defp fetch_interaction_for_approval(params) do
    interaction_id = params["interactionId"]
    turn_id = params["turnId"]

    cond do
      is_binary(interaction_id) ->
        Ash.get(Interaction, interaction_id)

      is_binary(turn_id) ->
        query =
          Interaction
          |> Ash.Query.for_read(:read)
          |> Ash.Query.filter(expr(codex_turn_id == ^turn_id))

        case Ash.read(query) do
          {:ok, [interaction | _]} -> {:ok, interaction}
          {:ok, []} -> {:error, :not_found}
          {:error, _} = error -> error
        end

      true ->
        {:error, :not_found}
    end
  end
end
