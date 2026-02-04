defmodule Piano.Mock.Surface do
  @moduledoc """
  Mock surface for testing and background task execution.

  Addressed as `mock:<mock-id>` to provide isolation.
  Collects all surface callbacks as an Agent for inspection.

  ## Usage

      # Start a mock surface
      {:ok, surface} = MockSurface.start("test-123")

      # Use it in interactions (reply_to format)
      reply_to = MockSurface.build_reply_to("test-123")  # => "mock:test-123"

      # After interaction completes, inspect collected events
      events = MockSurface.get_results("test-123")

      # Clean up
      MockSurface.stop("test-123")
  """

  use Agent

  defstruct [:mock_id]

  @type t :: %__MODULE__{mock_id: String.t()}

  @doc """
  Start a new mock surface agent.
  """
  @spec start(String.t()) :: {:ok, t()} | {:error, term()}
  def start(mock_id) do
    name = via_tuple(mock_id)

    case Agent.start_link(fn -> [] end, name: name) do
      {:ok, _pid} -> {:ok, %__MODULE__{mock_id: mock_id}}
      {:error, {:already_started, _}} -> {:ok, %__MODULE__{mock_id: mock_id}}
      error -> error
    end
  end

  @doc """
  Stop a mock surface agent.
  """
  @spec stop(String.t()) :: :ok
  def stop(mock_id) do
    name = via_tuple(mock_id)

    case GenServer.whereis(name) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end
  end

  @doc """
  Get all collected results from the mock surface.
  """
  @spec get_results(String.t()) :: [map()]
  def get_results(mock_id) do
    name = via_tuple(mock_id)

    case GenServer.whereis(name) do
      nil -> []
      _pid -> Agent.get(name, & &1)
    end
  end

  @doc """
  Clear collected results.
  """
  @spec clear(String.t()) :: :ok
  def clear(mock_id) do
    name = via_tuple(mock_id)

    case GenServer.whereis(name) do
      nil -> :ok
      _pid -> Agent.update(name, fn _ -> [] end)
    end
  end

  @doc """
  Check if a mock surface exists.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(mock_id) do
    name = via_tuple(mock_id)
    GenServer.whereis(name) != nil
  end

  @doc """
  Parse a reply_to string into a MockSurface struct.

  ## Examples

      iex> Piano.Mock.Surface.parse("mock:test-123")
      {:ok, %Piano.Mock.Surface{mock_id: "test-123"}}

      iex> Piano.Mock.Surface.parse("telegram:123:456")
      :error
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse("mock:" <> mock_id) do
    {:ok, %__MODULE__{mock_id: mock_id}}
  end

  def parse(_), do: :error

  @doc """
  Build a reply_to string from mock_id.
  """
  @spec build_reply_to(String.t()) :: String.t()
  def build_reply_to(mock_id), do: "mock:#{mock_id}"

  @doc """
  Record an event to the mock surface agent.
  """
  @spec record_event(String.t(), atom(), map()) :: :ok
  def record_event(mock_id, event_type, data) do
    name = via_tuple(mock_id)

    event = %{
      type: event_type,
      data: data,
      timestamp: DateTime.utc_now()
    }

    case GenServer.whereis(name) do
      nil -> :ok
      _pid -> Agent.update(name, fn events -> events ++ [event] end)
    end
  end

  defp via_tuple(mock_id) do
    {:via, Registry, {Piano.Mock.Registry, mock_id}}
  end
end

defimpl Piano.Surface, for: Piano.Mock.Surface do
  alias Piano.Mock.Surface, as: MockSurface

  def on_turn_started(%{mock_id: mock_id}, context, params) do
    MockSurface.record_event(mock_id, :turn_started, %{context: context, params: params})
    {:ok, :recorded}
  end

  def on_turn_completed(%{mock_id: mock_id}, context, params) do
    MockSurface.record_event(mock_id, :turn_completed, %{context: context, params: params})
    {:ok, :recorded}
  end

  def on_item_started(%{mock_id: mock_id}, context, params) do
    MockSurface.record_event(mock_id, :item_started, %{context: context, params: params})
    {:ok, :recorded}
  end

  def on_item_completed(%{mock_id: mock_id}, context, params) do
    MockSurface.record_event(mock_id, :item_completed, %{context: context, params: params})
    {:ok, :recorded}
  end

  def on_agent_message_delta(%{mock_id: mock_id}, context, params) do
    MockSurface.record_event(mock_id, :agent_message_delta, %{context: context, params: params})
    {:ok, :recorded}
  end

  def on_approval_required(%{mock_id: mock_id}, context, params) do
    MockSurface.record_event(mock_id, :approval_required, %{context: context, params: params})
    {:ok, :recorded}
  end

  def send_thread_transcript(%{mock_id: mock_id}, thread_data) do
    MockSurface.record_event(mock_id, :thread_transcript, %{thread_data: thread_data})
    {:ok, :recorded}
  end

  def on_account_login_start(%{mock_id: mock_id}, response) do
    MockSurface.record_event(mock_id, :account_login_start, %{response: response})
    :ok
  end

  def on_account_read(%{mock_id: mock_id}, response) do
    MockSurface.record_event(mock_id, :account_read, %{response: response})
    :ok
  end

  def on_account_logout(%{mock_id: mock_id}, response) do
    MockSurface.record_event(mock_id, :account_logout, %{response: response})
    :ok
  end

  def on_thread_transcript(%{mock_id: mock_id}, response, placeholder_id) do
    MockSurface.record_event(mock_id, :thread_transcript_response, %{
      response: response,
      placeholder_id: placeholder_id
    })

    :ok
  end

  def send_message(%{mock_id: mock_id}, message) do
    MockSurface.record_event(mock_id, :message_sent, %{message: message})
    {:ok, :recorded}
  end

  def send_file(%{mock_id: mock_id}, file, opts) do
    MockSurface.record_event(mock_id, :file_sent, %{file: file, opts: opts})
    {:ok, :recorded}
  end
end
