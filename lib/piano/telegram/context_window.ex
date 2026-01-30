defmodule Piano.Telegram.ContextWindow do
  use Agent

  @moduledoc """
  Agent keeping a small in-memory queue of recent Telegram messages per chat.
  Uses Erlang's :queue for efficient O(1) append and drop operations.
  """

  @default_window_size 200

  @type context_msg :: %{
          message_id: integer() | nil,
          from: String.t(),
          text: String.t()
        }

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec record(map(), String.t()) :: :ok
  def record(msg, text) do
    chat_id = dig(msg, [:chat, :id])
    chat_type = dig(msg, [:chat, :type])

    if is_integer(chat_id) and chat_type in ["group", "supergroup"] do
      window_size = Application.get_env(:piano, :telegram_context_window_size, @default_window_size)

      entry = %{
        message_id: dig(msg, [:message_id]),
        from: sender_tag(msg),
        text: String.trim(text)
      }

      Agent.update(__MODULE__, fn state ->
        current = Map.get(state, chat_id, %{queue: :queue.new(), last_tagged_message_id: nil})
        new_queue = :queue.in(entry, current.queue)
        
        # Trim from front if exceeds window size
        trimmed_queue = 
          if :queue.len(new_queue) > window_size do
            {_, q} = :queue.out(new_queue)
            q
          else
            new_queue
          end
        
        Map.put(state, chat_id, %{current | queue: trimmed_queue})
      end)
    end

    :ok
  end

  @spec mark_tagged(integer(), integer() | nil) :: :ok
  def mark_tagged(chat_id, message_id) do
    if is_integer(message_id) do
      Agent.update(__MODULE__, fn state ->
        current = Map.get(state, chat_id, %{queue: :queue.new(), last_tagged_message_id: nil})
        Map.put(state, chat_id, %{current | last_tagged_message_id: message_id})
      end)
    end

    :ok
  end

  @spec recent(integer(), keyword()) :: [context_msg]
  def recent(chat_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    exclude_message_id = Keyword.get(opts, :exclude_message_id)
    mode = Keyword.get(opts, :mode, :last_n)

    Agent.get(__MODULE__, fn state ->
      current = Map.get(state, chat_id, %{queue: :queue.new(), last_tagged_message_id: nil})
      list = :queue.to_list(current.queue)

      list =
        if is_integer(exclude_message_id) do
          Enum.reject(list, fn m -> m.message_id == exclude_message_id end)
        else
          list
        end

      case mode do
        :since_last_tag_or_last_n ->
          after_last_tag =
            if is_integer(current.last_tagged_message_id) do
              Enum.filter(list, fn %{message_id: mid} when is_integer(mid) -> mid > current.last_tagged_message_id end)
            else
              []
            end
          if after_last_tag != [], do: after_last_tag, else: Enum.take(list, -limit)

        _ ->
          Enum.take(list, -limit)
      end
    end)
  end

  defp sender_tag(msg) do
    username = dig(msg, [:from, :username])
    first_name = dig(msg, [:from, :first_name])
    last_name = dig(msg, [:from, :last_name])

    cond do
      username && username != "" -> "@#{username}"
      first_name && last_name -> String.trim("#{first_name} #{last_name}")
      first_name && first_name != "" -> first_name
      true -> "unknown"
    end
  end

  defp dig(data, []), do: data
  defp dig(nil, _), do: nil
  defp dig(data, [key | rest]) when is_map(data) do
    value = Map.get(data, key) || Map.get(data, to_string(key))
    dig(value, rest)
  end
  defp dig(_, _), do: nil
end
