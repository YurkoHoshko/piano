defmodule Piano.LLM do
  @moduledoc """
  LLM client for llama-swap backend using OpenAI-compatible API.
  """

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

    case Req.post("#{base_url}/v1/chat/completions",
           json: body,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
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

    Map.put(body, :tools, formatted_tools)
  end

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
