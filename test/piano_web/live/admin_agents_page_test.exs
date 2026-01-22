defmodule PianoWeb.AdminAgentsPageTest do
  use PianoWeb.ConnCase, async: false

  alias Piano.Agents.Agent

  setup do
    Application.put_env(:piano, :admin_token, "test_admin")
    Application.put_env(:piano, :llm, disable_model_fetch: true)
    :ok
  end

  test "can open create modal and create agent", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard/agents?token=test_admin")

    view
    |> element("button[phx-click='open_create_modal']")
    |> render_click()

    assert render(view) =~ "Create Agent"

    view
    |> form("#create-agent-form", %{
      "new" => %{
        "name" => "New Agent",
        "model" => "gpt-oss-20b",
        "description" => "Test agent",
        "system_prompt" => "Be helpful.",
        "soul" => "Remember the user prefers short answers."
      }
    })
    |> render_submit()

    assert render(view) =~ "New Agent"

    {:ok, agents} = Ash.read(Agent, action: :list)
    created = Enum.find(agents, fn agent -> agent.name == "New Agent" end)
    assert created
    assert created.soul == "Remember the user prefers short answers."
  end

  test "can open edit modal and update agent", %{conn: conn} do
    {:ok, agent} =
      Ash.create(Agent, %{
        name: "Original Agent",
        model: "gpt-oss-20b",
        system_prompt: "Original prompt"
      }, action: :create)

    {:ok, view, _html} = live(conn, "/dashboard/agents?token=test_admin")

    view
    |> element("button[phx-click='open_edit_modal'][phx-value-id='#{agent.id}']")
    |> render_click()

    assert render(view) =~ "Edit Agent"

    view
    |> form("#edit-agent-form", %{
      "form" => %{
        "name" => "Updated Agent",
        "model" => "gpt-oss-20b",
        "description" => "Updated description",
        "system_prompt" => "Updated prompt",
        "soul" => "Keep responses concise."
      }
    })
    |> render_submit()

    assert render(view) =~ "Updated Agent"

    {:ok, updated} = Ash.get(Agent, agent.id)
    assert updated.soul == "Keep responses concise."
  end

  test "can delete agent", %{conn: conn} do
    {:ok, agent} =
      Ash.create(Agent, %{
        name: "Agent To Delete",
        model: "gpt-oss-20b",
        system_prompt: "Test prompt"
      }, action: :create)

    {:ok, view, _html} = live(conn, "/dashboard/agents?token=test_admin")

    assert render(view) =~ "Agent To Delete"

    view
    |> element("button[phx-click='delete'][phx-value-id='#{agent.id}']")
    |> render_click()

    refute render(view) =~ "Agent To Delete"

    assert {:error, _} = Ash.get(Agent, agent.id)
  end
end
