defmodule Piano.Telegram.SessionMapper do
  @moduledoc """
  Maps Telegram chat IDs to Piano thread IDs.

  Uses ETS for fast, concurrent access to chat-to-thread mappings.
  """

  use GenServer

  alias Piano.Chat.Thread

  @table_name :telegram_sessions

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current thread_id for a chat, or creates a new thread if none exists.
  """
  @spec get_or_create_thread(integer()) :: {:ok, String.t()} | {:error, term()}
  def get_or_create_thread(chat_id) do
    case :ets.lookup(@table_name, chat_id) do
      [{^chat_id, thread_id}] ->
        {:ok, thread_id}

      [] ->
        create_and_store_thread(chat_id)
    end
  end

  @doc """
  Sets the active thread for a chat.
  """
  @spec set_thread(integer(), String.t()) :: :ok
  def set_thread(chat_id, thread_id) do
    :ets.insert(@table_name, {chat_id, thread_id})
    :ok
  end

  @doc """
  Clears the thread mapping for a chat. Next message will create a new thread.
  """
  @spec reset_thread(integer()) :: :ok
  def reset_thread(chat_id) do
    :ets.delete(@table_name, chat_id)
    :ok
  end

  @doc """
  Gets the current thread_id for a chat, or nil if none exists.
  """
  @spec get_thread(integer()) :: String.t() | nil
  def get_thread(chat_id) do
    case :ets.lookup(@table_name, chat_id) do
      [{^chat_id, thread_id}] -> thread_id
      [] -> nil
    end
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{table: table}}
  end

  defp create_and_store_thread(chat_id) do
    case Ash.create(Thread, %{title: "Telegram Chat"}, action: :create) do
      {:ok, thread} ->
        :ets.insert(@table_name, {chat_id, thread.id})
        {:ok, thread.id}

      {:error, _} = error ->
        error
    end
  end
end
