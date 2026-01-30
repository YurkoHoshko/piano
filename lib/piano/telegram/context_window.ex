defmodule Piano.Telegram.ContextWindow do
  use GenServer

  @moduledoc """
  GenServer keeping a small in-memory ETS window of recent Telegram messages per chat.
  """

  @table :piano_telegram_context_window
  @default_window_size 200
  @default_max_message_len 280

  @type context_msg :: %{
          message_id: integer() | nil,
          from: String.t(),
          text: String.t()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_args) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  @spec record(map(), String.t()) :: :ok
  def record(msg, text), do: GenServer.cast(__MODULE__, {:record, msg, text})

  @spec mark_tagged(integer(), integer() | nil) :: :ok
  def mark_tagged(chat_id, message_id), do: GenServer.cast(__MODULE__, {:mark_tagged, chat_id, message_id})

  @spec recent(integer(), keyword()) :: [context_msg]
  def recent(chat_id, opts \\ []), do: GenServer.call(__MODULE__, {:recent, chat_id, opts}, 5_000)

  @impl true
  def handle_cast({:record, msg, text}, state) do
    ensure_table!()
    chat_id = dig(msg, [:chat, :id])
    chat_type = dig(msg, [:chat, :type])

    if is_integer(chat_id) and chat_type in ["group", "supergroup"] do
      window_size = Application.get_env(:piano, :telegram_context_window_size, @default_window_size)
      max_len = Application.get_env(:piano, :telegram_context_max_message_len, @default_max_message_len)

      entry = %{
        message_id: dig(msg, [:message_id]),
        from: sender_tag(msg),
        text: text |> String.trim() |> truncate(max_len)
      }

      key = chat_id
      current = get_state(key)
      list = (current.messages ++ [entry]) |> Enum.take(-window_size)
      require Logger
      Logger.warn("inserting #{inspect(list)} into storage")
      :ets.insert(@table, {key, %{current | messages: list}})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:mark_tagged, chat_id, message_id}, state) do
    ensure_table!()
    current = get_state(chat_id)
    if is_integer(message_id) do
      :ets.insert(@table, {chat_id, %{current | last_tagged_message_id: message_id}})
    end
    {:noreply, state}
  end

  @impl true
  def handle_call({:recent, chat_id, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 10)
    exclude_message_id = Keyword.get(opts, :exclude_message_id)
    mode = Keyword.get(opts, :mode, :last_n)

    current = get_state(chat_id)
    list = current.messages

    require Logger
    Logger.warning(inspect(list))

    list =
      if is_integer(exclude_message_id) do
        Enum.reject(list, fn m -> m.message_id == exclude_message_id end)
      else
        list
      end

    result =
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

    {:reply, result, state}
  end

  # Private helpers unchanged
  defp ensure_table!, do: :ok  # Already ensured in init

  defp get_state(chat_id) do
    case :ets.lookup(@table, chat_id) do
      [{^chat_id, %{messages: _} = state}] -> state
      [{^chat_id, list}] when is_list(list) -> %{messages: list, last_tagged_message_id: nil}
      _ -> %{messages: [], last_tagged_message_id: nil}
    end
  end

  defp truncate(text, max_len) when byte_size(text) > max_len do
    String.slice(text, 0, max_len - 1) <> "…"
  end
  defp truncate(text, _), do: text

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
