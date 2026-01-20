defmodule Piano.LLM do
  @moduledoc """
  LLM client backed by ReqLLM.
  """

  @callback complete(ReqLLM.Context.t() | [ReqLLM.Message.t()], [ReqLLM.Tool.t()], keyword()) ::
              {:ok, ReqLLM.Response.t()} | {:error, term()}

  @doc """
  Sends a chat completion request to the LLM.

  ## Parameters
    - messages: List of message maps with :role and :content keys
    - tools: Optional list of tool definitions (OpenAI format)
    - opts: Optional keyword list with :model override

  ## Returns
    - {:ok, response_map} on success
    - {:error, reason} on failure
  """
  @spec complete(ReqLLM.Context.t() | [ReqLLM.Message.t()], [ReqLLM.Tool.t()], keyword()) ::
          {:ok, ReqLLM.Response.t()} | {:error, term()}
  def complete(context_or_messages, tools \\ [], opts \\ []) do
    impl().complete(context_or_messages, tools, opts)
  end

  defp impl, do: Application.get_env(:piano, :llm_impl, Piano.LLM.Impl)

  @doc """
  Extracts the assistant's message content from an LLM response.
  """
  @spec extract_content(ReqLLM.Response.t()) :: String.t() | nil
  def extract_content(%ReqLLM.Response{} = response) do
    ReqLLM.Response.text(response)
  end

  def extract_content(_), do: nil

  @doc """
  Extracts tool calls from an LLM response.
  """
  @spec extract_tool_calls(ReqLLM.Response.t()) :: list()
  def extract_tool_calls(%ReqLLM.Response{} = response) do
    ReqLLM.Response.tool_calls(response)
  end

  def extract_tool_calls(_), do: []
end

defmodule Piano.LLM.Impl do
  @moduledoc false
  @behaviour Piano.LLM

  require Logger

  @impl true
  def complete(context_or_messages, tools, opts) do
    config = Application.get_env(:piano, :llm, [])
    base_url = Keyword.get(config, :base_url, "http://localhost:8000")
    default_model = Keyword.get(config, :default_model, "gpt-oss-20b")
    provider = Keyword.get(config, :provider, "openai")
    api_key = Keyword.get(config, :api_key, System.get_env("LLM_API_KEY") || "local")
    max_tokens = Keyword.get(config, :max_tokens)
    model = Keyword.get(opts, :model, default_model)

    with {:ok, context} <- normalize_context(context_or_messages) do
      model_id = normalize_model_id(provider, model)

      Logger.debug(
        "LLM request to #{model_id} with #{length(context.messages)} messages (base_url=#{base_url})"
      )

      generation_opts =
        [
          tools: tools,
          tool_choice: "auto",
          base_url: base_url,
          api_key: api_key,
          receive_timeout: 120_000
        ]
        |> maybe_put_max_tokens(max_tokens)

      ReqLLM.generate_text(model_id, context, generation_opts)
      |> case do
        {:ok, _} = ok ->
          ok

        {:error, reason} = err ->
          Logger.error("LLM request failed (base_url=#{base_url}, model=#{model_id}): #{inspect(reason)}")
          err
      end
    end
  end

  defp normalize_context(%ReqLLM.Context{} = context), do: {:ok, context}
  defp normalize_context(messages) when is_list(messages), do: {:ok, ReqLLM.Context.new(messages)}
  defp normalize_context(prompt), do: ReqLLM.Context.normalize(prompt)

  defp maybe_put_max_tokens(opts, nil), do: opts
  defp maybe_put_max_tokens(opts, max_tokens), do: Keyword.put(opts, :max_tokens, max_tokens)

  defp normalize_model_id(provider, model) when is_binary(model) do
    if String.contains?(model, ":") do
      model
    else
      "#{provider}:#{model}"
    end
  end
end
