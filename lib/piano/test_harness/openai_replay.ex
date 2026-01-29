defmodule Piano.TestHarness.OpenAIReplay do
  @moduledoc false

  def build(:chat_completions, response) when is_map(response) do
    model = response["model"] || "gpt-oss-120b"
    created = System.system_time(:second)
    usage = build_usage(response)
    message = build_chat_message(response)

    %{
      id: "chatcmpl-#{random_id()}",
      object: "chat.completion",
      created: created,
      model: model,
      choices: [
        %{
          index: 0,
          message: message,
          finish_reason: response["finish_reason"] || "stop"
        }
      ],
      usage: usage,
      timings: response["timings"] || default_timings(usage)
    }
  end

  def build(:responses, response) when is_map(response) do
    text = response["content"] || "Mock response"
    created_at = System.system_time(:second)
    message_id = "msg_#{random_id()}"

    %{
      id: "resp-#{random_id()}",
      object: "response",
      created_at: created_at,
      model: response["model"] || "gpt-4",
      status: response["status"] || "completed",
      error: nil,
      incomplete_details: nil,
      instructions: response["instructions"],
      max_output_tokens: response["max_output_tokens"],
      usage: %{
        input_tokens: response["prompt_tokens"] || 10,
        output_tokens: response["completion_tokens"] || 20,
        total_tokens: response["total_tokens"] || 30
      },
      output: [
        %{
          type: "message",
          id: message_id,
          status: "completed",
          role: "assistant",
          content: [
            %{
              type: "output_text",
              text: text,
              annotations: []
            }
          ]
        }
      ],
      parallel_tool_calls: response["parallel_tool_calls"],
      previous_response_id: response["previous_response_id"],
      reasoning: response["reasoning"],
      store: response["store"],
      temperature: response["temperature"],
      text: response["text"],
      tool_choice: response["tool_choice"],
      tools: response["tools"],
      top_p: response["top_p"],
      truncation: response["truncation"],
      metadata: response["metadata"],
      user: response["user"],
      completed_at: response["completed_at"] || created_at
    }
  end

  defp build_usage(response) do
    %{
      prompt_tokens: response["prompt_tokens"] || 10,
      completion_tokens: response["completion_tokens"] || 20,
      total_tokens: response["total_tokens"] || 30
    }
  end

  defp build_chat_message(%{"tool_calls" => tool_calls} = response) when is_list(tool_calls) and tool_calls != [] do
    %{
      role: "assistant",
      content: response["content"],
      tool_calls: Enum.map(tool_calls, &build_tool_call/1)
    }
  end

  defp build_chat_message(%{"content" => content}) do
    %{
      role: "assistant",
      content: content
    }
  end

  defp build_chat_message(response) do
    %{
      role: "assistant",
      content: response["content"] || "Mock response"
    }
  end

  def stream_events(response) when is_map(response) do
    response = normalize_map(response)
    text = extract_output_text(response) || ""
    output_item =
      case response["output"] do
        list when is_list(list) -> List.first(list) || %{}
        _ -> %{}
      end

    item_id = output_item["id"] || "msg-#{random_id()}"

    message_item = %{
      "type" => "message",
      "id" => item_id,
      "status" => "in_progress",
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

  def stream_chat_events(response) when is_map(response) do
    response = normalize_map(response)
    text = extract_chat_text(response)
    reasoning = response["reasoning_content"] || response["reasoning"]

    id = response["id"] || "chatcmpl-#{random_id()}"
    created = response["created"] || System.system_time(:second)
    model = response["model"] || "gpt-oss-120b"

    usage = %{
      "prompt_tokens" => response["prompt_tokens"] || 10,
      "completion_tokens" => response["completion_tokens"] || 20,
      "total_tokens" => response["total_tokens"] || 30
    }

    [
      %{
        "id" => id,
        "object" => "chat.completion.chunk",
        "created" => created,
        "model" => model,
        "choices" => [
          %{"index" => 0, "delta" => %{"role" => "assistant"}, "finish_reason" => nil}
        ],
        "usage" => usage
      },
      maybe_reasoning_chunk(id, created, model, reasoning, usage),
      maybe_content_chunk(id, created, model, text, usage),
      %{
        "id" => id,
        "object" => "chat.completion.chunk",
        "created" => created,
        "model" => model,
        "choices" => [
          %{"index" => 0, "delta" => %{}, "finish_reason" => "stop"}
        ],
        "timings" => default_timings(usage)
      }
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  def models do
    created = System.system_time(:second)

    models = [
      %{
        id: "gpt-oss-120b",
        name: "gpt-oss-120b",
        slug: "gpt-oss-120b",
        display_name: "gpt-oss-120b",
        supported_reasoning_levels: [],
        shell_type: "bash",
        created: created,
        object: "model",
        owned_by: "llama-swap"
      },
      %{
        id: "gpt-oss-20b",
        name: "gpt-oss-20b",
        slug: "gpt-oss-20b",
        display_name: "gpt-oss-20b",
        supported_reasoning_levels: [],
        shell_type: "bash",
        created: created,
        object: "model",
        owned_by: "llama-swap"
      }
    ]

    %{object: "list", data: models, models: models}
  end

  defp maybe_reasoning_chunk(_id, _created, _model, nil, _usage), do: nil
  defp maybe_reasoning_chunk(_id, _created, _model, "", _usage), do: nil

  defp maybe_reasoning_chunk(id, created, model, reasoning, usage) do
    %{
      "id" => id,
      "object" => "chat.completion.chunk",
      "created" => created,
      "model" => model,
      "choices" => [
        %{"index" => 0, "delta" => %{"reasoning_content" => reasoning}, "finish_reason" => nil}
      ],
      "usage" => usage
    }
  end

  defp maybe_content_chunk(_id, _created, _model, "", _usage), do: nil

  defp maybe_content_chunk(id, created, model, text, usage) do
    %{
      "id" => id,
      "object" => "chat.completion.chunk",
      "created" => created,
      "model" => model,
      "choices" => [
        %{"index" => 0, "delta" => %{"content" => text}, "finish_reason" => nil}
      ],
      "usage" => usage
    }
  end

  defp default_timings(%{prompt_tokens: prompt_tokens, completion_tokens: completion_tokens}) do
    %{
      "prompt_n" => max(prompt_tokens, 1),
      "prompt_ms" => 200.0,
      "prompt_per_token_ms" => 20.0,
      "prompt_per_second" => 50.0,
      "predicted_n" => max(completion_tokens, 1),
      "predicted_ms" => 50.0,
      "predicted_per_token_ms" => 25.0,
      "predicted_per_second" => 40.0,
      "n_ctx" => 32_768,
      "n_past" => max(prompt_tokens, 1)
    }
  end

  defp default_timings(%{"prompt_tokens" => prompt_tokens, "completion_tokens" => completion_tokens}) do
    default_timings(%{prompt_tokens: prompt_tokens, completion_tokens: completion_tokens})
  end

  defp extract_output_text(%{"output" => output}) when is_list(output) do
    output
    |> Enum.filter(&(&1["type"] == "message"))
    |> Enum.flat_map(&(&1["content"] || []))
    |> Enum.filter(&(&1["type"] in ["output_text", "text"]))
    |> Enum.map_join("", & &1["text"])
  end

  defp extract_output_text(_), do: nil

  defp extract_chat_text(%{"choices" => choices}) when is_list(choices) do
    choices
    |> List.first()
    |> Map.get("message", %{})
    |> Map.get("content")
  end

  defp extract_chat_text(%{"content" => text}) when is_binary(text), do: text
  defp extract_chat_text(_), do: ""

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
