defmodule Piano.Codex do
  @moduledoc """
  High-level API for interacting with Codex app-server.

  This module provides functions to start threads, execute turns,
  and handle the event streaming back to surfaces.
  """

  alias Piano.Codex.Client
  alias Piano.Codex.RequestMap
  alias Piano.Core.{Thread, Interaction}
  require Logger

  @doc """
  Start a Codex turn for an interaction.

  This function:
  1. Loads the interaction + surface
  2. Resolves an active thread for the surface (or creates one)
  3. Ensures a Codex thread exists (async if needed)
  4. Starts a turn when the Codex thread is ready

  Returns `{:ok, interaction}` or `{:error, reason}`.
  """
  def start_turn(interaction, opts \\ []) do
    client = Keyword.get(opts, :client, Client)

    with {:ok, interaction} <- load_interaction(interaction),
         {:ok, thread} <- resolve_thread(interaction),
         {:ok, interaction} <- update_interaction_thread(interaction, thread) do
      Logger.debug("Codex start_turn", interaction_id: interaction.id, thread_id: thread.id)

      case ensure_codex_thread(thread, client) do
        {:ok, %{status: :ready, thread: thread}} ->
          Logger.debug("Codex thread ready", thread_id: thread.id, codex_thread_id: thread.codex_thread_id)
          :ok = request_turn_start(interaction, thread, client)
          {:ok, interaction}

        {:ok, %{status: :pending}} ->
          Logger.debug("Codex thread pending", thread_id: thread.id)
          {:ok, interaction}
      end
    end
  end

  @doc """
  Start a new Codex thread (async).
  """
  def start_thread(%Thread{} = thread, client \\ Client) do
    request_id = request_id()
    :ok = RequestMap.put(request_id, %{type: :thread_start, thread_id: thread.id, client: client})
    :ok = Client.send_request(client, "thread/start", %{}, request_id)
    {:ok, request_id}
  end

  @doc """
  Force-start a new Codex thread by clearing the cached thread id first.
  """
  def force_start_thread(%Thread{} = thread, client \\ Client) do
    Logger.debug("Codex force-start thread", thread_id: thread.id)

    with {:ok, updated} <- Ash.update(thread, %{codex_thread_id: nil}, action: :set_codex_thread_id) do
      start_thread(updated, client)
    end
  end

  def force_start_thread(thread_id, client) when is_binary(thread_id) do
    with {:ok, thread} <- Ash.get(Thread, thread_id) do
      force_start_thread(thread, client)
    end
  end

  @doc """
  Read effective Codex app-server configuration.
  """
  def read_config(client \\ Client) do
    request_id = request_id()
    :ok = Client.send_request(client, "config/read", %{}, request_id)
    {:ok, request_id}
  end

  @doc """
  Interrupt an active turn.
  """
  def interrupt_turn(turn_id, client \\ Client) do
    request_id = request_id()
    :ok = Client.send_request(client, "turn/interrupt", %{turnId: turn_id}, request_id)
    {:ok, request_id}
  end

  @doc """
  Archive a thread.
  """
  def archive_thread(thread_id, client \\ Client) when is_binary(thread_id) do
    request_id = request_id()
    :ok = Client.send_request(client, "thread/archive", %{threadId: thread_id}, request_id)
    {:ok, request_id}
  end

  # Private Functions

  defp load_interaction(%Interaction{} = interaction) do
    case Ash.load(interaction, [:thread, thread: [:agent]]) do
      {:ok, loaded} -> {:ok, loaded}
      {:error, reason} -> {:error, {:load_failed, reason}}
    end
  end

  defp load_interaction(interaction_id) when is_binary(interaction_id) do
    case Ash.get(Interaction, interaction_id) do
      {:ok, interaction} -> load_interaction(interaction)
      {:error, reason} -> {:error, {:not_found, reason}}
    end
  end

  defp resolve_thread(%Interaction{thread: %Thread{} = thread}), do: {:ok, thread}

  defp resolve_thread(%Interaction{thread: nil, reply_to: reply_to}) do
    case find_recent_thread(reply_to) do
      {:ok, thread} -> {:ok, thread}
      {:error, :not_found} -> create_thread(reply_to)
      {:error, _} = error -> error
    end
  end

  defp find_recent_thread(reply_to) do
    query = Ash.Query.for_read(Thread, :find_recent_for_reply_to, %{reply_to: reply_to})

    case Ash.read(query) do
      {:ok, [thread | _]} -> {:ok, thread}
      {:ok, []} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp create_thread(reply_to) do
    Ash.create(Thread, %{reply_to: reply_to}, action: :create)
  end

  defp ensure_codex_thread(%Thread{codex_thread_id: id} = thread, _client)
       when is_binary(id) and id != "" do
    {:ok, %{status: :ready, thread: thread}}
  end

  defp ensure_codex_thread(%Thread{} = thread, client) do
    Logger.debug("Codex thread missing codex_thread_id, starting", thread_id: thread.id)
    {:ok, _request_id} = start_thread(thread, client)
    {:ok, %{status: :pending, thread: thread}}
  end

  defp update_interaction_thread(interaction, thread) do
    if interaction.thread_id == thread.id do
      {:ok, %{interaction | thread: thread}}
    else
      case Ash.update(interaction, %{thread_id: thread.id}, action: :assign_thread) do
        {:ok, updated} -> {:ok, %{updated | thread: thread}}
        {:error, reason} -> {:error, {:thread_assign_failed, reason}}
      end
    end
  end

  defp request_turn_start(interaction, thread, client) do
    input = [%{type: "text", text: interaction.original_message}]

    params = %{
      threadId: thread.codex_thread_id,
      input: input
    }

    params = params |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

    request_id = request_id()
    :ok = RequestMap.put(request_id, %{
      type: :turn_start,
      thread_id: thread.id,
      interaction_id: interaction.id
    })
    Logger.debug("Codex turn/start request", request_id: request_id, thread_id: thread.id)
    Client.send_request(client, "turn/start", params, request_id)
  end

  defp request_id do
    System.unique_integer([:positive])
  end
end
