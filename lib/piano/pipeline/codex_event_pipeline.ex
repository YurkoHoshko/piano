defmodule Piano.Pipeline.CodexEventPipeline do
  @moduledoc false

  use Broadway

  def start_link(_opts \\ []) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Piano.Pipeline.CodexEventProducer, []},
        transformer: {__MODULE__, :wrap_message, []}
      ],
      processors: [default: [concurrency: System.schedulers_online(), max_demand: 20]],
      partition_by: fn message ->
        key = message.data.partition_key
        if is_integer(key), do: key, else: :erlang.phash2(key)
      end
    )
  end

  def wrap_message(event, _metadata) do
    %Broadway.Message{
      data: event,
      acknowledger: {Broadway.NoopAcknowledger, nil, nil}
    }
  end

  @impl true
  def handle_message(_processor, message, _context) do
    :ok = Piano.Pipeline.CodexEventConsumer.process(message.data)
    message
  end
end
