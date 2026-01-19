defmodule PianoWeb.Admin.AgentListLive do
  use PianoWeb, :live_view

  alias Piano.Agents.Agent

  @impl true
  def mount(params, session, socket) do
    token = params["token"] || session["admin_token"]

    if valid_token?(token) do
      agents = load_agents()
      {:ok, assign(socket, agents: agents, token: token)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Unauthorized - add ?token=<admin_token> to URL")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  defp valid_token?(token) do
    expected = Application.get_env(:piano, :admin_token, "piano_admin")
    token == expected
  end

  defp load_agents do
    case Ash.read(Agent, action: :list) do
      {:ok, agents} -> agents
      {:error, _} -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 p-6">
      <div class="max-w-4xl mx-auto">
        <header class="mb-8">
          <h1 class="text-3xl font-bold text-white">Agent Management</h1>
          <p class="text-gray-400 mt-2">Configure AI agents for Piano</p>
        </header>

        <div class="bg-gray-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-gray-700">
              <tr>
                <th class="px-6 py-3 text-left text-sm font-medium text-gray-300">Name</th>
                <th class="px-6 py-3 text-left text-sm font-medium text-gray-300">Model</th>
                <th class="px-6 py-3 text-left text-sm font-medium text-gray-300">Tools</th>
                <th class="px-6 py-3 text-left text-sm font-medium text-gray-300">Skills</th>
                <th class="px-6 py-3 text-right text-sm font-medium text-gray-300">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-700">
              <%= for agent <- @agents do %>
                <tr class="hover:bg-gray-750">
                  <td class="px-6 py-4">
                    <div class="text-white font-medium"><%= agent.name %></div>
                    <div class="text-sm text-gray-400"><%= agent.description || "No description" %></div>
                  </td>
                  <td class="px-6 py-4 text-gray-300"><%= agent.model %></td>
                  <td class="px-6 py-4 text-gray-300"><%= length(agent.enabled_tools) %></td>
                  <td class="px-6 py-4 text-gray-300"><%= length(agent.enabled_skills) %></td>
                  <td class="px-6 py-4 text-right">
                    <.link
                      navigate={~p"/admin/agents/#{agent.id}?token=#{@token}"}
                      class="text-blue-400 hover:text-blue-300 transition-colors"
                    >
                      Edit
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>

          <%= if @agents == [] do %>
            <div class="p-8 text-center text-gray-400">
              No agents configured. Run seeds to create a default agent.
            </div>
          <% end %>
        </div>

        <div class="mt-6">
          <.link navigate={~p"/chat"} class="text-gray-400 hover:text-white transition-colors">
            ← Back to Chat
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
