defmodule Piano.Tools.VoiceToolResource do
  @moduledoc """
  Ash resource wrapper for ASR (Automatic Speech Recognition) via vLLM.

  Exposes voice/audio transcription as an MCP tool that the agent can call
  to understand audio content from files sent by users.
  """

  use Ash.Resource, domain: nil

  alias Piano.Tools.TranscriptionClient

  actions do
    action :transcribe, :map do
      description "Transcribe an audio or voice file to text using ASR"

      argument :file_path, :string do
        allow_nil? false
        description "Path to the audio file to transcribe (local path or URL)"
      end

      argument :language, :string do
        description "Optional language hint (e.g., 'en', 'uk', 'es'). If not provided, auto-detect."
        default nil
      end

      run fn input, _ctx ->
        file_path = input.arguments.file_path
        language = input.arguments.language

        opts = if language, do: [language: language], else: []

        case TranscriptionClient.transcribe(file_path, opts) do
          {:ok, transcription} ->
            {:ok,
             %{
               transcription: transcription,
               file_path: file_path,
               language: language || "auto-detected"
             }}

          {:error, reason} ->
            {:error, "Transcription failed: #{inspect(reason)}"}
        end
      end
    end
  end
end
