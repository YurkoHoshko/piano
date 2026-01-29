defmodule Piano.Pipeline.AgentConsumer do
  @moduledoc """
  GenStage consumer that processes messages from MessageProducer.
  Loads agent config, builds message history, calls LLM, and stores responses.
  """

  use GenStage

  require Logger

  alias Piano.Agents.{Agent, SystemPrompt, ToolRegistry}
  alias Piano.Chat.Message
  alias Piano.{Events, LLM}
  alias Piano.Telegram.SessionMapper
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

  defp process_event(%{thread_id: thread_id, message_id: message_id, agent_id: agent_id} = event) do
    chat_id = Map.get(event, :chat_id)
    telegram_message_id = Map.get(event, :telegram_message_id)

    case maybe_skip_cancelled(chat_id, telegram_message_id) do
      :skip ->
        :ok

      :ok ->
        maybe_set_pending(chat_id, telegram_message_id)

        Process.put(:piano_message_id, message_id)
        Logger.info("Processing message #{message_id} for thread #{thread_id}")
        Events.broadcast(thread_id, {:processing_started, message_id})

        result = run_pipeline(thread_id, message_id, agent_id, chat_id, telegram_message_id)

        Process.delete(:piano_message_id)
        maybe_clear_pending(chat_id, telegram_message_id)
        result
    end
  end

  defp maybe_skip_cancelled(nil, _telegram_message_id), do: :ok
  defp maybe_skip_cancelled(_chat_id, nil), do: :ok

  defp maybe_skip_cancelled(chat_id, telegram_message_id) do
    if telegram_cancelled?(chat_id, telegram_message_id) do
      clear_telegram_cancelled(chat_id, telegram_message_id)
      Logger.info("Skipping cancelled Telegram message #{telegram_message_id} for chat #{chat_id}")
      :skip
    else
      :ok
    end
  end

  defp maybe_set_pending(nil, _telegram_message_id), do: :ok
  defp maybe_set_pending(_chat_id, nil), do: :ok

  defp maybe_set_pending(chat_id, telegram_message_id) do
    SessionMapper.set_pending_message_id(chat_id, telegram_message_id)
  end

  defp maybe_clear_pending(nil, _telegram_message_id), do: :ok
  defp maybe_clear_pending(_chat_id, nil), do: :ok

  defp maybe_clear_pending(chat_id, telegram_message_id) do
    SessionMapper.clear_pending_message_id(chat_id, telegram_message_id)
  end

  defp run_pipeline(thread_id, message_id, agent_id, chat_id, telegram_message_id) do
    with {:ok, agent} <- load_agent(agent_id),
         {:ok, messages} <- load_thread_messages(thread_id),
         {:ok, response} <- call_llm(agent, messages, thread_id),
         {:ok, agent_message} <- create_agent_message(thread_id, agent_id, response) do
      Logger.info("Processed message #{message_id} with agent #{agent.name} (#{agent.id})")
      handle_success(thread_id, message_id, agent_message, chat_id, telegram_message_id)
    else
      {:error, reason} ->
        Logger.error("Failed to process message #{message_id}: #{inspect(reason)}")
        handle_failure(thread_id, message_id, reason, chat_id, telegram_message_id)
    end
  end

  defp handle_success(thread_id, message_id, agent_message, chat_id, telegram_message_id) do
    if telegram_cancelled?(chat_id, telegram_message_id) do
      Logger.info("Skipping response for cancelled Telegram message #{telegram_message_id}")
      clear_telegram_cancelled(chat_id, telegram_message_id)
      :cancelled
    else
      Events.broadcast(thread_id, {:response_ready, message_id, agent_message})
      Logger.info("Successfully processed message #{message_id}")
      :ok
    end
  end

  defp handle_failure(thread_id, message_id, reason, chat_id, telegram_message_id) do
    if telegram_cancelled?(chat_id, telegram_message_id) do
      Logger.info("Skipping error broadcast for cancelled Telegram message #{telegram_message_id}")
      clear_telegram_cancelled(chat_id, telegram_message_id)
      :error
    else
      Events.broadcast(thread_id, {:processing_error, message_id, reason})
      :error
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

  @max_tool_iterations 10

  defp call_llm(agent, messages, thread_id) do
    system_prompt = build_system_prompt(agent)
    llm_messages = build_llm_messages(system_prompt, messages)
    tools = ToolRegistry.get_tools(agent.enabled_tools)
    max_iterations = agent.max_iterations || @max_tool_iterations

    case LLM.complete(llm_messages, tools, model: agent.model) do
      {:ok, response} ->
        handle_llm_response(response, tools, llm_messages, agent, thread_id, 0, max_iterations)

      {:error, _} = error ->
        error
    end
  end

  defp build_system_prompt(agent) do
    SystemPrompt.build(agent)
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

  defp handle_llm_response(response, tools, llm_messages, agent, thread_id, iteration, max_iterations) do
    tool_calls = LLM.extract_tool_calls(response)

    cond do
      Enum.empty?(tool_calls) ->
        content = normalize_content(LLM.extract_content(response))

        {:ok, ensure_non_empty_content(content, response)}

      iteration >= max_iterations ->
        Logger.warning("Max tool iterations (#{max_iterations}) reached, returning partial response")
        content =
          LLM.extract_content(response) ||
            "I attempted to use tools but reached the maximum number of iterations."

        {:ok, ensure_non_empty_content(normalize_content(content), response)}

      true ->
        execute_tool_calls_and_continue(
          response,
          tool_calls,
          tools,
          llm_messages,
          agent,
          thread_id,
          iteration,
          max_iterations
        )
    end
  end

  defp execute_tool_calls_and_continue(
         response,
         tool_calls,
         tools,
         llm_messages,
         agent,
         thread_id,
         iteration,
         max_iterations
       ) do
    base_context =
      case response do
        %ReqLLM.Response{context: %ReqLLM.Context{} = ctx} -> ctx
        _ -> llm_messages
      end

    {updated_context, direct_response} =
      base_context
      |> maybe_append_assistant(response, tool_calls)
      |> append_tool_results(thread_id, tool_calls, tools, agent)

    if direct_response do
      {:ok, normalize_content(direct_response)}
    else
      case LLM.complete(updated_context, tools, model: agent.model) do
        {:ok, new_response} ->
          handle_llm_response(
            new_response,
            tools,
            updated_context,
            agent,
            thread_id,
            iteration + 1,
            max_iterations
          )

        {:error, _} = error ->
          error
      end
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

  defp append_tool_results(%Context{} = context, thread_id, tool_calls, tools, agent) do
    message_id = Process.get(:piano_message_id)

    Enum.reduce(tool_calls, {context, nil}, fn call, {ctx, direct_response} ->
      {name, id, args} = normalize_tool_call(call)
      Logger.debug("Executing tool #{name} with args: #{inspect(args)}")

      broadcast_tool_call(thread_id, message_id, name, args)

      result = execute_tool(name, args, tools, agent)
      apply_tool_result(ctx, direct_response, name, id, result)
    end)
  end

  defp broadcast_tool_call(thread_id, nil, name, args) do
    Events.broadcast(thread_id, {:tool_call, %{name: name, arguments: args}})
  end

  defp broadcast_tool_call(thread_id, message_id, name, args) do
    Events.broadcast(thread_id, {:tool_call, message_id, %{name: name, arguments: args}})
  end

  defp execute_tool(name, args, tools, agent) do
    case Enum.find(tools, fn t -> t.name == name end) do
      nil ->
        {:error, "Unknown tool: #{name}"}

      tool ->
        if ToolRegistry.requires_context?(name) do
          ToolRegistry.execute(name, args, %{agent: agent})
        else
          ReqLLM.Tool.execute(tool, args)
        end
    end
  end

  defp apply_tool_result(ctx, direct_response, name, id, {:ok, %{output: output, return_direct: true}}) do
    Logger.debug("Tool #{name} returned #{byte_size(to_string(output))} bytes (return_direct)")
    new_ctx = Context.append(ctx, Context.tool_result_message(name, id, output))
    {new_ctx, direct_response || output}
  end

  defp apply_tool_result(ctx, direct_response, name, id, {:ok, output}) do
    Logger.debug("Tool #{name} returned #{byte_size(to_string(output))} bytes")
    {Context.append(ctx, Context.tool_result_message(name, id, output)), direct_response}
  end

  defp apply_tool_result(ctx, direct_response, name, id, {:error, error}) do
    Logger.warning("Tool #{name} failed: #{inspect(error)}")
    {Context.append(ctx, Context.tool_result_message(name, id, %{error: inspect(error)})), direct_response}
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

  defp ensure_non_empty_content("", response) do
    log_llm_empty_response(response)
    empty_response_message(response)
  end

  defp ensure_non_empty_content(content, _response), do: content

  defp log_llm_empty_response(%Response{} = response) do
    Logger.warning(
      "LLM returned empty content (finish_reason=#{inspect(response.finish_reason)}, usage=#{inspect(response.usage)}, error=#{inspect(response.error)})"
    )
  end

  defp log_llm_empty_response(_response) do
    Logger.warning("LLM returned empty content (no response metadata)")
  end

  defp empty_response_message(%Response{} = response) do
    reason =
      case response.finish_reason do
        nil -> "unknown"
        reason -> to_string(reason)
      end

    "LLM returned empty content (finish_reason=#{reason})."
  end

  defp empty_response_message(_response), do: "LLM returned empty content."

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

  defp telegram_cancelled?(nil, _telegram_message_id), do: false
  defp telegram_cancelled?(_chat_id, nil), do: false

  defp telegram_cancelled?(chat_id, telegram_message_id) do
    case :ets.whereis(:piano_telegram_cancelled) do
      :undefined -> false
      _ -> :ets.member(:piano_telegram_cancelled, {chat_id, telegram_message_id})
    end
  end

  defp clear_telegram_cancelled(chat_id, telegram_message_id) do
    case :ets.whereis(:piano_telegram_cancelled) do
      :undefined -> :ok
      _ -> :ets.delete(:piano_telegram_cancelled, {chat_id, telegram_message_id})
    end
  end
end
