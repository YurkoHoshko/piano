defmodule Piano.Telegram.TranscriptTest do
  use ExUnit.Case, async: true

  alias Piano.Telegram.Transcript

  test "format_transcript does not indent turns (no code block)" do
    md =
      Transcript.format_transcript(%{
        "thread" => %{"id" => "thr_1"},
        "turns" => [
          %{
            "id" => "turn-1",
            "items" => [
              %{
                "type" => "userMessage",
                "content" => [%{"type" => "input_text", "text" => "Hey"}]
              },
              %{
                "type" => "agentMessage",
                "content" => [%{"type" => "output_text", "text" => "Hello"}]
              }
            ]
          }
        ]
      })

    assert md =~ "## Turn 1"
    assert md =~ "**User:**\nHey"
    assert md =~ "**Agent:**\nHello"
    refute md =~ "\n    ## Turn"
  end
end
