defmodule Piano.Telegram.ContextWindow do
  @moduledoc """
  Keeps a small in-memory window of recent Telegram messages per chat.

  This is used to provide lightweight group-chat context when a user tags the bot.
  """

  @table :piano_telegram_context_window
  @default_window_size 200
  @default_max_message_len 280

  @type context_msg :: %{
          message_id: integer() | nil,
          from: String.t(),
          text: String.t()
        }

  @spec record(map(), String.t()) :: :ok
  def record(msg, text) when is_map(msg) and is_binary(text) do
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

      state = get_state(key)
      list = (state.messages ++ [entry]) |> Enum.take(-window_size)
      :ets.insert(@table, {key, %{state | messages: list}})
    end

    :ok
  end

  @spec mark_tagged(integer(), integer() | nil) :: :ok
  def mark_tagged(chat_id, message_id) when is_integer(chat_id) do
    ensure_table!()

    state = get_state(chat_id)

    if is_integer(message_id) do
      :ets.insert(@table, {chat_id, %{state | last_tagged_message_id: message_id}})
    end

    :ok
  end

  @spec recent(integer(), keyword()) :: [context_msg]
  def recent(chat_id, opts \\ []) when is_integer(chat_id) and is_list(opts) do
    ensure_table!()

    limit = Keyword.get(opts, :limit, 10)
    exclude_message_id = Keyword.get(opts, :exclude_message_id)
    mode = Keyword.get(opts, :mode, :last_n)

    state = get_state(chat_id)
    list = state.messages

    list =
      if is_integer(exclude_message_id) do
        Enum.reject(list, fn m -> m.message_id == exclude_message_id end)
      else
        list
      end

    case mode do
      :since_last_tag_or_last_n ->
        after_last_tag =
          if is_integer(state.last_tagged_message_id) do
            Enum.filter(list, fn
              %{message_id: mid} when is_integer(mid) -> mid > state.last_tagged_message_id
              _ -> false
            end)
          else
            []
          end

        if after_last_tag != [] do
          after_last_tag
        else
          Enum.take(list, -limit)
        end

      _ ->
        Enum.take(list, -limit)
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        _ = :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  defp get_state(chat_id) when is_integer(chat_id) do
    case :ets.lookup(@table, chat_id) do
      [{^chat_id, %{messages: _messages} = state}] ->
        state

      [{^chat_id, list}] when is_list(list) ->
        %{messages: list, last_tagged_message_id: nil}

      _ ->
        %{messages: [], last_tagged_message_id: nil}
    end
  end

  defp truncate(text, max_len) when is_binary(text) and is_integer(max_len) do
    if String.length(text) <= max_len do
      text
    else
      String.slice(text, 0, max_len - 1) <> "…"
    end
  end

  defp sender_tag(msg) do
    username = dig(msg, [:from, :username])
    first_name = dig(msg, [:from, :first_name])
    last_name = dig(msg, [:from, :last_name])

    cond do
      is_binary(username) and username != "" -> "@#{username}"
      is_binary(first_name) and is_binary(last_name) -> String.trim("#{first_name} #{last_name}")
      is_binary(first_name) and first_name != "" -> first_name
      true -> "unknown"
    end
  end

  defp dig(data, []), do: data
  defp dig(nil, _keys), do: nil

  defp dig(data, [key | rest]) when is_map(data) and is_atom(key) do
    value = Map.get(data, key) || Map.get(data, Atom.to_string(key))
    dig(value, rest)
  end

  defp dig(_data, [_key | _rest]), do: nil
end
