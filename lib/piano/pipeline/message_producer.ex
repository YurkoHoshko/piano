defmodule Piano.Pipeline.MessageProducer do
  @moduledoc """
  GenStage producer for the message processing pipeline.
  Receives incoming message events and buffers them until consumers request them.
  """

  use GenStage

  @type event :: %{
          thread_id: String.t(),
          message_id: String.t(),
          agent_id: String.t()
        }

  # Client API

  @doc """
  Starts the MessageProducer.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues a message event for processing.
  The event should contain thread_id, message_id, and agent_id.
  """
  @spec enqueue(event()) :: :ok
  def enqueue(event) when is_map(event) do
    GenStage.cast(__MODULE__, {:enqueue, event})
  end

  # GenStage callbacks

  @impl true
  def init(_opts) do
    {:producer, {:queue.new(), 0}}
  end

  @impl true
  def handle_cast({:enqueue, event}, {queue, pending_demand}) do
    queue = :queue.in(event, queue)
    dispatch_events(queue, pending_demand, [])
  end

  @impl true
  def handle_demand(incoming_demand, {queue, pending_demand}) do
    dispatch_events(queue, incoming_demand + pending_demand, [])
  end

  defp dispatch_events(queue, 0, events) do
    {:noreply, Enum.reverse(events), {queue, 0}}
  end

  defp dispatch_events(queue, demand, events) do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(queue, demand - 1, [event | events])

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end
end
