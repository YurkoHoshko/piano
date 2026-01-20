defmodule Piano.LLM do
  @moduledoc """
  LLM client for llama-swap backend using OpenAI-compatible API.
  """

  @callback complete(list(map()), list(map()), keyword()) ::
              {:ok, map()} | {:error, term()}

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
  @spec complete(list(map()), list(map()), keyword()) ::
          {:ok, map()} | {:error, term()}
  def complete(messages, tools \\ [], opts \\ []) do
    impl().complete(messages, tools, opts)
  end

  defp impl, do: Application.get_env(:piano, :llm_impl, Piano.LLM.Impl)

  @doc """
  Extracts the assistant's message content from an LLM response.
  """
  @spec extract_content(map()) :: String.t() | nil
  def extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    content
  end

  def extract_content(_), do: nil

  @doc """
  Extracts tool calls from an LLM response.
  """
  @spec extract_tool_calls(map()) :: list(map())
  def extract_tool_calls(%{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]})
      when is_list(tool_calls) do
    tool_calls
  end

  def extract_tool_calls(_), do: []
end

defmodule Piano.LLM.Impl do
  @moduledoc false
  @behaviour Piano.LLM

  require Logger

  @impl true
  def complete(messages, tools, opts) do
    config = Application.get_env(:piano, :llm, [])
    base_url = Keyword.get(config, :base_url, "http://localhost:8080")
    default_model = Keyword.get(config, :default_model, "qwen3:32b")
    model = Keyword.get(opts, :model, default_model)

    body =
      %{
        model: model,
        messages: messages
      }
      |> maybe_add_tools(tools)

    Logger.debug("LLM request to #{model} with #{length(messages)} messages")

    if Map.has_key?(body, :tools) do
      tool_names = Enum.map(body.tools, & &1.function.name)
      Logger.debug("Tools enabled: #{inspect(tool_names)}")
    end

    case Req.post("#{base_url}/v1/chat/completions",
           json: body,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        Logger.debug("LLM response received")
        {:ok, response_body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("LLM HTTP error: #{status}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("LLM request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) when is_list(tools) do
    formatted_tools =
      Enum.map(tools, fn tool ->
        %{
          type: "function",
          function: %{
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters
          }
        }
      end)

    body
    |> Map.put(:tools, formatted_tools)
    |> Map.put(:tool_choice, "auto")
  end
end
