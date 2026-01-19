defmodule PianoWeb.Admin.AgentEditLive do
  use PianoWeb, :live_view

  alias Piano.Agents.Agent

  @impl true
  def mount(params, session, socket) do
    token = params["token"] || session["admin_token"]

    if valid_token?(token) do
      {:ok, assign(socket, token: token, agent: nil)}
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
        {:noreply, assign(socket, agent: agent)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Agent not found")
         |> redirect(to: ~p"/admin/agents?token=#{socket.assigns.token}")}
    end
  end

  defp valid_token?(token) do
    expected = Application.get_env(:piano, :admin_token, "piano_admin")
    token == expected
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 p-6">
      <div class="max-w-2xl mx-auto">
        <header class="mb-8">
          <h1 class="text-3xl font-bold text-white">Edit Agent</h1>
        </header>

        <%= if @agent do %>
          <div class="bg-gray-800 rounded-lg p-6">
            <p class="text-gray-300">Agent: <%= @agent.name %></p>
            <p class="text-gray-400 mt-4">Edit form coming in next task...</p>
          </div>
        <% end %>

        <div class="mt-6">
          <.link
            navigate={~p"/admin/agents?token=#{@token}"}
            class="text-gray-400 hover:text-white transition-colors"
          >
            ← Back to Agents
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
