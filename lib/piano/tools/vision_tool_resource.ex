defmodule Piano.Tools.VisionToolResource do
  @moduledoc """
  Ash resource wrapper for vision/image understanding via vLLM.

  Exposes image analysis as an MCP tool that the agent can call
  to understand image content from files sent by users.
  """

  use Ash.Resource, domain: nil

  alias Piano.Tools.VisionClient

  actions do
    action :analyze, :map do
      description "Analyze an image and answer a question about it using vision AI"

      argument :file_path, :string do
        allow_nil? false
        description "Path to the image file to analyze (local path or URL)"
      end

      argument :question, :string do
        allow_nil? false
        description "What you want to know about the image (e.g., 'What is shown in this image?', 'Extract the text from this image', 'Describe the diagram')"
      end

      run fn input, _ctx ->
        file_path = input.arguments.file_path
        question = input.arguments.question

        case VisionClient.analyze(file_path, question) do
          {:ok, response} ->
            {:ok,
             %{
               response: response,
               file_path: file_path,
               question: question
             }}

          {:error, reason} ->
            {:error, "Vision analysis failed: #{inspect(reason)}"}
        end
      end
    end

    action :describe, :map do
      description "Get a general description of an image"

      argument :file_path, :string do
        allow_nil? false
        description "Path to the image file to describe (local path or URL)"
      end

      run fn input, _ctx ->
        file_path = input.arguments.file_path

        case VisionClient.analyze(file_path, "Describe this image in detail.") do
          {:ok, response} ->
            {:ok,
             %{
               description: response,
               file_path: file_path
             }}

          {:error, reason} ->
            {:error, "Vision analysis failed: #{inspect(reason)}"}
        end
      end
    end

    action :extract_text, :map do
      description "Extract text/OCR from an image"

      argument :file_path, :string do
        allow_nil? false
        description "Path to the image file to extract text from"
      end

      run fn input, _ctx ->
        file_path = input.arguments.file_path

        case VisionClient.analyze(file_path, "Extract all text visible in this image. Return only the extracted text.") do
          {:ok, response} ->
            {:ok,
             %{
               extracted_text: response,
               file_path: file_path
             }}

          {:error, reason} ->
            {:error, "Text extraction failed: #{inspect(reason)}"}
        end
      end
    end
  end
end
