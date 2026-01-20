defmodule Piano.LLMTest do
  use ExUnit.Case, async: true

  alias Piano.LLM

  describe "extract_content/1" do
    test "extracts content from ReqLLM response" do
      msg = ReqLLM.Context.assistant("Hello, world!")
      response = %ReqLLM.Response{message: msg, context: ReqLLM.Context.new([msg])}

      assert LLM.extract_content(response) == "Hello, world!"
    end

    test "returns nil for non-response input" do
      assert LLM.extract_content(%{}) == nil
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from ReqLLM response" do
      call = ReqLLM.ToolCall.new("call_123", "read_file", ~s({"path":"/tmp/test.txt"}))
      msg = ReqLLM.Context.assistant("", tool_calls: [call])
      response = %ReqLLM.Response{message: msg, context: ReqLLM.Context.new([msg])}

      tool_calls = LLM.extract_tool_calls(response)
      assert length(tool_calls) == 1
      assert hd(tool_calls).function.name == "read_file"
    end

    test "returns empty list when no tool calls" do
      msg = ReqLLM.Context.assistant("No tools needed")
      response = %ReqLLM.Response{message: msg, context: ReqLLM.Context.new([msg])}

      assert LLM.extract_tool_calls(response) == []
    end
  end
end
