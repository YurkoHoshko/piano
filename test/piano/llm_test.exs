defmodule Piano.LLMTest do
  use ExUnit.Case, async: true

  alias Piano.LLM

  describe "extract_content/1" do
    test "extracts content from valid response" do
      response = %{
        "choices" => [
          %{"message" => %{"content" => "Hello, world!"}}
        ]
      }

      assert LLM.extract_content(response) == "Hello, world!"
    end

    test "returns nil for empty response" do
      assert LLM.extract_content(%{}) == nil
    end

    test "returns nil for response without choices" do
      assert LLM.extract_content(%{"choices" => []}) == nil
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from response" do
      response = %{
        "choices" => [
          %{
            "message" => %{
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "function" => %{
                    "name" => "read_file",
                    "arguments" => "{\"path\": \"/tmp/test.txt\"}"
                  }
                }
              ]
            }
          }
        ]
      }

      tool_calls = LLM.extract_tool_calls(response)
      assert length(tool_calls) == 1
      assert hd(tool_calls)["function"]["name"] == "read_file"
    end

    test "returns empty list when no tool calls" do
      response = %{
        "choices" => [
          %{"message" => %{"content" => "No tools needed"}}
        ]
      }

      assert LLM.extract_tool_calls(response) == []
    end
  end

  describe "tool formatting" do
    test "tools are formatted per OpenAI spec" do
      tools = [
        %{
          name: "read_file",
          description: "Read contents of a file",
          parameters: %{
            type: "object",
            properties: %{
              path: %{type: "string", description: "File path"}
            },
            required: ["path"]
          }
        }
      ]

      body = %{model: "test", messages: []}

      formatted =
        body
        |> Map.put(:tools, format_tools(tools))
        |> Map.put(:tool_choice, "auto")

      assert Map.has_key?(formatted, :tools)
      assert Map.has_key?(formatted, :tool_choice)
      assert formatted.tool_choice == "auto"

      [tool] = formatted.tools
      assert tool.type == "function"
      assert tool.function.name == "read_file"
      assert tool.function.description == "Read contents of a file"
      assert Map.has_key?(tool.function, :parameters)
    end
  end

  defp format_tools(tools) do
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
  end
end
