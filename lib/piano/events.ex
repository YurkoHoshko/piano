defmodule Piano.Events do
  @moduledoc """
  PubSub event broadcasting and subscription helpers.
  """

  @pubsub Piano.PubSub

  @doc """
  Subscribes to events for a specific thread.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(thread_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(thread_id))
  end

  @doc """
  Unsubscribes from events for a specific thread.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(thread_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(thread_id))
  end

  @doc """
  Broadcasts an event for a specific thread.
  """
  @spec broadcast(String.t(), term()) :: :ok | {:error, term()}
  def broadcast(thread_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(thread_id), event)
  end

  defp topic(thread_id), do: "thread:#{thread_id}"
end
