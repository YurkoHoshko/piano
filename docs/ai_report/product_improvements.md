# Product Improvement Recommendations

## 1. Extending Domains: Users & Permissions

### Current State
Surfaces are identified only by chat_id. Multiple users in a Telegram group share the same surface context.

### Proposed Schema

```elixir
# lib/piano/core/user.ex
defmodule Piano.Core.User do
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer
  
  attributes do
    uuid_primary_key :id
    
    attribute :external_id, :string do
      allow_nil? false
      description "Platform-specific ID (Telegram user_id)"
    end
    
    attribute :platform, :atom do
      constraints one_of: [:telegram, :liveview, :api]
      allow_nil? false
    end
    
    attribute :username, :string
    attribute :display_name, :string
    
    attribute :role, :atom do
      constraints one_of: [:admin, :user, :guest]
      default :user
    end
    
    attribute :preferences, :map do
      default %{}
    end
    
    timestamps()
  end
  
  identities do
    identity :unique_platform_user, [:platform, :external_id]
  end
end

# lib/piano/core/user_surface.ex  
defmodule Piano.Core.UserSurface do
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer
  
  @moduledoc """
  Many-to-many join between users and surfaces with role overrides.
  Allows different permissions based on context (DM vs group chat).
  """
  
  attributes do
    uuid_primary_key :id
    
    attribute :context_type, :atom do
      constraints one_of: [:dm, :group_chat, :channel]
      allow_nil? false
    end
    
    attribute :role_override, :atom do
      constraints one_of: [:admin, :user, :guest, :inherit]
      default :inherit
    end
    
    attribute :permissions, :map do
      default %{}
      description "Granular permissions: can_restart_codex, can_switch_profile, etc."
    end
    
    timestamps()
  end
  
  relationships do
    belongs_to :user, Piano.Core.User
    belongs_to :surface, Piano.Core.Surface
  end
end
```

### Interaction Mode Detection

```elixir
# lib/piano/telegram/handler.ex
defp detect_interaction_mode(msg) do
  chat_type = msg.chat.type
  user_id = msg.from.id
  
  cond do
    chat_type == "private" -> :user_dm
    chat_type in ["group", "supergroup"] and is_admin?(msg.chat.id, user_id) -> :admin_in_group
    chat_type in ["group", "supergroup"] -> :user_in_group
    true -> :unknown
  end
end

defp is_admin?(chat_id, user_id) do
  case ExGram.get_chat_member(chat_id, user_id) do
    {:ok, %{status: status}} when status in ["administrator", "creator"] -> true
    _ -> false
  end
end
```

### Permission Enforcement

```elixir
# lib/piano/telegram/bot_v2.ex
def handle({:command, :restartcodex, msg}, context) do
  user = get_or_create_user(msg.from, :telegram)
  mode = detect_interaction_mode(msg)
  
  if can_execute?(user, :restartcodex, mode) do
    # Existing logic
  else
    answer(context, "You don't have permission to restart Codex in this context.")
  end
end

defp can_execute?(user, action, mode) do
  permissions = load_effective_permissions(user, mode)
  Map.get(permissions, action, false)
end
```

## 2. LiveView Surface Implementation

### Architecture

```elixir
# lib/piano_web/live/surface_live.ex
defmodule PianoWeb.SurfaceLive do
  use PianoWeb, :live_view
  
  @moduledoc """
  LiveView implementation of the Piano.Surface protocol.
  Provides feature parity with Telegram surface.
  """
  
  alias Piano.Surface.Context
  
  @impl true
  def mount(%{"surface_id" => surface_id}, session, socket) do
    # Authenticate user
    user = authenticate(session)
    
    # Create or load surface
    {:ok, surface} = get_or_create_liveview_surface(surface_id, user)
    
    # Subscribe to thread events
    if connected?(socket) do
      subscribe_to_thread_updates(surface.id)
    end
    
    socket =
      socket
      |> assign(:surface, surface)
      |> assign(:user, user)
      |> assign(:current_thread, nil)
      |> assign(:messages, [])
      |> assign(:status, :idle)
      |> assign(:streaming_content, "")
    
    {:ok, socket}
  end
  
  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    # Similar to Telegram handler but push to socket
    {:ok, reply_to} = create_placeholder_message(socket.assigns.surface)
    {:ok, interaction} = create_interaction(text, reply_to)
    
    socket = 
      socket
      |> assign(:status, :processing)
      |> push_event("processing_started", %{interaction_id: interaction.id})
    
    # Start turn asynchronously
    Task.start(fn ->
      Piano.Codex.start_turn(interaction)
    end)
    
    {:noreply, socket}
  end
end
```

### Surface Protocol Implementation

```elixir
# lib/piano_web/live/surface_protocol.ex
defimpl Piano.Surface, for: PianoWeb.Liveview.Surface do
  alias PianoWeb.Endpoint
  
  def on_turn_started(surface, context, _params) do
    broadcast(surface.id, "turn_started", %{
      turn_id: context.turn_id,
      status: "thinking..."
    })
  end
  
  def on_turn_completed(surface, context, params) do
    broadcast(surface.id, "turn_completed", %{
      response: extract_response(context, params),
      tool_summary: build_tool_summary(context)
    })
  end
  
  def on_item_started(surface, context, params) do
    case summarize_item(params) do
      nil -> {:ok, :noop}
      summary -> 
        broadcast(surface.id, "item_started", summary)
        {:ok, :sent}
    end
  end
  
  def on_agent_message_delta(surface, _context, params) do
    # Unlike Telegram, we support streaming in LiveView
    broadcast(surface.id, "message_delta", %{
      delta: params["delta"]
    })
  end
  
  def send_thread_transcript(surface, thread_data) do
    transcript = Piano.Transcript.Builder.from_thread_response(thread_data)
    
    broadcast(surface.id, "transcript_ready", %{
      transcript: transcript,
      filename: "transcript_#{thread_data["thread"]["id"]}.md"
    })
  end
  
  defp broadcast(surface_id, event, payload) do
    Endpoint.broadcast("surface:#{surface_id}", event, payload)
  end
end
```

### UI Components

```heex
<%# lib/piano_web/live/surface_live.html.heex %>
<div id="surface-@surface.id" phx-hook="SurfaceUI">
  <div class="messages-container" id="messages" phx-update="stream">
    <%= for {dom_id, message} <- @streams.messages do %>
      <.message_component message={message} dom_id={dom_id} />
    <% end %>
  </div>
  
  <%= if @status == :processing do %>
    <.processing_indicator progress={@processing_progress} />
  <% end %>
  
  <form phx-submit="send_message" phx-hook="MessageForm">
    <textarea 
      name="message" 
      placeholder="Type your message..."
      phx-keydown="maybe_submit"
      phx-key="Enter"
    />
    <button type="submit" disabled={@status == :processing}>
      Send
    </button>
  </form>
  
  <%= if @streaming_content != "" do %>
    <div class="streaming-message">
      <%= raw(format_streaming_content(@streaming_content)) %>
    </div>
  <% end %>
  
  <div class="toolbar">
    <button phx-click="new_thread">New Thread</button>
    <button phx-click="get_transcript">Download Transcript</button>
    <button phx-click="show_thread_history">History</button>
  </div>
</div>
```

### Surface Switching Support

```elixir
# lib/piano/core/thread.ex - Add surface switching
defmodule Piano.Core.Thread do
  # Add relationship
  relationships do
    has_many :surface_links, Piano.Core.ThreadSurfaceLink
  end
end

# lib/piano/core/thread_surface_link.ex
defmodule Piano.Core.ThreadSurfaceLink do
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :surface_type, :atom  # :telegram, :liveview
    attribute :surface_identifier, :string
    attribute :is_primary, :boolean, default: false
    timestamps()
  end
  
  relationships do
    belongs_to :thread, Piano.Core.Thread
  end
end

# Switch surface while preserving thread
def switch_surface(thread_id, new_surface_type, user) do
  {:ok, thread} = Ash.get(Piano.Core.Thread, thread_id)
  
  # Create new surface reference
  {:ok, _link} = Ash.create(Piano.Core.ThreadSurfaceLink, %{
    thread_id: thread.id,
    surface_type: new_surface_type,
    surface_identifier: generate_surface_id(user, new_surface_type),
    is_primary: true
  })
  
  # Notify all connected surfaces
  Piano.Codex.Notifications.notify_thread_surface_change(thread)
end
```

## 3. Local Tools Surface (Device Control)

### Concept: Device Surface Protocol

```elixir
# lib/piano/local_device/surface.ex
defmodule Piano.LocalDevice.Surface do
  @moduledoc """
  Surface implementation for local hardware devices.
  Supports remote phones, cameras, IoT devices, etc.
  """
  
  defstruct [:device_id, :device_type, :connection]
  
  @type t :: %__MODULE__{
    device_id: String.t(),
    device_type: :phone | :camera | :smart_speaker | :custom,
    connection: pid() | nil
  }
end

# Protocol implementation
defimpl Piano.Surface, for: Piano.LocalDevice.Surface do
  def on_turn_completed(surface, context, params) do
    # Convert text to speech for smart speakers
    if surface.device_type == :smart_speaker do
      text = extract_response(context, params)
      speak(surface, text)
    end
  end
  
  def on_approval_required(surface, context, params) do
    # Send push notification to phone for approval
    if surface.device_type == :phone do
      send_push_notification(surface, context, params)
    end
  end
end
```

### Example: Remote Phone Camera

```elixir
# lib/piano/local_device/phone_camera_tool.ex
defmodule Piano.LocalDevice.PhoneCameraTool do
  @moduledoc """
  MCP tool for capturing images from connected phone cameras.
  Requires companion app on phone.
  """
  
  def tool_definition do
    %{
      name: "phone_camera_capture",
      description: "Captures an image from the connected phone camera",
      parameters: %{
        type: "object",
        properties: %{
          camera: %{
            type: "string",
            enum: ["front", "back"],
            default: "back"
          },
          flash: %{
            type: "boolean",
            default: false
          }
        }
      }
    }
  end
  
  def handle_tool_call(args, %{device_pid: pid}) do
    # Send command to phone companion app via WebSocket
    GenServer.call(pid, {:capture_image, args})
  end
end

# Connection management
defmodule Piano.LocalDevice.ConnectionManager do
  use GenServer
  
  def init(_) do
    # Start WebSocket server for device connections
    {:ok, _} = Phoenix.Transports.WebSocket.start_link(...)
    {:ok, %{devices: %{}}}
  end
  
  def handle_info({:device_connected, device_id, socket}, state) do
    # Register device and create surface
    surface = %Piano.LocalDevice.Surface{
      device_id: device_id,
      device_type: detect_device_type(device_id),
      connection: socket
    }
    
    {:ok, _} = register_device_surface(surface)
    {:noreply, %{state | devices: Map.put(state.devices, device_id, surface)}}
  end
end
```

## 4. Enhanced Agent Skills

### SOUL.md - Personality Shaping

Create at `.piano/SOUL.md`:

```markdown
# Agent Personality Configuration

## Core Identity
You are Piano, a helpful AI assistant focused on software engineering tasks.
You communicate in a friendly, professional manner with occasional wit.

## Communication Style
- Be concise but thorough
- Use technical terminology appropriately
- Explain complex concepts with analogies when helpful
- Ask clarifying questions when requirements are ambiguous

## Behavioral Guidelines
- Always validate assumptions before executing destructive operations
- Proactively suggest improvements or catch potential issues
- Respect user preferences for interaction style (can be configured per user)
- Maintain context across conversation threads

## Expertise Areas
- Elixir and Phoenix development
- Database design and optimization
- Web scraping and browser automation
- Telegram bot development
- System architecture

## Response Patterns
- Code changes: Provide summary + diff preview
- Questions: Direct answer with follow-up suggestions
- Errors: Clear explanation + recovery steps
- Success: Confirmation + next step recommendations
```

### TOOLS.md - MCP Tool Usage Guide

Create at `.piano/TOOLS.md`:

```markdown
# MCP Tool Usage Guide

## Overview
This document explains how to use the available MCP tools effectively.
These tools are accessible via the Model Context Protocol (MCP) endpoint.

## Available Tools

### 1. web_fetch
**Purpose:** Extract clean, LLM-friendly content from web pages.

**Best Practices:**
- Use for static content extraction
- Specify format based on use case:
  - `text` - General content extraction
  - `markdown` - Preserves structure (headings, lists)
  - `html` - When you need raw markup
- Always validate URLs before fetching
- Handle 403 errors by trying alternative approaches

**Example Workflow:**
```
User: "What does the Elixir getting started guide say about processes?"
1. Identify URL: https://elixir-lang.org/getting-started/processes.html
2. Call web_fetch with format: "markdown"
3. Extract relevant sections
4. Provide summary with citations
```

### 2. browser_visit
**Purpose:** Navigate JavaScript-heavy sites requiring browser rendering.

**Best Practices:**
- Use when web_fetch returns insufficient content
- Enable screenshots for visual confirmation
- Take screenshots after interactions (click, input)
- Use structured format for complex pages
- Check current_url after navigation to confirm success

**Multi-Step Workflows:**
```
Task: "Check my Gmail inbox"
1. browser_visit to gmail.com
2. If not logged in, stop and inform user
3. browser_find for email selectors
4. Extract structured content
5. browser_screenshot for visual confirmation
```

### 3. browser_click
**Purpose:** Interact with page elements.

**Best Practices:**
- Always verify element exists with browser_find first
- Use specific CSS selectors (prefer IDs over classes)
- Wait for page to settle after clicks (built-in)
- Handle StaleElementReference errors gracefully

### 4. browser_input
**Purpose:** Fill form fields.

**Best Practices:**
- Clear existing content before input when needed
- Verify field accepts input type
- Handle autocomplete/autofill gracefully

## Advanced Patterns

### Handling Failures
1. **Timeout:** Retry with increased timeout
2. **403/Block:** Try alternative user agent
3. **Element Not Found:** Broaden selector or check if dynamic content

### Combining Tools
- web_fetch for initial content assessment
- browser_visit if dynamic content detected
- browser_find + click for navigation
- screenshot for visual validation

## Multi-Step Instructions

When tasks require multiple tool calls:

1. **Plan:** Outline steps before execution
2. **Validate:** Check state between steps
3. **Confirm:** Show intermediate results
4. **Recover:** Have fallback strategies

Example:
```
User: "Book a flight from NYC to LA"
1. Visit travel site
2. Find and click "Flights" tab
3. Input origin: "NYC"
4. Input destination: "LA"
5. Click search
6. Extract flight options
7. Present to user for selection
```

## Rate Limiting & Ethics
- Respect robots.txt
- Don't overload servers (add delays between requests)
- Handle CAPTCHAs by asking user for assistance
- Cache results when appropriate
```

### Skills Loading System

```elixir
# lib/piano/skills/loader.ex
defmodule Piano.Skills.Loader do
  @moduledoc """
  Loads and validates skills from .piano/skills/ directory.
  """
  
  @skill_dir ".piano/skills"
  
  def load_skills do
    @skill_dir
    |> Path.expand()
    |> File.ls!()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&load_skill/1)
    |> Enum.reject(&is_nil/1)
  end
  
  defp load_skill(dir) do
    skill_file = Path.join(dir, "SKILL.md")
    
    if File.exists?(skill_file) do
      case YamlElixir.read_from_file(skill_file) do
        {:ok, %{"frontmatter" => frontmatter, "content" => content}} ->
          %Piano.Skills.Skill{
            id: frontmatter["id"],
            name: frontmatter["name"],
            description: frontmatter["description"],
            instructions: content,
            tools: frontmatter["tools"] || [],
            mcp_servers: frontmatter["mcp_servers"] || []
          }
        _ -> nil
      end
    end
  end
end

# Usage in Agent
defmodule Piano.Core.Agent do
  attributes do
    attribute :skills, {:array, :map} do
      default []
    end
  end
  
  def get_effective_instructions(agent) do
    base = agent.base_instructions || ""
    soul = load_soul_md()
    tools = load_tools_md()
    skills = load_agent_skills(agent)
    
    """
    #{soul}
    
    #{tools}
    
    #{Enum.map_join(skills, "\n\n", & &1.instructions)}
    
    #{base}
    """
  end
end
```

## 5. Memory Management System

### Architecture

```elixir
# lib/piano/memory/store.ex
defmodule Piano.Memory.Store do
  @moduledoc """
  Vector-based semantic memory storage using pgvector (PostgreSQL).
  Falls back to SQLite for simple deployments.
  """
  
  def store_memory(user_id, content, metadata \\ %{}) do
    embedding = generate_embedding(content)
    
    Ash.create(Piano.Memory.Entry, %{
      user_id: user_id,
      content: content,
      embedding: embedding,
      metadata: metadata,
      importance_score: calculate_importance(content)
    })
  end
  
  def recall_relevant(user_id, query, limit \\ 5) do
    query_embedding = generate_embedding(query)
    
    Piano.Memory.Entry
    |> Ash.Query.for_read(:semantic_search, %{
      user_id: user_id,
      embedding: query_embedding,
      limit: limit
    })
    |> Ash.read()
  end
  
  defp generate_embedding(text) do
    # Call to embedding service (OpenAI, local model, etc.)
    Piano.EmbeddingService.embed(text)
  end
end

# Schema
defmodule Piano.Memory.Entry do
  use Ash.Resource,
    domain: Piano.Memory,
    data_layer: AshPostgres.DataLayer  # For pgvector support
  
  attributes do
    uuid_primary_key :id
    attribute :user_id, :uuid, allow_nil?: false
    attribute :content, :string, allow_nil?: false
    attribute :embedding, :vector  # pgvector type
    attribute :metadata, :map, default: %{}
    attribute :importance_score, :float
    attribute :last_accessed, :utc_datetime_usec
    timestamps()
  end
  
  actions do
    read :semantic_search do
      argument :embedding, :vector, allow_nil?: false
      argument :limit, :integer, default: 5
      
      prepare fn query, _context ->
        # Use pgvector cosine similarity
        query
        |> Ash.Query.filter(
          fragment("embedding <=> ? < 0.3", ^Ash.Query.get_argument(query, :embedding))
        )
        |> Ash.Query.sort(fragment("embedding <=> ?", ^Ash.Query.get_argument(query, :embedding)))
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
      end
    end
  end
end
```

### Integration with Interactions

```elixir
# lib/piano/codex.ex
def start_turn(interaction, opts \\ []) do
  with {:ok, interaction} <- load_interaction(interaction),
       {:ok, thread} <- resolve_thread(interaction),
       {:ok, memories} <- load_relevant_memories(interaction),
       {:ok, interaction} <- update_interaction_thread(interaction, thread) do
    
    # Enhance prompt with relevant memories
    enhanced_message = enhance_with_memories(interaction.original_message, memories)
    
    # Proceed with enhanced message
    ...
  end
end

defp load_relevant_memories(interaction) do
  user = get_user_from_interaction(interaction)
  
  # Retrieve memories relevant to the current query
  Piano.Memory.Store.recall_relevant(user.id, interaction.original_message)
end

defp enhance_with_memories(message, memories) do
  if Enum.empty?(memories) do
    message
  else
    context = Enum.map_join(memories, "\n", & &1.content)
    
    """
    Context from previous conversations:
    #{context}
    
    Current query:
    #{message}
    """
  end
end
```

## 6. Multimodality Support

### Image Processing

```elixir
# lib/piano/multimodal/image_processor.ex
defmodule Piano.Multimodal.ImageProcessor do
  @moduledoc """
  Handle image inputs from Telegram and other surfaces.
  """
  
  def process_image(url_or_file_id, opts \\ []) do
    # Download image
    {:ok, image_data} = download_image(url_or_file_id)
    
    # Analyze with vision model
    {:ok, description} = analyze_with_vision(image_data, opts)
    
    {:ok, description, image_data}
  end
  
  defp analyze_with_vision(image_data, opts) do
    # Call to vision-capable model (GPT-4V, Claude, etc.)
    model = opts[:model] || "gpt-4-vision-preview"
    
    Piano.VisionClient.analyze(%{
      model: model,
      messages: [
        %{
          role: "user",
          content: [
            %{type: "text", text: opts[:prompt] || "Describe this image"},
            %{type: "image_url", image_url: %{url: "data:image/png;base64,#{Base.encode64(image_data)}"}}
          ]
        }
      ]
    })
  end
end

# Telegram integration
# lib/piano/telegram/handler.ex
def handle_message(%{photo: photos} = msg, _text) when is_list(photos) do
  # Get largest photo
  photo = Enum.max_by(photos, & &1.file_size)
  
  # Download from Telegram
  {:ok, file} = ExGram.get_file(photo.file_id)
  {:ok, image_data} = download_telegram_file(file.file_path)
  
  # Process image
  {:ok, description, _} = Piano.Multimodal.ImageProcessor.process_image(image_data)
  
  # Create interaction with image description
  prompt = "[User shared an image: #{description}]"
  
  # Continue with normal flow
  ...
end
```

### Voice/Message Audio

```elixir
# lib/piano/multimodal/audio_processor.ex
defmodule Piano.Multimodal.AudioProcessor do
  def transcribe_audio(file_id, opts \\ []) do
    # Download audio file
    {:ok, audio_data} = download_audio(file_id)
    
    # Transcribe with Whisper or similar
    {:ok, transcription} = Piano.TranscriptionService.transcribe(audio_data, opts)
    
    {:ok, transcription}
  end
end
```

### Surface-Aware Multimodal Support

```elixir
# lib/piano/surface.ex - Extend protocol

defprotocol Piano.Surface do
  # ... existing callbacks ...
  
  @doc """
  Called when media (image, audio, video) is received.
  Returns {:ok, processed_content} or {:error, reason}.
  """
  @spec on_media_received(t(), Context.t(), map()) :: {:ok, map()} | {:error, term()}
  def on_media_received(surface, context, media_info)
  
  @doc """
  Send media to the surface (e.g., image response).
  """
  @spec send_media(t(), binary(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def send_media(surface, data, mime_type, opts)
end

# Telegram implementation
defimpl Piano.Surface, for: Piano.Telegram.Surface do
  def on_media_received(surface, context, %{type: :photo, file_id: file_id}) do
    {:ok, file} = ExGram.get_file(file_id)
    {:ok, image_data} = download_file(file.file_path)
    {:ok, description} = Piano.Multimodal.ImageProcessor.process_image(image_data)
    
    {:ok, %{type: :image, description: description, data: image_data}}
  end
  
  def send_media(surface, data, "image/png", opts) do
    TelegramSurface.send_photo(surface.chat_id, data, opts)
  end
end

# LiveView implementation  
defimpl Piano.Surface, for: PianoWeb.Liveview.Surface do
  def on_media_received(surface, context, %{type: :file, data: data, mime_type: mime_type}) do
    # Store file temporarily
    path = store_temp_file(data, mime_type)
    
    # Process based on type
    case mime_type do
      "image/" <> _ ->
        {:ok, description} = Piano.Multimodal.ImageProcessor.process_image(data)
        {:ok, %{type: :image, description: description, path: path}}
        
      "audio/" <> _ ->
        {:ok, transcription} = Piano.Multimodal.AudioProcessor.transcribe(data)
        {:ok, %{type: :audio, transcription: transcription, path: path}}
        
      _ ->
        {:ok, %{type: :file, path: path, mime_type: mime_type}}
    end
  end
  
  def send_media(surface, data, mime_type, opts) do
    # Stream to LiveView client
    PianoWeb.Endpoint.broadcast(
      "surface:#{surface.id}",
      "media_response",
      %{
        data: Base.encode64(data),
        mime_type: mime_type,
        caption: opts[:caption]
      }
    )
  end
end
```

## Implementation Roadmap

### Phase 1 (Weeks 1-2): Foundation
- [ ] Implement User and UserSurface resources
- [ ] Add authentication and permission system
- [ ] Update AGENTS.md to reference SOUL.md and TOOLS.md

### Phase 2 (Weeks 3-4): LiveView Surface
- [ ] Create LiveView surface implementation
- [ ] Implement surface switching functionality
- [ ] Add streaming message support

### Phase 3 (Weeks 5-6): Memory System
- [ ] Add PostgreSQL/pgvector support
- [ ] Implement Memory.Store module
- [ ] Integrate with interaction flow

### Phase 4 (Weeks 7-8): Skills Framework
- [ ] Create skills loader
- [ ] Implement SOUL.md and TOOLS.md parsing
- [ ] Add per-agent skill configuration

### Phase 5 (Weeks 9-10): Multimodality
- [ ] Add image processing support
- [ ] Implement audio transcription
- [ ] Extend Surface protocol for media

### Phase 6 (Weeks 11-12): Local Tools
- [ ] Design device surface protocol
- [ ] Implement phone camera integration
- [ ] Create connection manager

## Success Metrics

- **User System**: Support 1000+ users with distinct preferences
- **LiveView Surface**: Feature parity with Telegram
- **Memory**: <100ms recall latency, 90% relevance accuracy
- **Multimodality**: Support images, audio, documents
- **Skills**: Load 10+ skills without performance degradation

---

**Note:** These three reports provide a comprehensive review of the Piano architecture, security gaps, and product improvement opportunities. Priority should be given to P0 security items before implementing new features.
