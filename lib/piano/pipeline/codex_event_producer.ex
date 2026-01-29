defmodule Piano.Pipeline.CodexEventProducer do
  @moduledoc """
  GenStage producer for Codex app-server events.
  """

  use GenStage
  require Logger
  alias Broadway.Topology

  @type event :: %{
          method: String.t(),
          params: map(),
          partition_key: String.t() | nil
        }

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenStage.start_link(__MODULE__, opts, name: name)
  end

  @spec enqueue(event()) :: :ok
  def enqueue(event) when is_map(event) do
    producers =
      case producer_names() do
        [] ->
          []

        names ->
          names
      end

    Enum.each(producers, fn producer ->
      GenStage.cast(producer, {:enqueue, event})
    end)

    :ok
  end

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

  defp producer_names do
    Topology.producer_names(Piano.Pipeline.CodexEventPipeline)
  catch
    :exit, _ ->
      Logger.warning("CodexEventPipeline not running; attempting to start")

      case Piano.Pipeline.CodexEventPipeline.start_link() do
        {:ok, _pid} -> Topology.producer_names(Piano.Pipeline.CodexEventPipeline)
        {:error, {:already_started, _pid}} -> Topology.producer_names(Piano.Pipeline.CodexEventPipeline)
        {:error, _reason} -> []
      end
  end
end
