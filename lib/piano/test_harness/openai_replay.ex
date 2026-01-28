defmodule Piano.TestHarness.OpenAIReplay do
  @moduledoc false

  def build(:chat_completions, response) when is_map(response) do
    message =
      case response do
        %{"tool_calls" => tool_calls} when is_list(tool_calls) and tool_calls != [] ->
          %{
            role: "assistant",
            content: response["content"],
            tool_calls: Enum.map(tool_calls, &build_tool_call/1)
          }

        %{"content" => _} ->
          %{
            role: "assistant",
            content: response["content"]
          }

        _ ->
          %{
            role: "assistant",
            content: response["content"] || "Mock response"
          }
      end

    %{
      id: "chatcmpl-#{random_id()}",
      object: "chat.completion",
      created: System.system_time(:second),
      model: response["model"] || "gpt-4",
      choices: [
        %{
          index: 0,
          message: message,
          finish_reason: response["finish_reason"] || "stop"
        }
      ],
      usage: %{
        prompt_tokens: response["prompt_tokens"] || 10,
        completion_tokens: response["completion_tokens"] || 20,
        total_tokens: response["total_tokens"] || 30
      }
    }
  end

  def build(:responses, response) when is_map(response) do
    text = response["content"] || "Mock response"

    %{
      id: "resp-#{random_id()}",
      object: "response",
      created_at: System.system_time(:second),
      status: response["status"] || "completed",
      output_text: text,
      output: [
        %{
          type: "message",
          id: "msg-#{random_id()}",
          role: "assistant",
          content: [
            %{
              type: "output_text",
              text: text
            }
          ]
        }
      ]
    }
  end

  def stream_events(response) when is_map(response) do
    response = normalize_map(response)
    text = response["output_text"] || extract_output_text(response) || ""
    output_item =
      case response["output"] do
        list when is_list(list) -> List.first(list) || %{}
        _ -> %{}
      end

    item_id = output_item["id"] || "msg-#{random_id()}"

    message_item = %{
      "type" => "message",
      "id" => item_id,
      "role" => "assistant",
      "content" => [
        %{
          "type" => "output_text",
          "text" => ""
        }
      ]
    }

    events =
      []
      |> add_event(%{"type" => "response.created", "response" => response})
      |> add_event(%{"type" => "response.output_item.added", "output_index" => 0, "item" => message_item})
      |> add_event(%{
        "type" => "response.content_part.added",
        "item_id" => item_id,
        "output_index" => 0,
        "content_index" => 0,
        "part" => %{"type" => "output_text", "text" => ""}
      })
      |> maybe_add_text_events(item_id, text)
      |> add_event(%{
        "type" => "response.content_part.done",
        "item_id" => item_id,
        "output_index" => 0,
        "content_index" => 0,
        "part" => %{"type" => "output_text", "text" => text}
      })
      |> add_event(%{"type" => "response.output_item.done", "output_index" => 0, "item" => output_item})
      |> add_event(%{"type" => "response.completed", "response" => response})

    Enum.with_index(events, fn event, idx ->
      Map.put(event, "sequence_number", idx)
    end)
  end

  def models do
    %{
      object: "list",
      data: [
        %{id: "gpt-4", object: "model", owned_by: "openai"},
        %{id: "o3", object: "model", owned_by: "openai"}
      ]
    }
  end

  defp extract_output_text(%{"output" => output}) when is_list(output) do
    output
    |> Enum.filter(&(&1["type"] == "message"))
    |> Enum.flat_map(&(&1["content"] || []))
    |> Enum.filter(&(&1["type"] in ["output_text", "text"]))
    |> Enum.map(& &1["text"])
    |> Enum.join("")
  end

  defp extract_output_text(_), do: nil

  defp add_event(events, event), do: events ++ [event]

  defp maybe_add_text_events(events, _item_id, ""), do: events

  defp maybe_add_text_events(events, item_id, text) do
    events
    |> add_event(%{
      "type" => "response.output_text.delta",
      "item_id" => item_id,
      "output_index" => 0,
      "content_index" => 0,
      "delta" => text
    })
    |> add_event(%{
      "type" => "response.output_text.done",
      "item_id" => item_id,
      "output_index" => 0,
      "content_index" => 0,
      "text" => text
    })
  end

  defp normalize_map(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_map(v)} end)
    |> Map.new()
  end

  defp normalize_map(value) when is_list(value), do: Enum.map(value, &normalize_map/1)
  defp normalize_map(value), do: value

  defp build_tool_call(tool_call) do
    tool_call =
      case tool_call do
        %{} -> tool_call
        other -> %{"name" => other}
      end

    %{
      id: "call_#{random_id()}",
      type: "function",
      function: %{
        name: tool_call["name"],
        arguments: Jason.encode!(tool_call["arguments"] || %{})
      }
    }
  end

  defp random_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end
end
