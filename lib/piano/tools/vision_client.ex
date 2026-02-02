defmodule Piano.Tools.VisionClient do
  @moduledoc """
  HTTP client for vision/image understanding via vLLM.

  Communicates with the vision model using OpenAI-compatible API.
  """

  require Logger

  @default_base_url "http://llama-swap:8080/v1"
  @default_model "qwen3-vl-4b-vllm"
  @default_timeout 240_000

  @doc """
  Analyze an image and answer a question about it.

  ## Options
    * `:base_url` - Base URL of the vision service (default: http://llama-swap:8080/v1)
    * `:model` - Model to use (default: gemma3)
    * `:timeout` - Request timeout in milliseconds (default: 60000)
    * `:max_tokens` - Maximum tokens in response (default: 1024)

  ## Examples
      {:ok, response} = VisionClient.analyze("/path/to/image.jpg", "What is in this image?")
      {:ok, response} = VisionClient.analyze("https://example.com/image.png", "Describe the diagram")
  """
  @spec analyze(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def analyze(file_path_or_url, question, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    model = Keyword.get(opts, :model, @default_model)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_tokens = Keyword.get(opts, :max_tokens, 1024)

    Logger.info("Analyzing image via Vision API",
      file: file_path_or_url,
      question: String.slice(question, 0, 100)
    )

    case build_image_content(file_path_or_url) do
      {:ok, image_content} ->
        request_body = build_request(image_content, question, model, max_tokens)
        make_api_call(base_url, request_body, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if the vision service is healthy.
  """
  @spec healthy?(keyword()) :: boolean()
  def healthy?(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    health_url = base_url |> String.replace("/v1", "") |> Kernel.<>("/health")

    case Req.get(health_url, connect_options: [timeout: 240_000]) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  # Private functions

  defp build_image_content(path_or_url) do
    cond do
      String.starts_with?(path_or_url, "http://") or String.starts_with?(path_or_url, "https://") ->
        # URL - use directly
        {:ok,
         %{
           "type" => "image_url",
           "image_url" => %{"url" => path_or_url}
         }}

      File.exists?(path_or_url) ->
        # Local file - read and encode as base64
        case File.read(path_or_url) do
          {:ok, data} ->
            mime_type = guess_mime_type(path_or_url)
            base64_data = Base.encode64(data)

            {:ok,
             %{
               "type" => "image_url",
               "image_url" => %{"url" => "data:#{mime_type};base64,#{base64_data}"}
             }}

          {:error, reason} ->
            {:error, "Failed to read image file: #{inspect(reason)}"}
        end

      true ->
        {:error, "File not found: #{path_or_url}"}
    end
  end

  defp guess_mime_type(path) do
    case Path.extname(path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".bmp" -> "image/bmp"
      _ -> "image/jpeg"
    end
  end

  defp build_request(image_content, question, model, max_tokens) do
    %{
      "model" => model,
      "messages" => [
        %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => question},
            image_content
          ]
        }
      ],
      "max_tokens" => max_tokens,
      "temperature" => 0.3
    }
  end

  defp make_api_call(base_url, request_body, timeout) do
    url = "#{base_url}/chat/completions"

    case Req.post(url,
           json: request_body,
           headers: [{"Content-Type", "application/json"}],
           connect_options: [timeout: timeout],
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: body}} ->
        extract_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned status #{status}: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp extract_response(%{"choices" => [%{"message" => %{"content" => text}} | _]}) do
    {:ok, String.trim(text)}
  end

  defp extract_response(body) do
    {:error, "Unexpected API response format: #{inspect(body)}"}
  end
end
