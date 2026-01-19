defmodule PianoWeb.ChatLive do
  use PianoWeb, :live_view

  alias Piano.Chat.{Message, Thread}
  alias Piano.{ChatGateway, Events}

  @impl true
  def mount(_params, _session, socket) do
    threads = load_threads()

    {:ok,
     assign(socket,
       threads: threads,
       messages: [],
       thread_id: nil,
       input_value: "",
       thinking: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    thread_id = params["thread"]

    socket =
      if thread_id && thread_id != socket.assigns.thread_id do
        load_thread(socket, thread_id)
      else
        socket
      end

    {:noreply, socket}
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

        socket =
          if socket.assigns.thread_id != thread_id do
            Events.subscribe(thread_id)

            socket
            |> assign(:thread_id, thread_id)
            |> assign(:threads, load_threads())
            |> push_patch(to: ~p"/chat?thread=#{thread_id}")
          else
            socket
          end

        {:noreply,
         socket
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

  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?thread=#{thread_id}")}
  end

  def handle_event("new_thread", _params, socket) do
    if socket.assigns.thread_id do
      Events.unsubscribe(socket.assigns.thread_id)
    end

    {:noreply,
     socket
     |> assign(:thread_id, nil)
     |> assign(:messages, [])
     |> assign(:thinking, false)
     |> push_patch(to: ~p"/chat")}
  end

  def handle_event("fork_thread", %{"message-id" => message_id}, socket) do
    thread_id = socket.assigns.thread_id

    case Ash.create(Thread, %{}, action: :fork, args: [source_thread_id: thread_id, fork_at_message_id: message_id]) do
      {:ok, new_thread} ->
        Events.unsubscribe(thread_id)

        {:noreply,
         socket
         |> assign(:threads, load_threads())
         |> push_patch(to: ~p"/chat?thread=#{new_thread.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to fork thread")}
    end
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

  defp load_threads do
    case Ash.read(Thread, action: :list) do
      {:ok, threads} -> threads
      {:error, _} -> []
    end
  end

  defp load_thread(socket, thread_id) do
    if socket.assigns.thread_id do
      Events.unsubscribe(socket.assigns.thread_id)
    end

    case Ash.get(Thread, thread_id) do
      {:ok, _thread} ->
        messages = load_messages(thread_id)
        Events.subscribe(thread_id)

        socket
        |> assign(:thread_id, thread_id)
        |> assign(:messages, messages)
        |> assign(:thinking, false)

      {:error, _} ->
        socket
        |> put_flash(:error, "Thread not found")
        |> push_patch(to: ~p"/chat")
    end
  end

  defp load_messages(thread_id) do
    case Ash.read(Message, action: :list_by_thread, args: [thread_id: thread_id]) do
      {:ok, messages} -> Enum.sort_by(messages, & &1.inserted_at, DateTime)
      {:error, _} -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-900">
      <aside class="w-64 flex-shrink-0 border-r border-gray-700 flex flex-col">
        <div class="p-4 border-b border-gray-700">
          <button
            phx-click="new_thread"
            class="w-full bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
          >
            + New Thread
          </button>
        </div>
        <div class="flex-1 overflow-y-auto">
          <%= for thread <- @threads do %>
            <button
              phx-click="select_thread"
              phx-value-id={thread.id}
              class={[
                "w-full text-left px-4 py-3 border-b border-gray-700 hover:bg-gray-800 transition-colors",
                thread.id == @thread_id && "bg-gray-800"
              ]}
            >
              <div class="text-white truncate">
                <%= thread.title || "Untitled Thread" %>
              </div>
              <div class="text-xs text-gray-400">
                <%= Calendar.strftime(thread.inserted_at, "%b %d, %H:%M") %>
              </div>
            </button>
          <% end %>
        </div>
      </aside>

      <div class="flex-1 flex flex-col">
        <header class="flex-shrink-0 border-b border-gray-700 p-4">
          <h1 class="text-xl font-semibold text-white">Piano Chat</h1>
        </header>

        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="message-list" phx-update="stream">
          <%= if @messages == [] && @thread_id == nil do %>
            <div class="flex items-center justify-center h-full text-gray-400">
              Start a new conversation by typing a message below
            </div>
          <% else %>
            <%= for message <- @messages do %>
              <.message_bubble message={message} show_fork={@thread_id != nil} />
            <% end %>
          <% end %>

          <div :if={@thinking} class="flex items-center gap-2 text-gray-400">
            <div class="flex gap-1">
              <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce [animation-delay:-0.3s]">
              </span>
              <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce [animation-delay:-0.15s]">
              </span>
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
    </div>
    """
  end

  defp message_bubble(assigns) do
    ~H"""
    <div class="group relative">
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
      <button
        :if={@show_fork}
        phx-click="fork_thread"
        phx-value-message-id={@message.id}
        class={[
          "absolute top-2 opacity-0 group-hover:opacity-100 transition-opacity",
          "bg-gray-600 hover:bg-gray-500 text-white text-xs px-2 py-1 rounded",
          @message.role == :user && "left-2",
          @message.role == :agent && "right-2"
        ]}
        title="Fork from here"
      >
        ⑂ Fork
      </button>
    </div>
    """
  end
end
