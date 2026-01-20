defmodule PianoWeb.Admin.AgentEditLive do
  use PianoWeb, :live_view

  alias Piano.Agents.Agent
  alias Piano.Agents.ToolRegistry
  alias Piano.Agents.SkillRegistry

  @impl true
  def mount(params, session, socket) do
    token = params["token"] || session["admin_token"]

    if valid_token?(token) do
      available_tools = ToolRegistry.list_available()
      available_skills = SkillRegistry.list_available()

      {:ok,
       assign(socket,
         token: token,
         agent: nil,
         available_tools: available_tools,
         available_skills: available_skills,
         form: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Unauthorized")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Ash.get(Agent, id) do
      {:ok, agent} ->
        form = build_form(agent)
        {:noreply, assign(socket, agent: agent, form: form)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Agent not found")
         |> redirect(to: ~p"/admin/agents?token=#{socket.assigns.token}")}
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

  defp valid_token?(token) do
    expected = Application.get_env(:piano, :admin_token, "piano_admin")
    token == expected
  end

  @impl true
  def handle_event("validate", %{"form" => form_params}, socket) do
    form = to_form(form_params)
    {:noreply, assign(socket, form: form)}
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

    case agent
         |> Ash.Changeset.for_update(:update_config, attrs)
         |> Ash.update() do
      {:ok, updated_agent} ->
        form = build_form(updated_agent)

        {:noreply,
         socket
         |> assign(agent: updated_agent, form: form)
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

    case agent
         |> Ash.Changeset.for_update(:update_config, attrs)
         |> Ash.update() do
      {:ok, updated_agent} ->
        form = build_form(updated_agent)
        {:noreply, assign(socket, agent: updated_agent, form: form)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update agent")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 p-6">
      <div class="max-w-2xl mx-auto">
        <header class="mb-8">
          <h1 class="text-3xl font-bold text-white">Edit Agent</h1>
          <p class="text-gray-400 mt-2">Configure agent settings, tools, and skills</p>
        </header>

        <%= if @agent && @form do %>
          <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
            <div class="bg-gray-800 rounded-lg p-6 space-y-4">
              <h2 class="text-lg font-semibold text-white mb-4">Basic Information</h2>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Name</label>
                <input
                  type="text"
                  name="form[name]"
                  value={@form[:name].value}
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  required
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Model</label>
                <input
                  type="text"
                  name="form[model]"
                  value={@form[:model].value}
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  required
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Description</label>
                <textarea
                  name="form[description]"
                  rows="2"
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                ><%= @form[:description].value %></textarea>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">System Prompt</label>
                <textarea
                  name="form[system_prompt]"
                  rows="4"
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                ><%= @form[:system_prompt].value %></textarea>
              </div>
            </div>

            <div class="bg-gray-800 rounded-lg p-6">
              <h2 class="text-lg font-semibold text-white mb-4">Enabled Tools</h2>
              <p class="text-gray-400 text-sm mb-4">
                Select which tools this agent can use
              </p>

              <%= if @available_tools == [] do %>
                <p class="text-gray-500 italic">No tools available</p>
              <% else %>
                <div class="space-y-3">
                  <%= for tool <- @available_tools do %>
                    <div class="flex items-center justify-between">
                      <span class="text-gray-300"><%= tool %></span>
                      <button
                        type="button"
                        phx-click="toggle_tool"
                        phx-value-tool={tool}
                        class={[
                          "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-gray-800",
                          if(tool in (@agent.enabled_tools || []),
                            do: "bg-blue-600",
                            else: "bg-gray-600"
                          )
                        ]}
                      >
                        <span
                          class={[
                            "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                            if(tool in (@agent.enabled_tools || []),
                              do: "translate-x-5",
                              else: "translate-x-0"
                            )
                          ]}
                        />
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="bg-gray-800 rounded-lg p-6">
              <h2 class="text-lg font-semibold text-white mb-4">Enabled Skills</h2>
              <p class="text-gray-400 text-sm mb-4">
                Select which skills to include in the agent's system prompt
              </p>

              <%= if @available_skills == [] do %>
                <p class="text-gray-500 italic">
                  No skills available. Add .md files to .agents/skills/ directory.
                </p>
              <% else %>
                <div class="space-y-3">
                  <%= for skill <- @available_skills do %>
                    <div class="flex items-center justify-between">
                      <span class="text-gray-300"><%= skill %></span>
                      <button
                        type="button"
                        phx-click="toggle_skill"
                        phx-value-skill={skill}
                        class={[
                          "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-gray-800",
                          if(skill in (@agent.enabled_skills || []),
                            do: "bg-blue-600",
                            else: "bg-gray-600"
                          )
                        ]}
                      >
                        <span
                          class={[
                            "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                            if(skill in (@agent.enabled_skills || []),
                              do: "translate-x-5",
                              else: "translate-x-0"
                            )
                          ]}
                        />
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="flex items-center justify-between">
              <.link
                navigate={~p"/admin/agents?token=#{@token}"}
                class="text-gray-400 hover:text-white transition-colors"
              >
                ← Back to Agents
              </.link>

              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-500 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-gray-900"
              >
                Save Changes
              </button>
            </div>
          </.form>
        <% end %>
      </div>
    </div>
    """
  end
end
