defmodule Piano.ChatGateway do
  @moduledoc """
  Entry point for incoming chat messages from various sources (web, telegram, etc).
  Resolves thread and agent, creates user message, and enqueues for processing.
  """

  alias Piano.Agents.Agent
  alias Piano.Chat.{Message, Thread}
  alias Piano.Pipeline.MessageProducer

  @type source :: :web | :telegram
  @type metadata :: %{
          optional(:thread_id) => String.t(),
          optional(:agent_id) => String.t(),
          optional(:title) => String.t(),
          optional(:chat_id) => integer(),
          optional(:telegram_message_id) => integer()
        }

  @doc """
  Handles an incoming message from a user.

  ## Parameters
    - content: The message content
    - source: The source channel (:web, :telegram)
    - metadata: Optional map with thread_id, agent_id, title

  ## Returns
    - {:ok, message} on success
    - {:error, reason} on failure
  """
  @spec handle_incoming(String.t(), source(), metadata()) ::
          {:ok, Message.t()} | {:error, term()}
  def handle_incoming(content, source, metadata \\ %{}) do
    with {:ok, thread, agent_id} <- resolve_thread_and_agent(metadata),
         {:ok, message} <- create_user_message(content, source, thread, metadata[:agent_id]) do
      MessageProducer.enqueue(%{
        thread_id: thread.id,
        message_id: message.id,
        agent_id: agent_id,
        chat_id: metadata[:chat_id],
        telegram_message_id: metadata[:telegram_message_id]
      })

      {:ok, message}
    end
  end

  defp resolve_thread_and_agent(metadata) do
    thread_id = metadata[:thread_id]
    agent_id = metadata[:agent_id]

    with {:ok, thread} <- resolve_thread(thread_id, agent_id, metadata[:title]),
         {:ok, resolved_agent_id} <- resolve_agent_id(agent_id, thread) do
      {:ok, thread, resolved_agent_id}
    end
  end

  defp resolve_thread(nil, agent_id, title) do
    Ash.create(Thread, %{title: title, primary_agent_id: agent_id}, action: :create)
  end

  defp resolve_thread(thread_id, _agent_id, _title) do
    Ash.get(Thread, thread_id)
  end

  defp resolve_agent_id(nil, thread) do
    case thread.primary_agent_id do
      nil -> get_default_agent_id()
      id -> {:ok, id}
    end
  end

  defp resolve_agent_id(agent_id, _thread), do: {:ok, agent_id}

  defp get_default_agent_id do
    case Ash.read(Agent, action: :list) do
      {:ok, [agent | _]} -> {:ok, agent.id}
      {:ok, []} -> {:error, :no_agents_configured}
      {:error, _} = error -> error
    end
  end

  defp create_user_message(content, source, thread, agent_id) do
    Ash.create(
      Message,
      %{
        content: content,
        role: :user,
        source: source,
        thread_id: thread.id,
        agent_id: agent_id
      },
      action: :create
    )
  end
end
