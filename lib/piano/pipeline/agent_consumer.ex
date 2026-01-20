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
  alias ReqLLM.{Context, Response, ToolCall}

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
    query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: thread_id})

    case Ash.read(query) do
      {:ok, messages} ->
        sorted = Enum.sort_by(messages, & &1.inserted_at, DateTime)
        {:ok, sorted}

      {:error, _} = error ->
        error
    end
  end

  @max_tool_iterations 5

  defp call_llm(agent, messages) do
    system_prompt = build_system_prompt(agent)
    llm_messages = build_llm_messages(system_prompt, messages)
    tools = ToolRegistry.get_tools(agent.enabled_tools)

    case LLM.complete(llm_messages, tools, model: agent.model) do
      {:ok, response} ->
        handle_llm_response(response, tools, llm_messages, agent, 0)

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
    history =
      Enum.map(messages, fn msg ->
        case msg.role do
          :user -> Context.user(msg.content)
          :agent -> Context.assistant(msg.content)
          :assistant -> Context.assistant(msg.content)
          :system -> Context.system(msg.content)
          _ -> Context.user(msg.content)
        end
      end)

    Context.new([Context.system(system_prompt) | history])
  end

  defp handle_llm_response(response, tools, llm_messages, agent, iteration) do
    tool_calls = LLM.extract_tool_calls(response)

    cond do
      Enum.empty?(tool_calls) ->
        content = normalize_content(LLM.extract_content(response))

        if content == "" do
          Logger.warning("LLM returned empty content with no tool calls")
        end

        {:ok, content}

      iteration >= @max_tool_iterations ->
        Logger.warning("Max tool iterations (#{@max_tool_iterations}) reached, returning partial response")
        content =
          LLM.extract_content(response) ||
            "I attempted to use tools but reached the maximum number of iterations."

        {:ok, normalize_content(content)}

      true ->
        execute_tool_calls_and_continue(response, tool_calls, tools, llm_messages, agent, iteration)
    end
  end

  defp execute_tool_calls_and_continue(response, tool_calls, tools, llm_messages, agent, iteration) do
    base_context =
      case response do
        %ReqLLM.Response{context: %ReqLLM.Context{} = ctx} -> ctx
        _ -> llm_messages
      end

    updated_context =
      base_context
      |> maybe_append_assistant(response, tool_calls)
      |> append_tool_results(tool_calls, tools)

    case LLM.complete(updated_context, tools, model: agent.model) do
      {:ok, new_response} ->
        handle_llm_response(new_response, tools, updated_context, agent, iteration + 1)

      {:error, _} = error ->
        error
    end
  end

  defp maybe_append_assistant(%Context{} = context, %Response{message: %ReqLLM.Message{} = msg}, _)
       do
    if List.last(context.messages) == msg do
      context
    else
      Context.append(context, msg)
    end
  end

  defp maybe_append_assistant(%Context{} = context, response, tool_calls) do
    assistant_msg =
      Context.assistant(LLM.extract_content(response) || "", tool_calls: normalize_tool_calls(tool_calls))

    Context.append(context, assistant_msg)
  end

  defp append_tool_results(%Context{} = context, tool_calls, tools) do
    Enum.reduce(tool_calls, context, fn call, ctx ->
      {name, id, args} = normalize_tool_call(call)

      Logger.debug("Executing tool #{name} with args: #{inspect(args)}")

      result =
        case Enum.find(tools, fn t -> t.name == name end) do
          nil -> {:error, "Unknown tool: #{name}"}
          tool -> ReqLLM.Tool.execute(tool, args)
        end

      case result do
        {:ok, output} ->
          Logger.debug("Tool #{name} returned #{byte_size(to_string(output))} bytes")
          Context.append(ctx, Context.tool_result_message(name, id, output))

        {:error, error} ->
          Logger.warning("Tool #{name} failed: #{inspect(error)}")
          Context.append(ctx, Context.tool_result_message(name, id, %{error: inspect(error)}))
      end
    end)
  end

  defp normalize_tool_call(%ToolCall{} = call) do
    {call.function.name, call.id, normalize_args(ToolCall.args_map(call))}
  end

  defp normalize_tool_call(%{"name" => name, "arguments" => args} = call) do
    {name, Map.get(call, "id") || "call_#{:erlang.unique_integer()}", normalize_args(args)}
  end

  defp normalize_tool_call(%{name: name, arguments: args} = call) do
    {name, Map.get(call, :id) || "call_#{:erlang.unique_integer()}", normalize_args(args)}
  end

  defp normalize_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn call ->
      {name, id, args} = normalize_tool_call(call)
      %{name: name, arguments: args, id: id}
    end)
  end

  defp create_agent_message(thread_id, agent_id, content) do
    content = normalize_content(content)

    if content == "" do
      Logger.warning("Skipping empty agent message content for thread #{thread_id}")
    end

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

  defp normalize_content(nil), do: ""
  defp normalize_content(content) when is_binary(content), do: content
  defp normalize_content(content), do: to_string(content)

  defp normalize_args(nil), do: %{}

  defp normalize_args(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      {:ok, _} -> %{}
      {:error, error} ->
        Logger.warning("Failed to decode tool args JSON: #{inspect(error)}")
        %{}
    end
  end

  defp normalize_args(args) when is_map(args), do: args
  defp normalize_args(args), do: Map.new(args)
end
