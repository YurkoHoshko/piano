defmodule Piano.Codex.Client do
  @moduledoc """
  GenServer wrapping the `codex app-server` process.

  Communicates via JSON-RPC 2.0 over stdio (JSONL).
  Handles bidirectional communication - sends requests and receives
  both responses and server-initiated requests (approvals).
  """
  use GenServer

  require Logger

  @default_codex_command "codex"
  @initialize_timeout 30_000
  @request_timeout 60_000

  defstruct [
    :port,
    :pending_requests,
    :notification_handlers,
    :request_handlers,
    :next_id,
    :buffer,
    :initialized
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Send a JSON-RPC request and wait for response.
  """
  def request(client \\ __MODULE__, method, params, timeout \\ @request_timeout) do
    GenServer.call(client, {:request, method, params}, timeout)
  end

  @doc """
  Send a JSON-RPC notification (no response expected).
  """
  def notify(client \\ __MODULE__, method, params) do
    GenServer.cast(client, {:notify, method, params})
  end

  @doc """
  Register a handler for server-initiated notifications.
  Handler is a function (method, params) -> :ok
  """
  def register_notification_handler(client \\ __MODULE__, method, handler) do
    GenServer.call(client, {:register_notification_handler, method, handler})
  end

  @doc """
  Register a handler for server-initiated requests (like approvals).
  Handler is a function (method, params) -> {:ok, result} | {:error, code, message}
  """
  def register_request_handler(client \\ __MODULE__, method, handler) do
    GenServer.call(client, {:register_request_handler, method, handler})
  end

  @doc """
  Unregister a notification handler.
  """
  def unregister_notification_handler(client \\ __MODULE__, method) do
    GenServer.call(client, {:unregister_notification_handler, method})
  end

  @doc """
  Unregister a request handler.
  """
  def unregister_request_handler(client \\ __MODULE__, method) do
    GenServer.call(client, {:unregister_request_handler, method})
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
    codex_command = Keyword.get(opts, :codex_command, @default_codex_command)
    codex_args =
      Keyword.get(opts, :codex_args, Application.get_env(:piano, :codex_args, ["app-server"]))
    env = Keyword.get(opts, :env, [])
    auto_initialize = Keyword.get(opts, :auto_initialize, true)

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      {:line, 1_000_000},
      {:env, env}
    ]

    port = Port.open({:spawn_executable, find_executable(codex_command)}, [
      {:args, codex_args} | port_opts
    ])

    state = %__MODULE__{
      port: port,
      pending_requests: %{},
      notification_handlers: %{},
      request_handlers: %{},
      next_id: 1,
      buffer: "",
      initialized: false
    }

    if auto_initialize do
      send(self(), :do_initialize)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:request, method, params}, from, state) do
    {id, state} = next_request_id(state)

    request = %{
      id: id,
      method: method,
      params: params
    }

    send_json(state.port, request)

    timer_ref = Process.send_after(self(), {:request_timeout, id}, @request_timeout)

    state = %{state |
      pending_requests: Map.put(state.pending_requests, id, {from, timer_ref})
    }

    {:noreply, state}
  end

  def handle_call({:register_notification_handler, method, handler}, _from, state) do
    state = %{state | notification_handlers: Map.put(state.notification_handlers, method, handler)}
    {:reply, :ok, state}
  end

  def handle_call({:register_request_handler, method, handler}, _from, state) do
    state = %{state | request_handlers: Map.put(state.request_handlers, method, handler)}
    {:reply, :ok, state}
  end

  def handle_call({:unregister_notification_handler, method}, _from, state) do
    state = %{state | notification_handlers: Map.delete(state.notification_handlers, method)}
    {:reply, :ok, state}
  end

  def handle_call({:unregister_request_handler, method}, _from, state) do
    state = %{state | request_handlers: Map.delete(state.request_handlers, method)}
    {:reply, :ok, state}
  end

  def handle_call(:ready?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_cast({:notify, method, params}, state) do
    notification = %{
      method: method,
      params: params
    }

    send_json(state.port, notification)
    {:noreply, state}
  end

  @impl true
  def handle_info(:do_initialize, state) do
    {id, state} = next_request_id(state)

    request = %{
      id: id,
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

    timer_ref = Process.send_after(self(), {:initialize_timeout, id}, @initialize_timeout)

    state = %{state |
      pending_requests: Map.put(state.pending_requests, id, {:initialize, timer_ref})
    }

    {:noreply, state}
  end

  def handle_info({:request_timeout, id}, state) do
    case Map.pop(state.pending_requests, id) do
      {{from, _timer_ref}, pending_requests} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_requests: pending_requests}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:initialize_timeout, id}, state) do
    case Map.get(state.pending_requests, id) do
      {:initialize, _timer_ref} ->
        Logger.error("Codex initialize timeout")
        {:stop, :initialize_timeout, state}

      _ ->
        {:noreply, state}
    end
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
    case Map.pop(state.pending_requests, id) do
      {{:initialize, timer_ref}, pending_requests} ->
        Process.cancel_timer(timer_ref)

        notification = %{
          method: "initialized",
          params: %{}
        }

        send_json(state.port, notification)
        Logger.info("Codex client initialized")

        {:noreply, %{state | pending_requests: pending_requests, initialized: true}}

      {{from, timer_ref}, pending_requests} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:ok, result})
        {:noreply, %{state | pending_requests: pending_requests}}

      {nil, _} ->
        Logger.warning("Received response for unknown request id: #{id}")
        {:noreply, state}
    end
  end

  defp handle_message(%{"id" => id, "error" => error}, state) when not is_nil(id) do
    case Map.pop(state.pending_requests, id) do
      {{:initialize, timer_ref}, _pending_requests} ->
        Process.cancel_timer(timer_ref)
        Logger.error("Codex initialize failed: #{inspect(error)}")
        {:stop, {:initialize_error, error}, state}

      {{from, timer_ref}, pending_requests} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:error, error})
        {:noreply, %{state | pending_requests: pending_requests}}

      {nil, _} ->
        Logger.warning("Received error for unknown request id: #{id}")
        {:noreply, state}
    end
  end

  defp handle_message(%{"id" => id, "method" => method, "params" => params}, state)
       when not is_nil(id) do
    response =
      case Map.get(state.request_handlers, method) do
        nil ->
          Logger.warning("No handler for request method: #{method}")
          %{
            id: id,
            error: %{code: -32601, message: "Method not found"}
          }

        handler ->
          case handler.(method, params) do
            {:ok, result} ->
              %{id: id, result: result}

            {:error, code, message} ->
              %{id: id, error: %{code: code, message: message}}
          end
      end

    send_json(state.port, response)
    {:noreply, state}
  end

  defp handle_message(%{"method" => method, "params" => params}, state) do
    case Map.get(state.notification_handlers, method) do
      nil ->
        case Map.get(state.notification_handlers, :default) do
          nil ->
            Logger.debug("No handler for notification: #{method}")

          handler ->
            Task.start(fn -> handler.(method, params) end)
        end

      handler ->
        Task.start(fn -> handler.(method, params) end)
    end

    {:noreply, state}
  end

  defp handle_message(%{"method" => method}, state) do
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

  defp next_request_id(state) do
    {state.next_id, %{state | next_id: state.next_id + 1}}
  end

  defp find_executable(command) do
    case System.find_executable(command) do
      nil -> raise "Could not find executable: #{command}"
      path -> path
    end
  end
end
