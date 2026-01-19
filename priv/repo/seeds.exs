# Script for populating the database with seed data.
# Run with: mix run priv/repo/seeds.exs

alias Piano.Agents.Agent

# Create default agent if none exists
case Ash.read(Agent, action: :list) do
  {:ok, []} ->
    Agent
    |> Ash.Changeset.for_create(:create, %{
      name: "Assistant",
      description: "Default AI assistant",
      model: "qwen3:32b",
      system_prompt: "You are a helpful AI assistant.",
      enabled_tools: [],
      enabled_skills: []
    })
    |> Ash.create!()

    IO.puts("Created default agent: Assistant")

  {:ok, agents} ->
    IO.puts("Found #{length(agents)} existing agent(s), skipping seed")
end
