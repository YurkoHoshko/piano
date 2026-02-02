defmodule Piano.Tools.TranscriptionClient do
  @moduledoc """
  HTTP client for Qwen3-ASR transcription service via vLLM.

  Communicates with the transcription service (vLLM) using OpenAI-compatible API.
  """

  require Logger

  @default_base_url "http://llama-swap:8080/v1"
  @default_timeout 240_000

  @doc """
  Transcribe an audio file or URL using the Qwen3-ASR service.

  Supports both local file paths and URLs (http/https).

  ## Options
    * `:base_url` - Base URL of the transcription service (default: http://llama-swap:8080/v1)
    * `:language` - Force specific language (e.g., "en", "zh"), or nil for auto-detect
    * `:timeout` - Request timeout in milliseconds (default: 240000)

  ## Examples
      {:ok, text} = TranscriptionClient.transcribe("/path/to/audio.ogg")
      {:ok, text} = TranscriptionClient.transcribe("/path/to/audio.ogg", language: "en")
      {:ok, text} = TranscriptionClient.transcribe("https://example.com/audio.wav")
  """
  @spec transcribe(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(file_path_or_url, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    language = Keyword.get(opts, :language)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Logger.info("Transcribing audio via API",
      file: file_path_or_url,
      language: language || "auto"
    )

    make_transcription_call(base_url, file_path_or_url, language, timeout)
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

  # Get local file path - download if URL
  defp ensure_local_file(path_or_url) do
    cond do
      String.starts_with?(path_or_url, "http://") or String.starts_with?(path_or_url, "https://") ->
        # URL - download to temp file
        case download_to_temp(path_or_url) do
          {:ok, temp_path} -> {:ok, temp_path, true}
          {:error, reason} -> {:error, "Failed to download audio: #{inspect(reason)}"}
        end

      File.exists?(path_or_url) ->
        # Local file - use directly
        {:ok, path_or_url, false}

      true ->
        {:error, "Audio file not found: #{path_or_url}"}
    end
  end

  defp download_to_temp(url) do
    Logger.info("Downloading audio from URL", url: url)
    filename = get_filename(url)

    temp_path =
      Path.join(
        System.tmp_dir!(),
        "piano_asr_dl_#{System.unique_integer([:positive])}_#{filename}"
      )

    case Req.get(url,
           connect_options: [timeout: 60_000],
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        case File.write(temp_path, body) do
          :ok -> {:ok, temp_path}
          {:error, reason} -> {:error, "Failed to write temp file: #{inspect(reason)}"}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, error} ->
        {:error, error}
    end
  end

  # Get filename from path or URL
  defp get_filename(path_or_url) do
    path_or_url
    |> URI.parse()
    |> Map.get(:path, path_or_url)
    |> Path.basename()
    |> case do
      "" -> "audio.wav"
      name -> name
    end
  end

  defp make_transcription_call(base_url, path_or_url, language, timeout) do
    url = "#{base_url}/audio/transcriptions"

    with {:ok, file_path, is_temp} <- ensure_local_file(path_or_url),
         {:ok, file_contents} <- File.read(file_path) do
      # Successfully got file contents, proceed with API call
      try do
        filename = Path.basename(file_path)

        # Build multipart form using Multipart library
        multipart =
          Multipart.new()
          |> Multipart.add_part(Multipart.Part.text_field("qwen3-asr-0.6b", "model"))
          |> Multipart.add_part(Multipart.Part.text_field("json", "response_format"))
          |> Multipart.add_part(
            Multipart.Part.file_content_field(filename, file_contents, :file, filename: filename)
          )

        # Add language if specified
        multipart =
          if language do
            Multipart.add_part(multipart, Multipart.Part.text_field(language, "language"))
          else
            multipart
          end

        content_length = Multipart.content_length(multipart)
        content_type = Multipart.content_type(multipart, "multipart/form-data")

        headers = [
          {"Content-Type", content_type},
          {"Content-Length", to_string(content_length)}
        ]

        Logger.info("Making transcription API call",
          url: url,
          filename: filename,
          language: language || "auto",
          content_length: content_length
        )

        case Req.post(url,
               headers: headers,
               body: Multipart.body_stream(multipart),
               connect_options: [timeout: timeout],
               receive_timeout: timeout
             ) do
          {:ok, %{status: 200, body: body}} ->
            extract_transcription(body)

          {:ok, %{status: status, body: body}} ->
            Logger.error("Transcription API error", status: status, body: inspect(body))
            {:error, "API returned status #{status}: #{inspect(body)}"}

          {:error, error} ->
            Logger.error("Transcription request failed", error: inspect(error))
            {:error, "Request failed: #{inspect(error)}"}
        end
      after
        # Clean up temp file if we downloaded it
        if is_temp do
          File.rm(file_path)
        end
      end
    else
      {:error, reason} = error ->
        Logger.error("Transcription file preparation failed",
          path_or_url: path_or_url,
          reason: inspect(reason)
        )

        error
    end
  end

  defp extract_transcription(%{"text" => text}) when is_binary(text) do
    {:ok, String.trim(text)}
  end

  defp extract_transcription(body) do
    Logger.error("Unexpected transcription response format", body: inspect(body))
    {:error, "Unexpected API response format: #{inspect(body)}"}
  end
end
