defmodule Piano.TestHarness.MockLLMServer do
  @moduledoc """
  Mock OpenAI-compatible API server for testing Codex integration.

  Starts a Bandit server on a random port that responds to chat completion
  requests with configurable response sequences.

  ## Usage

      {:ok, server} = MockLLMServer.start_link()
      port = MockLLMServer.port(server)

      # Configure responses
      MockLLMServer.queue_response(server, %{
        content: "Hello! How can I help?",
        tool_calls: nil
      })

      # Point Codex at http://localhost:<port>/v1
  """

  use GenServer

  require Logger

  defstruct [:port, :server_pid, :responses, :requests]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def port(server) do
    GenServer.call(server, :get_port)
  end

  def base_url(server) do
    "http://127.0.0.1:#{port(server)}/v1"
  end

  def queue_response(server, response) do
    GenServer.call(server, {:queue_response, response})
  end

  def queue_responses(server, responses) when is_list(responses) do
    Enum.each(responses, &queue_response(server, &1))
  end

  def get_requests(server) do
    GenServer.call(server, :get_requests)
  end

  def clear(server) do
    GenServer.call(server, :clear)
  end

  def stop(server) do
    GenServer.stop(server)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 0)

    state = %__MODULE__{
      responses: :queue.new(),
      requests: []
    }

    {:ok, state, {:continue, {:start_server, port}}}
  end

  @impl true
  def handle_continue({:start_server, port}, state) do
    parent = self()

    plug = {Piano.TestHarness.MockLLMServer.Plug, parent: parent}

    case Bandit.start_link(plug: plug, port: port, ip: {127, 0, 0, 1}) do
      {:ok, server_pid} ->
        {:ok, {_ip, actual_port}} = ThousandIsland.listener_info(server_pid)
        {:noreply, %{state | port: actual_port, server_pid: server_pid}}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  def handle_call({:queue_response, response}, _from, state) do
    responses = :queue.in(response, state.responses)
    {:reply, :ok, %{state | responses: responses}}
  end

  def handle_call(:get_requests, _from, state) do
    {:reply, Enum.reverse(state.requests), state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | responses: :queue.new(), requests: []}}
  end

  def handle_call(:pop_response, _from, state) do
    case :queue.out(state.responses) do
      {{:value, response}, remaining} ->
        {:reply, {:ok, response}, %{state | responses: remaining}}

      {:empty, _} ->
        {:reply, {:ok, default_response()}, state}
    end
  end

  def handle_call({:record_request, request}, _from, state) do
    {:reply, :ok, %{state | requests: [request | state.requests]}}
  end

  @impl true
  def terminate(_reason, %{server_pid: pid}) when is_pid(pid) do
    Supervisor.stop(pid)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp default_response do
    %{
      content: "I'm a mock response.",
      tool_calls: nil,
      finish_reason: "stop"
    }
  end
end

defmodule Piano.TestHarness.MockLLMServer.Plug do
  @moduledoc false

  use Plug.Router

  plug Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason

  plug :match
  plug :dispatch

  post "/v1/chat/completions" do
    parent = conn.private[:parent]
    GenServer.call(parent, {:record_request, conn.body_params})

    {:ok, response} = GenServer.call(parent, :pop_response)

    completion = build_completion(response)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(completion))
  end

  post "/v1/responses" do
    parent = conn.private[:parent]
    GenServer.call(parent, {:record_request, conn.body_params})

    {:ok, response} = GenServer.call(parent, :pop_response)

    resp = build_responses_api_response(response)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(resp))
  end

  get "/v1/models" do
    models = %{
      object: "list",
      data: [
        %{id: "gpt-4", object: "model", owned_by: "openai"},
        %{id: "o3", object: "model", owned_by: "openai"}
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(models))
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    conn = Plug.Conn.put_private(conn, :parent, opts[:parent])
    super(conn, opts)
  end

  defp build_completion(response) do
    message =
      case response do
        %{tool_calls: tool_calls} when is_list(tool_calls) and tool_calls != [] ->
          %{
            role: "assistant",
            content: response[:content],
            tool_calls: Enum.map(tool_calls, &build_tool_call/1)
          }

        _ ->
          %{
            role: "assistant",
            content: response[:content] || response["content"] || "Mock response"
          }
      end

    %{
      id: "chatcmpl-#{random_id()}",
      object: "chat.completion",
      created: System.system_time(:second),
      model: "gpt-4",
      choices: [
        %{
          index: 0,
          message: message,
          finish_reason: response[:finish_reason] || "stop"
        }
      ],
      usage: %{
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      }
    }
  end

  defp build_responses_api_response(response) do
    %{
      id: "resp-#{random_id()}",
      object: "response",
      created_at: System.system_time(:second),
      status: "completed",
      output: [
        %{
          type: "message",
          id: "msg-#{random_id()}",
          role: "assistant",
          content: [
            %{
              type: "output_text",
              text: response[:content] || response["content"] || "Mock response"
            }
          ]
        }
      ]
    }
  end

  defp build_tool_call(tool_call) do
    %{
      id: "call_#{random_id()}",
      type: "function",
      function: %{
        name: tool_call[:name] || tool_call["name"],
        arguments: Jason.encode!(tool_call[:arguments] || tool_call["arguments"] || %{})
      }
    }
  end

  defp random_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end
end
