defmodule Piano.Pipeline.AgentConsumer do
  @moduledoc """
  GenStage consumer that processes messages from MessageProducer.
  Loads agent config, builds message history, calls LLM, and stores responses.
  """

  use GenStage

  require Logger

  alias Piano.Agents.{Agent, ToolRegistry, SkillRegistry}
  alias Piano.Chat.Message
  alias Piano.{Events, LLM}

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:consumer, %{}, subscribe_to: [{Piano.Pipeline.MessageProducer, max_demand: 1}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    Enum.each(events, &process_event/1)
    {:noreply, [], state}
  end

  defp process_event(%{thread_id: thread_id, message_id: message_id, agent_id: agent_id}) do
    Logger.info("Processing message #{message_id} for thread #{thread_id}")

    Events.broadcast(thread_id, {:processing_started, message_id})

    with {:ok, agent} <- load_agent(agent_id),
         {:ok, messages} <- load_thread_messages(thread_id),
         {:ok, response} <- call_llm(agent, messages),
         {:ok, agent_message} <- create_agent_message(thread_id, agent_id, response) do
      Events.broadcast(thread_id, {:response_ready, agent_message})
      Logger.info("Successfully processed message #{message_id}")
    else
      {:error, reason} ->
        Logger.error("Failed to process message #{message_id}: #{inspect(reason)}")
        Events.broadcast(thread_id, {:processing_error, message_id, reason})
    end
  end

  defp load_agent(agent_id) do
    case Ash.get(Agent, agent_id) do
      {:ok, agent} -> {:ok, agent}
      {:error, _} = error -> error
    end
  end

  defp load_thread_messages(thread_id) do
    case Ash.read(Message, action: :list_by_thread, thread_id: thread_id) do
      {:ok, messages} ->
        sorted = Enum.sort_by(messages, & &1.inserted_at, DateTime)
        {:ok, sorted}

      {:error, _} = error ->
        error
    end
  end

  defp call_llm(agent, messages) do
    system_prompt = build_system_prompt(agent)
    llm_messages = build_llm_messages(system_prompt, messages)
    tools = ToolRegistry.get_tools(agent.enabled_tools)

    case LLM.complete(llm_messages, tools, model: agent.model) do
      {:ok, response} ->
        handle_llm_response(response, tools, llm_messages, agent)

      {:error, _} = error ->
        error
    end
  end

  defp build_system_prompt(agent) do
    skill_prompts = SkillRegistry.get_prompts(agent.enabled_skills)

    base_prompt = agent.system_prompt || "You are a helpful assistant."

    if skill_prompts == "" do
      base_prompt
    else
      "#{base_prompt}\n\n#{skill_prompts}"
    end
  end

  defp build_llm_messages(system_prompt, messages) do
    system_msg = %{role: "system", content: system_prompt}

    history =
      Enum.map(messages, fn msg ->
        role = if msg.role == :user, do: "user", else: "assistant"
        %{role: role, content: msg.content}
      end)

    [system_msg | history]
  end

  defp handle_llm_response(response, tools, llm_messages, agent) do
    tool_calls = LLM.extract_tool_calls(response)

    if Enum.empty?(tool_calls) do
      content = LLM.extract_content(response) || ""
      {:ok, content}
    else
      execute_tool_calls_and_continue(response, tool_calls, tools, llm_messages, agent)
    end
  end

  defp execute_tool_calls_and_continue(response, tool_calls, tools, llm_messages, agent) do
    assistant_msg = %{
      role: "assistant",
      content: LLM.extract_content(response),
      tool_calls: tool_calls
    }

    tool_results =
      Enum.map(tool_calls, fn tc ->
        function_name = tc["function"]["name"]
        arguments = Jason.decode!(tc["function"]["arguments"])

        result =
          case execute_tool(function_name, arguments, tools) do
            {:ok, output} -> output
            {:error, error} -> "Error: #{inspect(error)}"
          end

        %{
          role: "tool",
          tool_call_id: tc["id"],
          content: result
        }
      end)

    updated_messages = llm_messages ++ [assistant_msg | tool_results]

    case LLM.complete(updated_messages, tools, model: agent.model) do
      {:ok, new_response} ->
        handle_llm_response(new_response, tools, updated_messages, agent)

      {:error, _} = error ->
        error
    end
  end

  defp execute_tool(function_name, arguments, tools) do
    case Enum.find(tools, fn t -> t.name == function_name end) do
      nil ->
        {:error, "Unknown tool: #{function_name}"}

      tool ->
        tool.callback.(arguments)
    end
  end

  defp create_agent_message(thread_id, agent_id, content) do
    Ash.create(Message,
      %{
        content: content,
        role: :agent,
        source: :web,
        thread_id: thread_id,
        agent_id: agent_id
      },
      action: :create
    )
  end
end
