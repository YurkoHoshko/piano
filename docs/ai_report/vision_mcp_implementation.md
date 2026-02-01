# Vision MCP Tool Implementation

## Overview

Exposes a vision-enabled model (running via llama-swap) as an MCP tool. The main agent can ask questions about images, and a smaller vision-enabled model (via Codex with `vision` profile) provides the analysis.

## Architecture

```
Main Agent (large model)
    ↓
Calls vision_analyze tool (MCP)
    ↓
Spawns Codex with `vision` profile
    ↓
Vision-enabled model (llama-swap)
    ↓
Returns analysis
```

## Implementation

### 1. Vision Tool Module

```elixir
# lib/piano/tools/vision.ex
defmodule Piano.Tools.Vision do
  @moduledoc """
  MCP tool for vision analysis using a dedicated vision-enabled model.
  
  This tool spawns a separate Codex process with the 'vision' profile
  to analyze images using a vision-capable model (e.g., GPT-4V, Claude 3,
  or local vision model via llama-swap).
  """
  
  require Logger
  
  alias Piano.Codex.Config, as: CodexConfig
  
  @vision_profile :vision
  @default_timeout 60_000
  
  def tool_definition do
    %{
      name: "vision_analyze",
      description: """
      Analyze an image using a vision-enabled AI model. Use this when:
      - User shares an image and asks about its contents
      - You need to read text from an image (OCR)
      - You need to identify objects, people, or scenes
      - You need to analyze diagrams, charts, or screenshots
      
      Returns a detailed description of the image contents.
      """,
      parameters: %{
        type: "object",
        properties: %{
          image_data: %{
            type: "string",
            description: "Base64-encoded image data or URL to the image"
          },
          mime_type: %{
            type: "string",
            enum: ["image/jpeg", "image/png", "image/webp", "image/gif"],
            default: "image/jpeg",
            description: "MIME type of the image"
          },
          prompt: %{
            type: "string",
            description: "Specific question or instructions for the vision analysis",
            default: "Describe what you see in this image in detail."
          },
          max_tokens: %{
            type: "integer",
            description: "Maximum tokens for the response",
            default: 1000
          }
        },
        required: ["image_data"]
      }
    }
  end
  
  @doc """
  Handle the vision_analyze tool call.
  """
  def handle_tool_call(%{"image_data" => image_data} = args, _opts) do
    prompt = args["prompt"] || "Describe what you see in this image in detail."
    mime_type = args["mime_type"] || "image/jpeg"
    max_tokens = args["max_tokens"] || 1000
    
    # Check if vision profile exists
    unless vision_profile_available?() do
      return_profile_error()
    end
    
    # Prepare the image for the vision model
    with {:ok, prepared_image} <- prepare_image(image_data, mime_type),
         {:ok, result} <- run_vision_analysis(prepared_image, prompt, max_tokens) do
      
      {:ok, %{
        analysis: result,
        prompt: prompt,
        model_used: get_vision_model_name()
      }}
    else
      {:error, :invalid_image} ->
        {:error, "Invalid image data provided"}
        
      {:error, :vision_profile_not_configured} ->
        return_profile_error()
        
      {:error, reason} ->
        Logger.error("Vision analysis failed: #{inspect(reason)}")
        {:error, "Vision analysis failed: #{inspect(reason)}"}
    end
  end
  
  def handle_tool_call(_args, _opts) do
    {:error, "Missing required parameter: image_data"}
  end
  
  # Private functions
  
  defp vision_profile_available? do
    profiles = CodexConfig.profile_names()
    @vision_profile in profiles
  end
  
  defp return_profile_error do
    current = CodexConfig.current_profile!()
    available = CodexConfig.profile_names() |> Enum.join(", ")
    
    {:error, """
    Vision analysis not available. Current profile '#{current}' does not support vision.
    
    To enable vision:
    1. Configure a 'vision' profile in Codex with a vision-capable model
    2. Or switch to a vision-enabled profile
    
    Available profiles: #{available}
    """}
  end
  
  defp prepare_image("http" <> _ = url, _mime_type) do
    # URL provided - fetch the image
    case Req.get(url, max_redirects: 3) do
      {:ok, %{status: 200, body: body}} ->
        mime_type = guess_mime_type_from_binary(body)
        base64 = Base.encode64(body)
        {:ok, %{data: base64, mime_type: mime_type, source: :url}}
        
      {:ok, %{status: status}} ->
        {:error, "Failed to fetch image: HTTP #{status}"}
        
      {:error, reason} ->
        {:error, "Failed to fetch image: #{inspect(reason)}"}
    end
  end
  
  defp prepare_image("data:" <> _ = data_uri, _mime_type) do
    # Data URI provided - parse it
    case parse_data_uri(data_uri) do
      {:ok, mime_type, base64_data} ->
        {:ok, %{data: base64_data, mime_type: mime_type, source: :data_uri}}
        
      :error ->
        {:error, :invalid_image}
    end
  end
  
  defp prepare_image(base64_data, mime_type) do
    # Assume it's already base64
    # Validate it's valid base64
    case Base.decode64(base64_data) do
      {:ok, _} ->
        {:ok, %{data: base64_data, mime_type: mime_type, source: :base64}}
        
      :error ->
        {:error, :invalid_image}
    end
  end
  
  defp run_vision_analysis(image, prompt, max_tokens) do
    # Start a temporary Codex client with vision profile
    client = start_vision_client()
    
    try do
      # Build the vision prompt with image
      vision_input = build_vision_input(image, prompt)
      
      # Run the analysis through Codex
      case execute_vision_turn(client, vision_input, max_tokens) do
        {:ok, response} ->
          {:ok, response}
          
        {:error, reason} ->
          {:error, reason}
      end
    after
      stop_vision_client(client)
    end
  end
  
  defp build_vision_input(%{data: base64_data, mime_type: mime_type}, prompt) do
    # Format for vision models (OpenAI/GPT-4V style)
    # This format works with most vision-capable models
    [
      %{
        type: "text",
        text: prompt
      },
      %{
        type: "image_url",
        image_url: %{
          url: "data:#{mime_type};base64,#{base64_data}",
          detail: "high"
        }
      }
    ]
  end
  
  defp execute_vision_turn(client, input, max_tokens) do
    # Create a thread
    request_id = System.unique_integer([:positive])
    
    # Send thread/start request
    :ok = Piano.Codex.Client.send_request(
      client,
      "thread/start",
      %{
        profile: @vision_profile,
        max_tokens: max_tokens
      },
      request_id
    )
    
    # Wait for thread to be ready and get thread ID
    case wait_for_thread(client, request_id, 10_000) do
      {:ok, thread_id} ->
        # Start a turn with the vision input
        turn_request_id = System.unique_integer([:positive])
        
        :ok = Piano.Codex.Client.send_request(
          client,
          "turn/start",
          %{
            threadId: thread_id,
            input: input,
            max_tokens: max_tokens
          },
          turn_request_id
        )
        
        # Wait for turn completion
        wait_for_turn_completion(client, turn_request_id, 60_000)
        
      {:error, reason} ->
        {:error, "Failed to start vision thread: #{inspect(reason)}"}
    end
  end
  
  defp wait_for_thread(client, request_id, timeout) do
    receive do
      {:codex_response, ^request_id, response} ->
        case response do
          %{"result" => %{"thread" => %{"id" => thread_id}}} ->
            {:ok, thread_id}
            
          %{"error" => error} ->
            {:error, error}
            
          _ ->
            {:error, :invalid_response}
        end
    after
      timeout ->
        {:error, :timeout}
    end
  end
  
  defp wait_for_turn_completion(client, request_id, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    # Collect streaming responses
    collect_response(client, request_id, "", start_time, timeout)
  end
  
  defp collect_response(client, request_id, accumulator, start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    if elapsed > timeout do
      {:error, :timeout}
    else
      remaining = timeout - elapsed
      
      receive do
        {:codex_event, %{"method" => "turn/completed", "params" => params}} ->
          # Extract the final message
          items = params["turn"]["items"] || []
          
          message = 
            items
            |> Enum.filter(&(&1["type"] == "message"))
            |> List.last()
            |> case do
              nil -> accumulator
              item -> extract_text_from_item(item)
            end
            
          {:ok, message}
          
        {:codex_event, %{"method" => "item/completed", "params" => params}} ->
          # Accumulate message content
          item = params["item"]
          
          if item["type"] == "message" do
            text = extract_text_from_item(item)
            collect_response(client, request_id, accumulator <> text, start_time, timeout)
          else
            collect_response(client, request_id, accumulator, start_time, timeout)
          end
          
        {:codex_event, %{"method" => "agent/message/delta", "params" => params}} ->
          # Stream deltas
          delta = params["delta"]["content"] || ""
          collect_response(client, request_id, accumulator <> delta, start_time, timeout)
          
        _ ->
          collect_response(client, request_id, accumulator, start_time, timeout)
          
      after
        remaining ->
          {:ok, accumulator}  # Return what we have
      end
    end
  end
  
  defp extract_text_from_item(item) do
    content = item["content"] || []
    
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(&(&1["text"]))
    |> Enum.join("")
  end
  
  defp start_vision_client do
    # Start a temporary Codex client process
    {:ok, pid} = Piano.Codex.Client.start_link([])
    pid
  end
  
  defp stop_vision_client(pid) do
    GenServer.stop(pid, :normal)
  end
  
  defp get_vision_model_name do
    # Get model name from vision profile config
    case Application.get_env(:piano, :codex_profiles)[@vision_profile] do
      nil -> "vision-model"
      config -> config[:model] || "vision-model"
    end
  end
  
  defp parse_data_uri("data:" <> rest) do
    case String.split(rest, ";base64,", parts: 2) do
      [mime_type, base64_data] ->
        {:ok, mime_type, base64_data}
        
      _ ->
        :error
    end
  end
  
  defp parse_data_uri(_), do: :error
  
  defp guess_mime_type_from_binary(<<0xFF, 0xD8, _::binary>>), do: "image/jpeg"
  defp guess_mime_type_from_binary(<<0x89, 0x50, 0x4E, 0x47, _::binary>>), do: "image/png"
  defp guess_mime_type_from_binary(<<"GIF87a", _::binary>>), do: "image/gif"
  defp guess_mime_type_from_binary(<<"GIF89a", _::binary>>), do: "image/gif"
  defp guess_mime_type_from_binary(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp guess_mime_type_from_binary(_), do: "image/jpeg"
end
```

### 2. Update MCP Tools Registration

```elixir
# lib/piano/tools/mcp.ex - Add vision tool

def tool_definitions do
  [
    # ... existing tools ...
    Piano.Tools.Vision.tool_definition()
  ]
end

def handle_tool_call("vision_analyze", arguments, opts) do
  Piano.Tools.Vision.handle_tool_call(arguments, opts)
end
```

### 3. Vision Profile Configuration

```elixir
# config/config.exs - Add vision profile

config :piano, Piano.Codex.Config,
  codex_command: "codex",
  current_profile: :fast,
  allowed_profiles: [:smart, :fast, :expensive, :replay, :experimental, :gfq, :vision],
  profiles: %{
    vision: %{
      model: "gpt-4-vision-preview",  # or local model via llama-swap
      description: "Vision-capable model for image analysis",
      max_tokens: 2000,
      temperature: 0.7,
      # For llama-swap integration:
      base_url: System.get_env("LLAMA_SWAP_URL", "http://localhost:8080"),
      api_key: System.get_env("LLAMA_SWAP_API_KEY", "dummy-key")
    }
  }
```

### 4. Telegram Image Handler

```elixir
# lib/piano/telegram/handler.ex - Add image handling

defmodule Piano.Telegram.Handler do
  # ... existing code ...
  
  @doc """
  Handle an incoming message with photos.
  """
  def handle_message(%{photo: photos} = msg, _text) when is_list(photos) and length(photos) > 0 do
    # Get the largest photo (best quality)
    photo = Enum.max_by(photos, & &1.file_size)
    
    chat = msg.chat
    chat_id = chat.id
    chat_type = chat_type(msg)
    
    # Check if vision is supported
    unless vision_supported?() do
      Piano.Telegram.Surface.send_message(
        chat_id,
        "❌ Image analysis is not available. Please configure a 'vision' profile in Codex to enable image support.",
        []
      )
      
      return {:error, :vision_not_supported}
    end
    
    # Download the photo
    case download_telegram_photo(photo.file_id) do
      {:ok, image_data, mime_type} ->
        # Create interaction with image
        with {:ok, reply_to} <- Piano.Telegram.Surface.send_placeholder(chat_id),
             {:ok, interaction} <- create_image_interaction(msg, image_data, mime_type, reply_to) do
          
          Logger.info("Telegram photo processed",
            chat_id: chat_id,
            interaction_id: interaction.id,
            photo_size: byte_size(image_data)
          )
          
          # Start the turn
          case start_turn(interaction) do
            {:ok, _} -> {:ok, :processed}
            error -> error
          end
        end
        
      {:error, reason} ->
        Logger.error("Failed to download Telegram photo",
          chat_id: chat_id,
          error: inspect(reason)
        )
        
        Piano.Telegram.Surface.send_message(
          chat_id,
          "❌ Failed to process the image. Please try again.",
          []
        )
        
        {:error, reason}
    end
  end
  
  def handle_message(%{document: %{mime_type: mime_type} = doc} = msg, _text) 
      when mime_type in ["image/jpeg", "image/png", "image/webp"] do
    # Handle images sent as documents
    handle_document_image(msg, doc)
  end
  
  # Private functions
  
  defp vision_supported? do
    profiles = Piano.Codex.Config.profile_names()
    :vision in profiles
  end
  
  defp download_telegram_photo(file_id) do
    with {:ok, file} <- ExGram.get_file(file_id),
         {:ok, %{body: image_data}} <- Req.get(file_download_url(file.file_path)) do
      
      mime_type = Piano.Tools.Vision.guess_mime_type_from_binary(image_data)
      {:ok, image_data, mime_type}
    end
  end
  
  defp file_download_url(file_path) do
    token = Application.get_env(:ex_gram, :token)
    "https://api.telegram.org/file/bot#{token}/#{file_path}"
  end
  
  defp create_image_interaction(msg, image_data, mime_type, reply_to) do
    # Encode image to base64
    base64_image = Base.encode64(image_data)
    
    # Create prompt that tells Codex there's an image
    # The main agent will then use vision_analyze tool if needed
    prompt = """
    [User shared an image]
    
    Image data: data:#{mime_type};base64,#{Base.encode64(binary_slice(base64_image, 0, 100))}...
    Image size: #{byte_size(image_data)} bytes
    
    To analyze this image, use the vision_analyze tool with:
    - image_data: "#{base64_image}"
    - mime_type: "#{mime_type}"
    """
    
    # Create the interaction
    Ash.create(Piano.Core.Interaction, %{
      original_message: prompt,
      reply_to: reply_to,
      metadata: %{
        has_image: true,
        image_mime_type: mime_type,
        image_size: byte_size(image_data)
      }
    })
  end
  
  defp binary_slice(binary, start, length) do
    binary
    |> :binary.part(start, min(length, byte_size(binary) - start))
  end
  
  defp chat_type(%{chat: %{type: type}}), do: type
  defp chat_type(_), do: "unknown"
end
```

### 5. Enhanced Interaction Resource for Images

```elixir
# lib/piano/core/interaction.ex - Add image support

defmodule Piano.Core.Interaction do
  # ... existing code ...
  
  attributes do
    # ... existing attributes ...
    
    attribute :metadata, :map do
      default %{}
      description "Additional data like image info, attachments, etc."
    end
  end
  
  # Add action to handle image interactions
  actions do
    # ... existing actions ...
    
    create :create_with_image do
      accept [:original_message, :reply_to, :thread_id, :metadata]
    end
  end
end
```

### 6. Skill for Using Vision Tool

```elixir
# .piano/skills/vision/SKILL.md

# Vision Analysis Skill

## Overview

You have access to a `vision_analyze` tool that can analyze images using a dedicated vision-enabled AI model. This is useful when users share images or when you need to understand visual content.

## When to Use

**Always use vision_analyze when:**
- User sends a photo and asks "what is this?"
- User shares a screenshot and asks for help
- User sends a document image that needs OCR
- You need to read text from an image
- User asks about objects, people, or scenes in an image

**Don't use when:**
- User just says "hi" with a photo (greeting only)
- The image is clearly just an emoji or sticker
- You've already analyzed the image in the current conversation

## How to Use

### Basic Usage

```
User: [sends photo of a dog] "What breed is this?"

Your action:
→ vision_analyze
  image_data: "<base64-encoded-image>"
  prompt: "What breed of dog is in this image?"

Response: "That appears to be a Golden Retriever..."
```

### Advanced Prompts

Be specific in your prompts to get better results:

```
❌ Bad: "Describe this"
✅ Good: "Describe the main objects in this image and their colors"

❌ Bad: "What's this?"
✅ Good: "What type of flower is shown in this image? Identify the species if possible."

❌ Bad: "Read this"
✅ Good: "Transcribe all the text visible in this image, preserving the layout."
```

### Multiple Images

If user sends multiple images, analyze them separately or together:

```
User: [sends 2 photos] "Which one is better?"

Option 1 - Separate:
→ vision_analyze (image 1)
→ vision_analyze (image 2)
→ Compare the results yourself

Option 2 - Combined (if supported by model):
→ vision_analyze (both images)
  prompt: "Compare these two images and tell me which one is better and why"
```

## Image Data Sources

### From Telegram

When a user sends an image via Telegram, the image data is provided in the interaction metadata:

```
[User shared an image]

Image data: data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ...
Image size: 12458 bytes

To analyze this image, use the vision_analyze tool...
```

Extract the base64 data and pass it to the tool.

### From URLs

You can also analyze images from URLs:

```
User: "What's in this image? https://example.com/photo.jpg"

→ vision_analyze
  image_data: "https://example.com/photo.jpg"
  prompt: "Describe what you see in this image"
```

## Common Use Cases

### 1. Screenshot Analysis

```
User: [screenshot of error message] "What's wrong?"

→ vision_analyze
  image_data: "<screenshot>"
  prompt: "This is a screenshot of an error. Read the error message and explain what went wrong and how to fix it."
```

### 2. Document OCR

```
User: [photo of receipt] "Add this to my expenses"

→ vision_analyze
  image_data: "<receipt>"
  prompt: "Read all text from this receipt. Extract: vendor name, date, items purchased, and total amount."
```

### 3. Object Identification

```
User: [photo of plant] "What plant is this?"

→ vision_analyze
  image_data: "<plant>"
  prompt: "Identify this plant species. Include common name and scientific name if possible."
```

### 4. Chart/Diagram Analysis

```
User: [chart image] "Explain this data"

→ vision_analyze
  image_data: "<chart>"
  prompt: "Analyze this chart. What type is it? What trends or patterns do you see? What are the key insights?"
```

### 5. Code Review

```
User: [screenshot of code] "Can you improve this?"

→ vision_analyze
  image_data: "<code>"
  prompt: "This is a screenshot of code. Transcribe it and suggest improvements or identify bugs."
```

## Error Handling

If vision analysis fails:

1. **Profile not configured**: 
   - Tell user: "Vision analysis isn't available right now. The admin needs to configure a vision profile."
   
2. **Image too large**:
   - Try: "The image is too large. Can you send a smaller version or crop to the relevant area?"
   
3. **Analysis unclear**:
   - Ask user: "I couldn't clearly understand this image. Can you describe what I'm looking at or send a clearer image?"

## Tips

1. **Crop when helpful**: If only part of the image matters, mention it: "Focus on the error message in the top right"

2. **Multiple passes**: For complex images, do multiple analyses:
   - First: "Describe what's in this image"
   - Then: "Now focus on the text in the corner - what does it say?"

3. **Combine with tools**: After vision analysis, use other tools:
   - See a URL in an image → Use web_fetch to visit it
   - See code → Use that code in your response
   - See an error → Use your knowledge to suggest fixes

4. **Respect privacy**: If image contains sensitive info (IDs, addresses), warn user and don't expose in response

## Examples

### Example 1: Menu Translation
```
User: [photo of restaurant menu in Italian] "What's good here?"

→ vision_analyze
  image_data: "<menu>"
  prompt: "This is an Italian restaurant menu. List all the pasta dishes with their prices and descriptions."

Response: "Based on the menu, I'd recommend the 'Tagliatelle al Ragù' (€14) which is a traditional Bolognese pasta..."
```

### Example 2: UI Feedback
```
User: [screenshot of their app] "What do you think of my design?"

→ vision_analyze
  image_data: "<screenshot>"
  prompt: "This is a web app UI. Analyze the design: layout, colors, typography, usability. Suggest improvements."

Response: "The color scheme is good but I notice the contrast on the buttons could be better for accessibility..."
```

### Example 3: Debug Help
```
User: [screenshot of terminal error] "Why is this failing?"

→ vision_analyze
  image_data: "<terminal>"
  prompt: "Read all the text from this terminal output. Identify the error, the command that failed, and suggest how to fix it."

Response: "The error shows 'ModuleNotFoundError: No module named requests'. You need to install it with 'pip install requests'."
```
