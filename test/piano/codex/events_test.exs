defmodule Piano.Codex.EventsTest do
  use ExUnit.Case, async: true

  alias Piano.Codex.Events

  describe "map_item_type/1" do
    test "maps Codex string types to atoms" do
      assert Events.map_item_type("userMessage") == :user_message
      assert Events.map_item_type("agentMessage") == :agent_message
      assert Events.map_item_type("reasoning") == :reasoning
      assert Events.map_item_type("commandExecution") == :command_execution
      assert Events.map_item_type("fileChange") == :file_change
      assert Events.map_item_type("mcpToolCall") == :mcp_tool_call
      assert Events.map_item_type("webSearch") == :web_search
      assert Events.map_item_type("collabToolCall") == :collab_tool_call
      assert Events.map_item_type("imageView") == :image_view
      assert Events.map_item_type("enteredReviewMode") == :review_mode
      assert Events.map_item_type("exitedReviewMode") == :review_mode
      assert Events.map_item_type("compacted") == :compacted
    end

    test "returns :unknown for unknown types" do
      assert Events.map_item_type("unknownType") == :unknown
      assert Events.map_item_type(nil) == :unknown
      assert Events.map_item_type(123) == :unknown
    end

    test "passes through existing atoms" do
      assert Events.map_item_type(:user_message) == :user_message
      assert Events.map_item_type(:reasoning) == :reasoning
    end
  end

  describe "extract_turn_id/1" do
    test "extracts turn_id from top level" do
      assert Events.extract_turn_id(%{"turnId" => "turn_123"}) == "turn_123"
    end

    test "returns nil when no turn_id found" do
      assert Events.extract_turn_id(%{}) == nil
      assert Events.extract_turn_id(%{"other" => "value"}) == nil
    end
  end

  describe "extract_thread_id/1" do
    test "extracts thread_id from top level" do
      assert Events.extract_thread_id(%{"threadId" => "thr_123"}) == "thr_123"
    end

    test "returns nil when no thread_id found" do
      assert Events.extract_thread_id(%{}) == nil
    end
  end

  describe "extract_text_from_content/1" do
    test "extracts text from content array" do
      content = [
        %{"type" => "text", "text" => "Hello "},
        %{"type" => "outputText", "text" => "world"}
      ]

      assert Events.extract_text_from_content(content) == "Hello world"
    end

    test "handles inputText type" do
      content = [%{"type" => "inputText", "text" => "User input"}]
      assert Events.extract_text_from_content(content) == "User input"
    end

    test "extracts text from map" do
      assert Events.extract_text_from_content(%{"text" => "Direct text"}) == "Direct text"
      assert Events.extract_text_from_content(%{"text" => "Atom key"}) == "Atom key"
    end

    test "returns string as-is" do
      assert Events.extract_text_from_content("plain string") == "plain string"
    end

    test "returns nil for nil or unknown" do
      assert Events.extract_text_from_content(nil) == nil
      assert Events.extract_text_from_content(%{"other" => "value"}) == nil
    end
  end

  describe "parse/1 - Turn events" do
    test "parses turn/started event" do
      raw = %{
        "method" => "turn/started",
        "params" => %{
          "turnId" => "turn_123",
          "threadId" => "thr_456",
          "turn" => %{
            "input" => [%{"type" => "text", "text" => "Hello"}]
          }
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.TurnStarted{} = event
      assert event.turn_id == "turn_123"
      assert event.thread_id == "thr_456"
      assert event.input_items == [%{"type" => "text", "text" => "Hello"}]
    end

    test "parses turn/completed event" do
      raw = %{
        "method" => "turn/completed",
        "params" => %{
          "turnId" => "turn_123",
          "threadId" => "thr_456",
          "status" => "completed",
          "turn" => %{
            "usage" => %{
              "inputTokens" => 100,
              "outputTokens" => 50,
              "totalTokens" => 150
            }
          }
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.TurnCompleted{} = event
      assert event.turn_id == "turn_123"
      assert event.status == :completed
      assert event.usage.input_tokens == 100
      assert event.usage.output_tokens == 50
      assert event.usage.total_tokens == 150
    end

    test "parses turn/completed with failed status" do
      raw = %{
        "method" => "turn/completed",
        "params" => %{
          "turnId" => "turn_123",
          "turn" => %{
            "status" => "failed",
            "error" => %{"message" => "Something went wrong"}
          }
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.TurnCompleted{} = event
      assert event.status == :failed
      assert event.error == %{"message" => "Something went wrong"}
    end

    test "parses turn/diff/updated event" do
      raw = %{
        "method" => "turn/diff/updated",
        "params" => %{
          "turnId" => "turn_123",
          "diff" => "diff content"
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.TurnDiffUpdated{} = event
      assert event.diff == "diff content"
    end

    test "parses turn/plan/updated event" do
      raw = %{
        "method" => "turn/plan/updated",
        "params" => %{
          "turnId" => "turn_123",
          "plan" => %{"steps" => [%{"action" => "search"}]}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.TurnPlanUpdated{} = event
      assert event.plan == %{"steps" => [%{"action" => "search"}]}
    end
  end

  describe "parse/1 - Item events" do
    test "parses item/started event" do
      raw = %{
        "method" => "item/started",
        "params" => %{
          "item" => %{
            "id" => "item_123",
            "type" => "commandExecution",
            "turnId" => "turn_456"
          }
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ItemStarted{} = event
      assert event.item_id == "item_123"
      assert event.type == :command_execution
      assert event.turn_id == "turn_456"
    end

    test "parses item/completed event" do
      raw = %{
        "method" => "item/completed",
        "params" => %{
          "item" => %{
            "id" => "item_123",
            "type" => "fileChange",
            "status" => "completed"
          },
          "result" => %{"path" => "/tmp/test.txt"}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ItemCompleted{} = event
      assert event.item_id == "item_123"
      assert event.type == :file_change
      assert event.status == :completed
      assert event.result == %{"path" => "/tmp/test.txt"}
    end

    test "parses item/completed with declined status" do
      raw = %{
        "method" => "item/completed",
        "params" => %{
          "item" => %{
            "id" => "item_123",
            "type" => "commandExecution",
            "status" => "declined"
          }
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ItemCompleted{} = event
      assert event.status == :declined
    end

    test "parses item/agentMessage/delta event" do
      raw = %{
        "method" => "item/agentMessage/delta",
        "params" => %{
          "itemId" => "item_123",
          "turnId" => "turn_456",
          "delta" => "partial text"
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.AgentMessageDelta{} = event
      assert event.item_id == "item_123"
      assert event.delta == "partial text"
    end

    test "parses item/reasoning/textDelta event" do
      raw = %{
        "method" => "item/reasoning/textDelta",
        "params" => %{
          "itemId" => "item_123",
          "delta" => "reasoning text"
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ReasoningDelta{} = event
      assert event.delta == "reasoning text"
    end
  end

  describe "parse/1 - Thread events" do
    test "parses thread/started event" do
      raw = %{
        "method" => "thread/started",
        "params" => %{
          "thread" => %{"id" => "thr_123"}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ThreadStarted{} = event
      assert event.thread_id == "thr_123"
    end

    test "parses thread/archived event" do
      raw = %{
        "method" => "thread/archived",
        "params" => %{
          "thread" => %{"id" => "thr_123"}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ThreadArchived{} = event
      assert event.thread_id == "thr_123"
    end

    test "parses thread/tokenUsage/updated event" do
      raw = %{
        "method" => "thread/tokenUsage/updated",
        "params" => %{
          "threadId" => "thr_123",
          "usage" => %{"inputTokens" => 1000}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ThreadTokenUsageUpdated{} = event
      assert event.thread_id == "thr_123"
      assert event.usage.input_tokens == 1000
    end
  end

  describe "parse/1 - Account events" do
    test "parses account/updated event" do
      raw = %{
        "method" => "account/updated",
        "params" => %{
          "account" => %{"type" => "apiKey"}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.AccountUpdated{} = event
      assert event.account == %{"type" => "apiKey"}
    end

    test "parses account/login/completed event" do
      raw = %{
        "method" => "account/login/completed",
        "params" => %{
          "account" => %{"type" => "chatgpt"}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.AccountLoginCompleted{} = event
    end

    test "parses account/rateLimits/updated event" do
      raw = %{
        "method" => "account/rateLimits/updated",
        "params" => %{
          "rateLimits" => %{"usedPercent" => 50}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.AccountRateLimitsUpdated{} = event
      assert event.rate_limits == %{"usedPercent" => 50}
    end
  end

  describe "parse/1 - Approval events" do
    test "parses commandExecution/requestApproval event" do
      raw = %{
        "method" => "item/commandExecution/requestApproval",
        "params" => %{
          "itemId" => "item_123",
          "turnId" => "turn_456",
          "command" => ["rm", "-rf", "/"],
          "reason" => "Dangerous command"
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.CommandExecutionRequestApproval{} = event
      assert event.item_id == "item_123"
      assert event.command == ["rm", "-rf", "/"]
      assert event.reason == "Dangerous command"
    end

    test "parses fileChange/requestApproval event" do
      raw = %{
        "method" => "item/fileChange/requestApproval",
        "params" => %{
          "itemId" => "item_123",
          "path" => "/etc/passwd",
          "reason" => "System file"
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.FileChangeRequestApproval{} = event
      assert event.path == "/etc/passwd"
    end
  end

  describe "parse/1 - Legacy v1 events" do
    test "parses codex/event/task_started as turn/started" do
      raw = %{
        "method" => "codex/event/task_started",
        "params" => %{
          "turnId" => "turn_123"
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.TurnStarted{} = event
      assert event.turn_id == "turn_123"
    end

    test "parses codex/event/item_completed as item/completed" do
      raw = %{
        "method" => "codex/event/item_completed",
        "params" => %{
          "item" => %{"id" => "item_123", "type" => "agentMessage"}
        }
      }

      assert {:ok, event} = Events.parse(raw)
      assert %Events.ItemCompleted{} = event
      assert event.type == :agent_message
    end
  end

  describe "parse/1 - Error handling" do
    test "returns error for unknown event method" do
      raw = %{
        "method" => "unknown/method",
        "params" => %{}
      }

      assert {:error, {:unknown_event_method, "unknown/method", %{}}} = Events.parse(raw)
    end

    test "returns error for invalid event structure" do
      assert {:error, {:invalid_event, "not a map"}} = Events.parse("not a map")
      assert {:error, {:invalid_event, %{}}} = Events.parse(%{})
    end
  end

  describe "TokenUsage struct" do
    test "has correct fields" do
      usage = %Events.TokenUsage{
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      }

      assert usage.input_tokens == 100
      assert usage.output_tokens == 50
      assert usage.total_tokens == 150
    end
  end
end
