defmodule Piano.Tools.TranscriptionClient do
  @moduledoc """
  HTTP client for Qwen3-ASR transcription service via vLLM.

  Communicates with the transcription service (vLLM) using OpenAI-compatible API.
  """

  require Logger

  @default_base_url "http://llama-swap:8080/v1"
  @default_timeout 240_000

  @doc """
  Transcribe an audio file using the Qwen3-ASR service.

  ## Options
    * `:base_url` - Base URL of the transcription service (default: http://qwen-asr:8000/v1)
    * `:language` - Force specific language (e.g., "en", "zh"), or nil for auto-detect
    * `:timeout` - Request timeout in milliseconds (default: 60000)

  ## Examples
      {:ok, text} = TranscriptionClient.transcribe("/path/to/audio.ogg")
      {:ok, text} = TranscriptionClient.transcribe("/path/to/audio.ogg", language: "en")
  """
  @spec transcribe(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(file_path, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    language = Keyword.get(opts, :language)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Logger.info("Transcribing audio via API", file: file_path, language: language || "auto")

    # Read audio file
    case File.read(file_path) do
      {:ok, audio_data} ->
        # Encode to base64
        audio_base64 = Base.encode64(audio_data)

        # Build request
        request_body = build_request(audio_base64, language)

        # Make API call
        case make_api_call(base_url, request_body, timeout) do
          {:ok, response} ->
            {:ok, response}

          {:error, reason} ->
            Logger.error("Transcription API call failed", error: inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to read audio file", file: file_path, error: inspect(reason))
        {:error, "Failed to read audio file: #{inspect(reason)}"}
    end
  end

  @doc """
  Check if the transcription service is healthy and ready.
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

  defp build_request(audio_base64, language) do
    # Qwen3-ASR via vLLM accepts audio in base64 format
    # Using OpenAI-compatible chat completions API

    content = [
      %{
        "type" => "audio_url",
        "audio_url" => %{
          "url" => "data:audio/ogg;base64,#{audio_base64}"
        }
      }
    ]

    # Add language hint if specified
    content =
      if language do
        [%{"type" => "text", "text" => "Transcribe this audio in #{language}."} | content]
      else
        content
      end

    %{
      "model" => "qwen3-asr-0.6b",
      "messages" => [
        %{
          "role" => "user",
          "content" => content
        }
      ],
      "max_tokens" => 256,
      "temperature" => 0.0
    }
  end

  defp make_api_call(base_url, request_body, timeout) do
    url = "#{base_url}/chat/completions"

    case Req.post(url,
           json: request_body,
           headers: [{"Content-Type", "application/json"}],
           connect_options: [timeout: timeout]
         ) do
      {:ok, %{status: 200, body: body}} ->
        extract_transcription(body)

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned status #{status}: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp extract_transcription(%{"choices" => [%{"message" => %{"content" => text}} | _]}) do
    # Parse the response - Qwen3-ASR returns format like "Language: English\nText: ..."
    # or just the text directly

    transcription = parse_asr_output(text)
    {:ok, transcription}
  end

  defp extract_transcription(body) do
    {:error, "Unexpected API response format: #{inspect(body)}"}
  end

  # Parse ASR output to extract clean text
  # Qwen3-ASR returns formatted output like:
  # "Language: English\nText: Hello world"
  defp parse_asr_output(text) do
    lines = String.split(text, "\n")

    # Find the line starting with "Text:"
    text_line =
      Enum.find(lines, fn line ->
        String.starts_with?(line, "Text:") || String.starts_with?(line, "text:")
      end)

    if text_line do
      # Extract text after "Text:"
      text_line
      |> String.replace_prefix("Text:", "")
      |> String.replace_prefix("text:", "")
      |> String.trim()
    else
      # If no "Text:" prefix found, return the whole response
      # (might already be clean text)
      text |> String.trim()
    end
  end
end
