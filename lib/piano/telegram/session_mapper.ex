defmodule Piano.Telegram.SessionMapper do
  @moduledoc """
  Maps Telegram chat IDs to Piano thread IDs.

  Uses database persistence via Piano.Telegram.Session resource.
  """

  alias Piano.Chat.Thread
  alias Piano.Telegram.Session

  @doc """
  Gets the current thread_id for a chat, or creates a new thread if none exists.
  """
  @spec get_or_create_thread(integer()) :: {:ok, String.t()} | {:error, term()}
  def get_or_create_thread(chat_id) do
    case get_session(chat_id) do
      {:ok, %{thread_id: thread_id}} ->
        {:ok, thread_id}

      {:ok, nil} ->
        create_and_store_thread(chat_id)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Sets the active thread for a chat.
  """
  @spec set_thread(integer(), String.t()) :: :ok | {:error, term()}
  def set_thread(chat_id, thread_id) do
    case get_session(chat_id) do
      {:ok, %Session{} = session} ->
        session
        |> Ash.Changeset.for_update(:update, %{thread_id: thread_id})
        |> Ash.update()
        |> case do
          {:ok, _} -> :ok
          {:error, _} = error -> error
        end

      {:ok, nil} ->
        Session
        |> Ash.Changeset.for_create(:create, %{chat_id: chat_id, thread_id: thread_id})
        |> Ash.create()
        |> case do
          {:ok, _} -> :ok
          {:error, _} = error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Clears the thread mapping for a chat. Next message will create a new thread.
  """
  @spec reset_thread(integer()) :: :ok
  def reset_thread(chat_id) do
    case get_session(chat_id) do
      {:ok, %Session{} = session} ->
        Ash.destroy!(session)
        :ok

      {:ok, nil} ->
        :ok

      {:error, _} ->
        :ok
    end
  end

  @doc """
  Gets the current thread_id for a chat, or nil if none exists.
  """
  @spec get_thread(integer()) :: String.t() | nil
  def get_thread(chat_id) do
    case get_session(chat_id) do
      {:ok, %{thread_id: thread_id}} -> thread_id
      {:ok, nil} -> nil
      {:error, _} -> nil
    end
  end

  @doc """
  Gets the current agent_id for a chat, or nil if none exists.
  """
  @spec get_agent(integer()) :: String.t() | nil
  def get_agent(chat_id) do
    case get_session(chat_id) do
      {:ok, %{agent_id: agent_id}} -> agent_id
      {:ok, nil} -> nil
      {:error, _} -> nil
    end
  end

  @doc """
  Sets the active agent for a chat.
  """
  @spec set_agent(integer(), String.t()) :: :ok | {:error, term()}
  def set_agent(chat_id, agent_id) do
    case get_session(chat_id) do
      {:ok, %Session{} = session} ->
        session
        |> Ash.Changeset.for_update(:update, %{agent_id: agent_id})
        |> Ash.update()
        |> case do
          {:ok, _} -> :ok
          {:error, _} = error -> error
        end

      {:ok, nil} ->
        with {:ok, thread} <- Ash.create(Thread, %{title: "Telegram Chat"}, action: :create),
             {:ok, _session} <-
               Session
               |> Ash.Changeset.for_create(:create, %{
                 chat_id: chat_id,
                 thread_id: thread.id,
                 agent_id: agent_id
               })
               |> Ash.create() do
          :ok
        end

      {:error, _} = error ->
        error
    end
  end

  defp get_session(chat_id) do
    Session
    |> Ash.Query.for_read(:by_chat_id, %{chat_id: chat_id})
    |> Ash.read_one()
  end

  defp create_and_store_thread(chat_id) do
    with {:ok, thread} <- Ash.create(Thread, %{title: "Telegram Chat"}, action: :create),
         {:ok, _session} <-
           Session
           |> Ash.Changeset.for_create(:create, %{chat_id: chat_id, thread_id: thread.id})
           |> Ash.create() do
      {:ok, thread.id}
    end
  end
end
