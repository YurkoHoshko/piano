defmodule PianoWeb.ChatLive do
  use PianoWeb, :live_view

  alias Piano.{ChatGateway, Events}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       messages: [],
       thread_id: nil,
       input_value: "",
       thinking: false
     )}
  end

  @impl true
  def handle_event("send_message", %{"message" => content}, socket) when content != "" do
    metadata =
      case socket.assigns.thread_id do
        nil -> %{}
        id -> %{thread_id: id}
      end

    case ChatGateway.handle_incoming(content, :web, metadata) do
      {:ok, message} ->
        thread_id = message.thread_id

        if socket.assigns.thread_id != thread_id do
          Events.subscribe(thread_id)
        end

        {:noreply,
         socket
         |> assign(:thread_id, thread_id)
         |> assign(:input_value, "")
         |> assign(:thinking, true)
         |> update(:messages, &(&1 ++ [message]))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :input_value, value)}
  end

  @impl true
  def handle_info({:processing_started, _message_id}, socket) do
    {:noreply, assign(socket, :thinking, true)}
  end

  def handle_info({:response_ready, message}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> update(:messages, &(&1 ++ [message]))}
  end

  def handle_info({:processing_error, _message_id, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> put_flash(:error, "Failed to get response")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-900">
      <header class="flex-shrink-0 border-b border-gray-700 p-4">
        <h1 class="text-xl font-semibold text-white">Piano Chat</h1>
      </header>

      <div class="flex-1 overflow-y-auto p-4 space-y-4" id="message-list" phx-update="stream">
        <%= for message <- @messages do %>
          <.message_bubble message={message} />
        <% end %>

        <div :if={@thinking} class="flex items-center gap-2 text-gray-400">
          <div class="flex gap-1">
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce [animation-delay:-0.3s]"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce [animation-delay:-0.15s]"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></span>
          </div>
          <span>Thinking...</span>
        </div>
      </div>

      <div class="flex-shrink-0 border-t border-gray-700 p-4">
        <form phx-submit="send_message" class="flex gap-3">
          <input
            type="text"
            name="message"
            value={@input_value}
            phx-change="update_input"
            placeholder="Type a message..."
            autocomplete="off"
            class="flex-1 bg-gray-800 text-white rounded-lg px-4 py-3 border border-gray-600 focus:outline-none focus:border-blue-500"
          />
          <button
            type="submit"
            disabled={@thinking}
            class="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white px-6 py-3 rounded-lg font-medium transition-colors"
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp message_bubble(assigns) do
    ~H"""
    <div class={[
      "max-w-[80%] rounded-lg px-4 py-3",
      @message.role == :user && "bg-blue-600 text-white ml-auto",
      @message.role == :agent && "bg-gray-700 text-white mr-auto"
    ]}>
      <div class="text-sm opacity-70 mb-1">
        <%= if @message.role == :user, do: "You", else: "Assistant" %>
      </div>
      <div class="whitespace-pre-wrap"><%= @message.content %></div>
    </div>
    """
  end
end
