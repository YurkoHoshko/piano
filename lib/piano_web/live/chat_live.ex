defmodule PianoWeb.ChatLive do
  use PianoWeb, :live_view

  alias Piano.Agents.Agent
  alias Piano.Chat.{Message, Thread}
  alias Piano.{ChatGateway, Events}

  @impl true
  def mount(_params, _session, socket) do
    threads = load_threads()
    agents = load_agents()

    {:ok,
     assign(socket,
       threads: threads,
       agents: agents,
       messages: [],
       tool_calls_buffer: [],
       tool_calls_by_message_id: %{},
       thread_id: nil,
       renaming_thread_id: nil,
       rename_value: "",
       selected_agent_id: nil,
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

    metadata =
      case socket.assigns.selected_agent_id do
        nil -> metadata
        agent_id -> Map.put(metadata, :agent_id, agent_id)
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

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input_value, value)}
  end

  def handle_event("select_agent", %{"agent_id" => ""}, socket) do
    {:noreply, assign(socket, :selected_agent_id, nil)}
  end

  def handle_event("select_agent", %{"agent_id" => agent_id}, socket) do
    {:noreply, assign(socket, :selected_agent_id, agent_id)}
  end

  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    socket =
      socket
      |> assign(:renaming_thread_id, nil)
      |> assign(:rename_value, "")

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
     |> assign(:tool_calls_buffer, [])
     |> assign(:tool_calls_by_message_id, %{})
     |> assign(:renaming_thread_id, nil)
     |> assign(:rename_value, "")
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

  def handle_event("start_rename_thread", %{"id" => thread_id}, socket) do
    title =
      case Enum.find(socket.assigns.threads, fn thread -> thread.id == thread_id end) do
        nil -> ""
        thread -> thread.title || ""
      end

    {:noreply,
     socket
     |> assign(:renaming_thread_id, thread_id)
     |> assign(:rename_value, title)}
  end

  def handle_event("rename_thread_change", %{"rename_value" => value}, socket) do
    {:noreply, assign(socket, :rename_value, value)}
  end

  def handle_event("rename_thread_cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:renaming_thread_id, nil)
     |> assign(:rename_value, "")}
  end

  def handle_event("rename_thread_save", %{"id" => thread_id}, socket) do
    thread = Enum.find(socket.assigns.threads, fn t -> t.id == thread_id end)

    if thread do
      title =
        socket.assigns.rename_value
        |> String.trim()
        |> case do
          "" -> nil
          value -> value
        end

      case thread |> Ash.Changeset.for_update(:rename, %{title: title}) |> Ash.update() do
        {:ok, _updated_thread} ->
          {:noreply,
           socket
           |> assign(:threads, load_threads())
           |> assign(:renaming_thread_id, nil)
           |> assign(:rename_value, "")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to rename thread")}
      end
    else
      {:noreply, put_flash(socket, :error, "Thread not found")}
    end
  end

  def handle_event("delete_thread", %{"id" => thread_id}, socket) do
    thread = Enum.find(socket.assigns.threads, fn t -> t.id == thread_id end)

    if thread do
      case Ash.destroy(thread) do
        :ok ->
          socket =
            if socket.assigns.thread_id == thread_id do
              Events.unsubscribe(thread_id)

              socket
              |> assign(:thread_id, nil)
              |> assign(:messages, [])
              |> assign(:tool_calls_buffer, [])
              |> assign(:tool_calls_by_message_id, %{})
              |> assign(:thinking, false)
              |> push_patch(to: ~p"/chat")
            else
              socket
            end

          {:noreply,
           socket
           |> assign(:threads, load_threads())
           |> assign(:renaming_thread_id, nil)
           |> assign(:rename_value, "")}

        {:error, _error} ->
          {:noreply, put_flash(socket, :error, "Failed to delete thread")}
      end
    else
      {:noreply, put_flash(socket, :error, "Thread not found")}
    end
  end

  @impl true
  def handle_info({:processing_started, _message_id}, socket) do
    {:noreply, assign(socket, :thinking, true)}
  end

  def handle_info({:response_ready, _message_id, message}, socket) do
    handle_response_ready(message, socket)
  end

  def handle_info({:response_ready, message}, socket) do
    handle_response_ready(message, socket)
  end

  def handle_info({:processing_error, _message_id, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> assign(:tool_calls_buffer, [])
     |> put_flash(:error, "Failed to get response")}
  end

  def handle_info({:tool_call, _message_id, tool_call}, socket) do
    {:noreply, update(socket, :tool_calls_buffer, &(&1 ++ [tool_call]))}
  end

  def handle_info({:tool_call, tool_call}, socket) do
    {:noreply, update(socket, :tool_calls_buffer, &(&1 ++ [tool_call]))}
  end

  defp handle_response_ready(message, socket) do
    tool_calls = socket.assigns.tool_calls_buffer

    {:noreply,
     socket
     |> assign(:thinking, false)
     |> assign(:tool_calls_buffer, [])
     |> update(:tool_calls_by_message_id, fn map ->
       if tool_calls == [] do
         map
       else
         Map.put(map, message.id, tool_calls)
       end
     end)
     |> update(:messages, &(&1 ++ [message]))}
  end

  defp load_threads do
    case Ash.read(Thread, action: :list) do
      {:ok, threads} -> threads
      {:error, _} -> []
    end
  end

  defp load_agents do
    case Ash.read(Agent, action: :list) do
      {:ok, agents} -> agents
      {:error, _} -> []
    end
  end

  defp load_thread(socket, thread_id) do
    if socket.assigns.thread_id do
      Events.unsubscribe(socket.assigns.thread_id)
    end

    case Ash.get(Thread, thread_id) do
      {:ok, thread} ->
        messages = load_messages(thread_id)
        Events.subscribe(thread_id)

        socket
        |> assign(:thread_id, thread_id)
        |> assign(:messages, messages)
        |> assign(:tool_calls_buffer, [])
        |> assign(:tool_calls_by_message_id, %{})
        |> assign(:thinking, false)
        |> assign(:selected_agent_id, thread.primary_agent_id)

      {:error, _} ->
        socket
        |> put_flash(:error, "Thread not found")
        |> push_patch(to: ~p"/chat")
    end
  end

  defp load_messages(thread_id) do
    query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: thread_id})

    case Ash.read(query) do
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
            data-testid="new-thread-btn"
            class="w-full bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
          >
            + New Thread
          </button>
        </div>
        <div class="flex-1 overflow-y-auto">
          <%= for thread <- @threads do %>
            <div
              class={[
                "border-b border-gray-700",
                thread.id == @thread_id && "bg-gray-800"
              ]}
            >
              <button
                phx-click="select_thread"
                phx-value-id={thread.id}
                data-testid={"thread-#{thread.id}"}
                class="w-full text-left px-4 py-3 hover:bg-gray-800 transition-colors"
              >
                <div class="text-white truncate">
                  <%= thread.title || "Untitled Thread" %>
                </div>
                <div class="text-xs text-gray-400">
                  <%= Calendar.strftime(thread.inserted_at, "%b %d, %H:%M") %>
                </div>
              </button>

              <div class="flex items-center gap-2 px-4 pb-3 text-xs">
                <%= if @renaming_thread_id == thread.id do %>
                  <input
                    type="text"
                    value={@rename_value}
                    phx-change="rename_thread_change"
                    phx-debounce="200"
                    name="rename_value"
                    class="flex-1 bg-gray-800 text-white rounded px-2 py-1 border border-gray-600"
                  />
                  <button
                    phx-click="rename_thread_save"
                    phx-value-id={thread.id}
                    class="text-green-400 hover:text-green-300"
                  >
                    Save
                  </button>
                  <button
                    phx-click="rename_thread_cancel"
                    class="text-gray-400 hover:text-gray-200"
                  >
                    Cancel
                  </button>
                <% else %>
                  <button
                    phx-click="start_rename_thread"
                    phx-value-id={thread.id}
                    class="text-blue-400 hover:text-blue-300"
                  >
                    Rename
                  </button>
                  <button
                    phx-click="delete_thread"
                    phx-value-id={thread.id}
                    phx-confirm="Delete this thread?"
                    class="text-red-400 hover:text-red-300"
                  >
                    Delete
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </aside>

      <div class="flex-1 flex flex-col">
        <header class="flex-shrink-0 border-b border-gray-700 p-4">
          <h1 class="text-xl font-semibold text-white">Piano Chat</h1>
        </header>

        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="message-list" data-testid="message-list">
          <%= if @messages == [] && @thread_id == nil do %>
            <div class="flex items-center justify-center h-full text-gray-400">
              Start a new conversation by typing a message below
            </div>
          <% else %>
            <%= for message <- @messages do %>
              <.message_bubble
                message={message}
                show_fork={@thread_id != nil}
                agents={@agents}
                tool_calls={Map.get(@tool_calls_by_message_id, message.id, [])}
              />
            <% end %>
          <% end %>

          <div :if={@thinking and @tool_calls_buffer != []} class="text-gray-300 text-sm">
            <details open class="bg-gray-800 rounded-lg px-4 py-3 border border-gray-700">
              <summary class="cursor-pointer">Tool calls</summary>
              <ul class="mt-2 space-y-1">
                <%= for call <- @tool_calls_buffer do %>
                  <li class="font-mono text-xs break-all"><%= format_tool_call(call) %></li>
                <% end %>
              </ul>
            </details>
          </div>

          <div :if={@thinking} class="flex items-center gap-2 text-gray-400" data-testid="thinking-indicator">
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
          <div class="mb-3">
            <select
              phx-change="select_agent"
              name="agent_id"
              class="bg-gray-800 text-white rounded-lg px-3 py-2 border border-gray-600 focus:outline-none focus:border-blue-500"
            >
              <option value="">Default Agent</option>
              <%= for agent <- @agents do %>
                <option value={agent.id} selected={agent.id == @selected_agent_id}>
                  <%= agent.name %>
                </option>
              <% end %>
            </select>
          </div>
          <form phx-submit="send_message" class="flex gap-3" data-testid="message-form">
            <input
              type="text"
              name="message"
              value={@input_value}
              phx-change="update_input"
              placeholder="Type a message..."
              autocomplete="off"
              data-testid="message-input"
              class="flex-1 bg-gray-800 text-white rounded-lg px-4 py-3 border border-gray-600 focus:outline-none focus:border-blue-500"
            />
            <button
              type="submit"
              disabled={@thinking}
              data-testid="send-btn"
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
    agent_name =
      if assigns.message.role == :agent && assigns.message.agent_id do
        case Enum.find(assigns.agents, fn a -> a.id == assigns.message.agent_id end) do
          nil -> "Assistant"
          agent -> agent.name
        end
      else
        nil
      end

    assigns = assign(assigns, :agent_name, agent_name)

    ~H"""
    <div class="group relative" data-testid={"message-#{@message.role}"}>
      <div class={[
        "max-w-[80%] rounded-lg px-4 py-3",
        @message.role == :user && "bg-blue-600 text-white ml-auto",
        @message.role == :agent && "bg-gray-700 text-white mr-auto"
      ]}>
        <div class="text-sm opacity-70 mb-1">
          <%= if @message.role == :user, do: "You", else: @agent_name || "Assistant" %>
        </div>
        <div class="whitespace-pre-wrap" data-testid="message-content"><%= @message.content %></div>
        <details :if={@message.role == :agent and @tool_calls != []} class="mt-3 text-xs text-gray-300">
          <summary class="cursor-pointer">Tool calls</summary>
          <ul class="mt-2 space-y-1">
            <%= for call <- @tool_calls do %>
              <li class="font-mono break-all"><%= format_tool_call(call) %></li>
            <% end %>
          </ul>
        </details>
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

  defp format_tool_call(%{name: name, arguments: args}) when is_map(args) do
    rendered =
      args
      |> Enum.filter(fn {key, value} ->
        key in ["command", "path", "url", "query", "file", "name"] and value != nil
      end)
      |> Enum.map(fn {key, value} -> "#{key}=#{format_tool_call_value(value)}" end)
      |> Enum.join(", ")

    if rendered == "" do
      "#{name}()"
    else
      "#{name}(#{rendered})"
    end
  end

  defp format_tool_call(%{name: name}), do: "#{name}()"
  defp format_tool_call(_), do: "tool_call()"

  defp format_tool_call_value(value) when is_binary(value) do
    value
    |> String.replace("\n", " ")
    |> String.slice(0, 120)
  end

  defp format_tool_call_value(value), do: inspect(value, limit: 2, printable_limit: 120)
end
