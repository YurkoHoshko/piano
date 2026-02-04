#!/usr/bin/env elixir

# Test script for @.agents/github-tools agent
# Run with: mix run test_github_tools_agent.exs

require Logger

alias Piano.Mock.Surface, as: MockSurface
alias Piano.Core.Interaction
alias Piano.Core.InteractionItem
alias Piano.Core.Thread
alias Piano.Codex

defmodule TestHarness do
  @moduledoc """
  Test harness for github-tools agent testing
  """

  def run_test do
    IO.puts("=" |> String.duplicate(70))
    IO.puts("GitHub Tools Agent Test Script")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    # Step 1: Initialize test environment
    IO.puts("Step 1: Initializing test environment...")
    :ok = initialize_app()
    IO.puts("  App initialized successfully")
    IO.puts("")

    # Step 2: Start mock surface
    mock_id = "github-tools-test-#{System.unique_integer([:positive])}"
    IO.puts("Step 2: Starting mock surface...")
    IO.puts("  Mock ID: #{mock_id}")

    {:ok, _surface} = MockSurface.start(mock_id)
    reply_to = MockSurface.build_reply_to(mock_id)
    IO.puts("  Reply to: #{reply_to}")
    IO.puts("")

    # Step 3: Create thread for the mock surface
    IO.puts("Step 3: Creating thread for mock surface...")
    {:ok, thread} = Ash.create(Thread, %{reply_to: reply_to})
    IO.puts("  Thread ID: #{thread.id}")
    IO.puts("")

    # Step 4: Create interaction with github-tools command
    IO.puts("Step 4: Creating interaction with test command...")

    test_message =
      "Run the github-tools agent to fetch starred repositories for user 'torvalds' using: mise exec -- uv run python starred_repos.py torvalds"

    {:ok, interaction} =
      Ash.create(Interaction, %{
        original_message: test_message,
        reply_to: reply_to,
        thread_id: thread.id
      })

    IO.puts("  Interaction ID: #{interaction.id}")
    IO.puts("  Message: #{test_message}")
    IO.puts("")

    # Step 5: Start the turn
    IO.puts("Step 5: Starting Codex turn...")

    case Codex.start_turn(interaction) do
      {:ok, started_interaction} ->
        IO.puts("  Turn started successfully")
        IO.puts("  Interaction status: #{started_interaction.status}")
        IO.puts("")

        # Step 6: Wait for completion
        IO.puts("Step 6: Waiting for completion...")
        wait_for_completion(started_interaction.id, 300)

      {:error, reason} ->
        IO.puts("  ERROR: Failed to start turn")
        IO.puts("  Reason: #{inspect(reason)}")
    end

    IO.puts("")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("Step 7: Collecting results from mock surface...")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    results = MockSurface.get_results(mock_id)
    display_mock_results(results)

    IO.puts("")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("Step 8: Querying database for interaction records...")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    query_database_records(interaction.id)

    IO.puts("")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("Step 9: Checking for mise/ett issues...")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    check_for_issues(results, interaction.id)

    IO.puts("")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("Test Summary")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    print_summary(interaction.id, results)

    # Cleanup
    MockSurface.stop(mock_id)
    IO.puts("")
    IO.puts("Mock surface cleaned up")
    IO.puts("Test complete!")
  end

  defp initialize_app do
    # Ensure the piano app is started
    case Application.ensure_all_started(:piano) do
      {:ok, _} -> :ok
      {:error, {:already_started, :piano}} -> :ok
      {:error, reason} -> raise "Failed to start piano: #{inspect(reason)}"
    end
  end

  defp wait_for_completion(interaction_id, attempts_remaining) when attempts_remaining > 0 do
    case Ash.get(Interaction, interaction_id) do
      {:ok, %{status: status} = interaction} when status in [:complete, :failed, :interrupted] ->
        IO.puts("  Completion detected!")
        IO.puts("  Final status: #{status}")
        IO.puts("  Response: #{inspect(interaction.response)}")
        :ok

      {:ok, %{status: status}} ->
        IO.write(".")
        Process.sleep(500)
        wait_for_completion(interaction_id, attempts_remaining - 1)

      {:error, reason} ->
        IO.puts("  Error querying interaction: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp wait_for_completion(_interaction_id, 0) do
    IO.puts("")
    IO.puts("  WARNING: Timeout waiting for completion")
    {:error, :timeout}
  end

  defp display_mock_results(results) when is_list(results) do
    if Enum.empty?(results) do
      IO.puts("No events recorded in mock surface")
    else
      IO.puts("Recorded #{length(results)} events:")
      IO.puts("")

      results
      |> Enum.with_index(1)
      |> Enum.each(fn {event, index} ->
        IO.puts("  Event #{index}: #{event.type}")
        IO.puts("    Timestamp: #{event.timestamp}")

        case event.type do
          :turn_started ->
            IO.puts("    Turn started")

          :turn_completed ->
            IO.puts("    Turn completed")

            if get_in(event.data, [:params, "turn", "output"]) do
              output = get_in(event.data, [:params, "turn", "output"])
              IO.puts("    Output: #{inspect(output, limit: 200)}")
            end

          :item_started ->
            IO.puts("    Item started")

            if get_in(event.data, [:params, "item", "type"]) do
              item_type = get_in(event.data, [:params, "item", "type"])
              IO.puts("    Item type: #{item_type}")
            end

          :item_completed ->
            IO.puts("    Item completed")

            if get_in(event.data, [:params, "item", "type"]) do
              item_type = get_in(event.data, [:params, "item", "type"])
              IO.puts("    Item type: #{item_type}")
            end

            if get_in(event.data, [:params, "item", "text"]) do
              text = get_in(event.data, [:params, "item", "text"])
              IO.puts("    Text: #{String.slice(text, 0, 200)}...")
            end

            if get_in(event.data, [:params, "item", "command"]) do
              command = get_in(event.data, [:params, "item", "command"])
              IO.puts("    Command: #{command}")
            end

          :agent_message_delta ->
            delta = get_in(event.data, [:params, :delta]) || ""
            IO.puts("    Delta: #{String.slice(delta, 0, 100)}...")

          :approval_required ->
            IO.puts("    Approval required")
            IO.puts("    Params: #{inspect(event.data.params, limit: 100)}")

          :message_sent ->
            IO.puts("    Message sent")
            IO.puts("    Content: #{inspect(get_in(event.data, [:message]), limit: 200)}")

          _ ->
            IO.puts("    Data: #{inspect(event.data, limit: 100)}")
        end

        IO.puts("")
      end)
    end
  end

  defp query_database_records(interaction_id) do
    # Query the interaction
    case Ash.get(Interaction, interaction_id) do
      {:ok, interaction} ->
        IO.puts("Interaction Record:")
        IO.puts("  ID: #{interaction.id}")
        IO.puts("  Status: #{interaction.status}")
        IO.puts("  Original message: #{interaction.original_message}")
        IO.puts("  Response: #{inspect(interaction.response, limit: 300)}")
        IO.puts("  Created at: #{interaction.inserted_at}")
        IO.puts("  Updated at: #{interaction.updated_at}")
        IO.puts("")

      {:error, reason} ->
        IO.puts("  ERROR: Could not retrieve interaction: #{inspect(reason)}")
    end

    # Query interaction items
    query =
      Ash.Query.for_read(InteractionItem, :list_by_interaction, %{
        interaction_id: interaction_id
      })

    case Ash.read(query) do
      {:ok, items} ->
        IO.puts("Interaction Items: #{length(items)} found")
        IO.puts("")

        items
        |> Enum.with_index(1)
        |> Enum.each(fn {item, index} ->
          IO.puts("  Item #{index}:")
          IO.puts("    ID: #{item.id}")
          IO.puts("    Type: #{item.type}")
          IO.puts("    Status: #{item.status}")
          IO.puts("    Payload keys: #{Map.keys(item.payload) |> inspect}")

          # Check for relevant data in payload
          if item.type == :command_execution do
            command = get_in(item.payload, ["item", "command"])
            output = get_in(item.payload, ["item", "output"])

            IO.puts("    Command: #{inspect(command)}")
            IO.puts("    Output: #{inspect(output, limit: 200)}")
          end

          if item.type == :agent_message do
            text = get_in(item.payload, ["item", "text"])
            IO.puts("    Message text: #{String.slice(text || "", 0, 200)}...")
          end

          IO.puts("")
        end)

      {:error, reason} ->
        IO.puts("  ERROR: Could not retrieve items: #{inspect(reason)}")
    end
  end

  defp check_for_issues(results, interaction_id) do
    issues = []

    # Check mock surface for error indicators
    error_events =
      Enum.filter(results, fn event ->
        (event.type in [:turn_completed] and
           event.data[:params]) && get_in(event.data.params, ["turn", "error"])
      end)

    if Enum.any?(error_events) do
      issues = ["Turn completed with errors" | issues]
    end

    # Check for command execution failures
    command_failures =
      Enum.filter(results, fn event ->
        ((event.type == :item_completed and
            event.data[:params]) &&
           get_in(event.data.params, ["item", "type"]) == "commandExecution") and
          (get_in(event.data.params, ["item", "output", "exitCode"]) != 0 or
             get_in(event.data.params, ["item", "output", "error"]))
      end)

    if Enum.any?(command_failures) do
      issues = ["Command execution failures detected" | issues]
    end

    # Query items for specific error types
    query =
      Ash.Query.for_read(InteractionItem, :list_by_interaction, %{
        interaction_id: interaction_id
      })

    case Ash.read(query) do
      {:ok, items} ->
        # Check for mise/ett related items
        mise_items =
          Enum.filter(items, fn item ->
            text = get_in(item.payload, ["item", "text"]) || ""
            command = get_in(item.payload, ["item", "command"]) || ""

            String.contains?(text, "mise") or
              String.contains?(text, "ett") or
              String.contains?(command, "mise") or
              String.contains?(command, "ett")
          end)

        if Enum.any?(mise_items) do
          IO.puts("Found #{length(mise_items)} items related to mise/ett:")

          mise_items
          |> Enum.each(fn item ->
            IO.puts("  - Item #{item.id} (#{item.type})")
            text = get_in(item.payload, ["item", "text"]) || ""
            command = get_in(item.payload, ["item", "command"]) || ""

            if text != "", do: IO.puts("    Text: #{String.slice(text, 0, 100)}")
            if command != "", do: IO.puts("    Command: #{command}")
          end)
        else
          IO.puts("No specific mise/ett related items found")
        end

      {:error, _} ->
        :ok
    end

    if Enum.empty?(issues) do
      IO.puts("No critical issues detected")
    else
      IO.puts("Issues detected:")

      Enum.each(issues, fn issue ->
        IO.puts("  - #{issue}")
      end)
    end
  end

  defp print_summary(interaction_id, results) do
    # Get final interaction status
    case Ash.get(Interaction, interaction_id) do
      {:ok, interaction} ->
        status = interaction.status

        IO.puts("Test Results:")
        IO.puts("  Interaction ID: #{interaction_id}")
        IO.puts("  Final Status: #{status}")
        IO.puts("  Events Recorded: #{length(results)}")

        event_types = Enum.map(results, & &1.type) |> Enum.uniq()
        IO.puts("  Event Types: #{inspect(event_types)}")

        # Determine test outcome
        case status do
          :complete ->
            IO.puts("")
            IO.puts("  STATUS: SUCCESS")
            IO.puts("  The github-tools agent completed successfully")

          :failed ->
            IO.puts("")
            IO.puts("  STATUS: FAILED")
            IO.puts("  The interaction failed")

          :interrupted ->
            IO.puts("")
            IO.puts("  STATUS: INTERRUPTED")
            IO.puts("  The interaction was interrupted")

          _ ->
            IO.puts("")
            IO.puts("  STATUS: INCOMPLETE")
            IO.puts("  The interaction did not reach a final state")
        end

      {:error, reason} ->
        IO.puts("  Could not retrieve final status: #{inspect(reason)}")
    end
  end
end

# Run the test
TestHarness.run_test()
