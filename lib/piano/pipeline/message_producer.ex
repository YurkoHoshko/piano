defmodule Piano.Pipeline.MessageProducer do
  @moduledoc """
  GenStage producer for the message processing pipeline.
  Receives incoming message events and buffers them until consumers request them.
  """

  use GenStage

  alias Piano.Telegram.SessionMapper

  @type event :: %{
          thread_id: String.t(),
          message_id: String.t(),
          agent_id: String.t(),
          chat_id: integer(),
          telegram_message_id: integer()
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

  @doc """
  Cancels a queued Telegram message for a chat.
  """
  @spec cancel_telegram(integer(), integer()) :: :ok
  def cancel_telegram(chat_id, telegram_message_id) do
    GenStage.cast(__MODULE__, {:cancel_telegram, chat_id, telegram_message_id})
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
  def handle_cast({:cancel_telegram, chat_id, telegram_message_id}, {queue, pending_demand}) do
    queue =
      queue
      |> :queue.to_list()
      |> Enum.reject(fn event ->
        event[:chat_id] == chat_id and event[:telegram_message_id] == telegram_message_id
      end)
      |> :queue.from_list()

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
    dispatch_events(queue, demand, events, :queue.len(queue))
  end

  defp dispatch_events(queue, 0, events, _remaining) do
    {:noreply, Enum.reverse(events), {queue, 0}}
  end

  defp dispatch_events(queue, demand, events, 0) do
    {:noreply, Enum.reverse(events), {queue, demand}}
  end

  defp dispatch_events(queue, demand, events, remaining) do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        if should_dispatch?(event) do
          dispatch_events(queue, demand - 1, [event | events], remaining - 1)
        else
          dispatch_events(:queue.in(event, queue), demand, events, remaining - 1)
        end

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end

  defp should_dispatch?(%{chat_id: chat_id, telegram_message_id: message_id})
       when is_integer(chat_id) and is_integer(message_id) do
    pending = SessionMapper.get_pending_message_id(chat_id)
    pending == nil or pending == message_id
  end

  defp should_dispatch?(_event), do: true
end
