if Code.ensure_loaded?(Phoenix.LiveDashboard.PageBuilder) do
  defmodule PianoWeb.Admin.AgentsPage do
    @moduledoc false

    use Phoenix.LiveDashboard.PageBuilder

    import Phoenix.Component
    import Phoenix.LiveView, only: [put_flash: 3]

    alias Piano.Agents.{Agent, SkillRegistry, ToolRegistry}

  @impl true
  def menu_link(_params, _capabilities), do: {:ok, "Agents"}

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(
       agents: load_agents(),
       available_models: load_models(),
       available_tools: ToolRegistry.list_available(),
       available_skills: SkillRegistry.list_available(),
       agent: nil,
       form: nil,
       selected_id: params["agent_id"]
     )
     |> maybe_select_agent(params)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, maybe_select_agent(socket, params)}
  end

  @impl true
  def handle_event("validate", %{"form" => form_params}, socket) do
    {:noreply, assign(socket, form: to_form(form_params))}
  end

  @impl true
  def handle_event("save", %{"form" => form_params}, socket) do
    agent = socket.assigns.agent

    attrs = %{
      name: form_params["name"],
      description: form_params["description"],
      model: form_params["model"],
      system_prompt: form_params["system_prompt"],
      enabled_tools: agent.enabled_tools || [],
      enabled_skills: agent.enabled_skills || []
    }

    case agent |> Ash.Changeset.for_update(:update_config, attrs) |> Ash.update() do
      {:ok, updated_agent} ->
        form = build_form(updated_agent)

        {:noreply,
         socket
         |> assign(agent: updated_agent, form: form, agents: load_agents(), available_models: load_models())
         |> put_flash(:info, "Agent updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update agent")}
    end
  end

  @impl true
  def handle_event("toggle_tool", %{"tool" => tool_name}, socket) do
    agent = socket.assigns.agent
    current_tools = agent.enabled_tools || []

    new_tools =
      if tool_name in current_tools do
        List.delete(current_tools, tool_name)
      else
        [tool_name | current_tools]
      end

    update_agent_field(socket, :enabled_tools, new_tools)
  end

  @impl true
  def handle_event("toggle_skill", %{"skill" => skill_name}, socket) do
    agent = socket.assigns.agent
    current_skills = agent.enabled_skills || []

    new_skills =
      if skill_name in current_skills do
        List.delete(current_skills, skill_name)
      else
        [skill_name | current_skills]
      end

    update_agent_field(socket, :enabled_skills, new_skills)
  end

  defp update_agent_field(socket, field, value) do
    agent = socket.assigns.agent
    attrs = Map.put(%{}, field, value)

    case agent |> Ash.Changeset.for_update(:update_config, attrs) |> Ash.update() do
      {:ok, updated_agent} ->
        form = build_form(updated_agent)
        {:noreply,
         assign(socket,
           agent: updated_agent,
           form: form,
           agents: load_agents(),
           available_models: load_models()
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update agent")}
    end
  end

  defp build_form(agent) do
    to_form(%{
      "name" => agent.name,
      "description" => agent.description || "",
      "model" => agent.model,
      "system_prompt" => agent.system_prompt || "",
      "enabled_tools" => agent.enabled_tools,
      "enabled_skills" => agent.enabled_skills
    })
  end

  defp maybe_select_agent(socket, %{"agent_id" => agent_id}) when is_binary(agent_id) do
    case Ash.get(Agent, agent_id) do
      {:ok, agent} ->
        assign(socket, agent: agent, form: build_form(agent), selected_id: agent_id)

      {:error, _} ->
        socket
        |> put_flash(:error, "Agent not found")
        |> assign(agent: nil, form: nil, selected_id: nil)
    end
  end

  defp maybe_select_agent(socket, _params), do: socket

  defp load_agents do
    case Ash.read(Agent, action: :list) do
      {:ok, agents} -> agents
      {:error, _} -> []
    end
  end

  defp load_models do
    config = Application.get_env(:piano, :llm, [])
    base_url = Keyword.get(config, :base_url, "http://localhost:8000/v1")
    url = String.trim_trailing(base_url, "/") <> "/models"

    case Req.get(url, receive_timeout: 2_000) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        data
        |> Enum.map(&Map.get(&1, "id"))
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()
        |> Enum.sort()

      _ ->
        []
    end
  rescue
    _ -> []
  end

    @impl true
    def render(assigns) do
      ~H"""
      <div class="row">
        <div class="col">
          <div class="card mb-4">
            <div class="card-body">
              <h5 class="card-title">Agents</h5>
              <p class="text-muted mb-3">Configure AI agents for Piano.</p>

              <%= if @agents == [] do %>
                <p class="text-muted mb-0">No agents configured. Run seeds to create a default agent.</p>
              <% else %>
                <table class="table table-hover">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Model</th>
                      <th>Tools</th>
                      <th>Skills</th>
                      <th class="text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for agent <- @agents do %>
                      <tr>
                        <td>
                          <strong><%= agent.name %></strong><br />
                          <small class="text-muted"><%= agent.description || "No description" %></small>
                        </td>
                        <td><%= agent.model %></td>
                        <td><%= length(agent.enabled_tools) %></td>
                        <td><%= length(agent.enabled_skills) %></td>
                        <td class="text-right">
                          <a class="btn btn-primary btn-sm" href={"/dashboard/agents?agent_id=#{agent.id}"}>
                            Edit
                          </a>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%= if @agent && @form do %>
        <div class="row">
          <div class="col">
            <div class="card">
              <div class="card-body">
                <h5 class="card-title">Edit Agent</h5>
                <p class="text-muted mb-3">Update settings, tools, and skills.</p>

                <.form for={@form} phx-change="validate" phx-submit="save">
                  <div class="mb-3">
                    <label>Name</label>
                    <input
                      type="text"
                      name="form[name]"
                      value={@form[:name].value}
                      class="form-control form-control-sm"
                      required
                    />
                  </div>

                  <div class="mb-3">
                    <label>Model</label>
                    <%= if @available_models == [] do %>
                      <input
                        type="text"
                        name="form[model]"
                        value={@form[:model].value}
                        class="form-control form-control-sm"
                        required
                      />
                      <small class="text-muted d-block">
                        LlamaSwap models unavailable; enter a model name manually.
                      </small>
                    <% else %>
                      <select name="form[model]" class="form-control form-control-sm" required>
                        <%= for model <- Enum.uniq([@form[:model].value | @available_models]) do %>
                          <option value={model} selected={model == @form[:model].value}>
                            <%= model %>
                          </option>
                        <% end %>
                      </select>
                    <% end %>
                  </div>

                  <div class="mb-3">
                    <label>Description</label>
                    <textarea name="form[description]" rows="2" class="form-control form-control-sm"><%= @form[:description].value %></textarea>
                  </div>

                  <div class="mb-3">
                    <label>System Prompt</label>
                    <textarea
                      name="form[system_prompt]"
                      rows="4"
                      class="form-control form-control-sm"
                    ><%= @form[:system_prompt].value %></textarea>
                  </div>

                  <div class="mb-3">
                    <label>Enabled Tools</label>
                    <%= if @available_tools == [] do %>
                      <p class="text-muted">No tools available.</p>
                    <% else %>
                      <div class="mb-3">
                        <%= for tool <- @available_tools do %>
                          <div class="d-flex align-items-center justify-content-between mb-2">
                            <span><%= tool %></span>
                            <button
                              type="button"
                              class={
                                "btn btn-sm " <>
                                  if(tool in (@agent.enabled_tools || []),
                                    do: "btn-secondary",
                                    else: "btn-outline-secondary"
                                  )
                              }
                              phx-click="toggle_tool"
                              phx-value-tool={tool}
                            >
                              <%= if tool in (@agent.enabled_tools || []), do: "Disable", else: "Enable" %>
                            </button>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <div class="mb-3">
                    <label>Enabled Skills</label>
                    <%= if @available_skills == [] do %>
                      <p class="text-muted">
                        No skills available. Add .md files to .agents/skills/ directory.
                      </p>
                    <% else %>
                      <div class="mb-3">
                        <%= for skill <- @available_skills do %>
                          <div class="d-flex align-items-center justify-content-between mb-2">
                            <span><%= skill %></span>
                            <button
                              type="button"
                              class={
                                "btn btn-sm " <>
                                  if(skill in (@agent.enabled_skills || []),
                                    do: "btn-secondary",
                                    else: "btn-outline-secondary"
                                  )
                              }
                              phx-click="toggle_skill"
                              phx-value-skill={skill}
                            >
                              <%= if skill in (@agent.enabled_skills || []), do: "Disable", else: "Enable" %>
                            </button>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <div class="d-flex align-items-center gap-2">
                    <button type="submit" class="btn btn-primary">Save Changes</button>
                    <a class="btn btn-outline-secondary" href="/dashboard/agents">Clear selection</a>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>
      <% end %>
      """
    end
  end
end
