# Qwen3-ASR Integration Plan

## Overview
Integrate Qwen3-ASR (automatic speech recognition) using Pythonx to transcribe voice messages from Telegram.

## Architecture

```
Telegram Voice Message
        ↓
Download to intake folder (.ogg format)
        ↓
TranscriptionService.transcribe(file_path)
        ↓
Pythonx → Qwen3-ASR model → Text
        ↓
Send transcription to agent as text message
```

## Implementation Steps

### 1. Dependencies (mix.exs)

Add to deps:
```elixir
{:pythonx, "~> 0.4"}
```

### 2. Create Transcription Module

Create `lib/piano/tools/transcription_service.ex`:

```elixir
defmodule Piano.Tools.TranscriptionService do
  @moduledoc """
  GenServer-based transcription service using Qwen3-ASR via Pythonx.
  
  Loads the ASR model once at startup and reuses it for all transcriptions.
  """
  
  use GenServer
  require Logger
  
  # Use smaller 0.6B model for faster inference, or 1.7B for better accuracy
  @default_model "Qwen/Qwen3-ASR-0.6B"
  
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Transcribe an audio file to text.
  
  ## Options
    * `:language` - Force specific language (e.g., "English", "Chinese"), or nil for auto-detect
    * `:timeout` - Maximum time to wait for transcription (default: 60_000ms)
  
  ## Examples
      {:ok, text} = TranscriptionService.transcribe("/path/to/audio.ogg")
      {:ok, text} = TranscriptionService.transcribe("/path/to/audio.ogg", language: "English")
  """
  @spec transcribe(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(file_path, opts \\ []) do
    GenServer.call(__MODULE__, {:transcribe, file_path, opts}, Keyword.get(opts, :timeout, 60_000))
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    model_name = Keyword.get(opts, :model, @default_model)
    
    Logger.info("Initializing Qwen3-ASR model: #{model_name}")
    
    # Initialize Python and load the model
    {globals, _} = Pythonx.eval("""
    import torch
    from qwen_asr import Qwen3ASRModel
    import os
    
    # Suppress verbose logging
    os.environ['TRANSFORMERS_VERBOSITY'] = 'error'
    os.environ['HF_HUB_DISABLE_SYMLINKS_WARNING'] = '1'
    
    # Initialize model
    model = Qwen3ASRModel.from_pretrained(
        "#{model_name}",
        dtype=torch.bfloat16,
        device_map="cuda:0" if torch.cuda.is_available() else "cpu",
        max_inference_batch_size=1,
        max_new_tokens=256,
    )
    
    def transcribe_file(file_path, language=None):
        \"\"\"
        Transcribe audio file to text.
        
        Args:
            file_path: Path to audio file
            language: Optional language hint (e.g., "English", "Chinese")
        
        Returns:
            Tuple of (language_detected, transcription_text)
        \"\"\"
        try:
            results = model.transcribe(
                audio=file_path,
                language=language,
            )
            
            if results and len(results) > 0:
                result = results[0]
                return (result.language, result.text)
            else:
                return (None, "")
        except Exception as e:
            return (None, f"Transcription error: {str(e)}")
    """, %{})
    
    Logger.info("Qwen3-ASR model loaded successfully")
    
    {:ok, %{globals: globals, model: model_name}}
  end
  
  @impl true
  def handle_call({:transcribe, file_path, opts}, _from, state) do
    language = Keyword.get(opts, :language)
    
    Logger.info("Transcribing file", file: file_path, language: language)
    
    try do
      # Call Python transcription function
      {{lang, text}, _} = Pythonx.eval("""
      transcribe_file("#{file_path}", #{if language, do: "\"#{language}\"", else: "None"})
      """, state.globals)
      
      Logger.info("Transcription complete", language: lang, text_length: String.length(text))
      
      {:reply, {:ok, text}, state}
    catch
      error ->
        Logger.error("Transcription failed", error: inspect(error))
        {:reply, {:error, "Transcription failed: #{inspect(error)}"}, state}
    end
  end
end
```

### 3. Add to Supervision Tree

In `lib/piano/application.ex`, add to children:

```elixir
# Add after existing children
Piano.Tools.TranscriptionService
```

Or make it conditional:

```elixir
children = [
  # ... existing children
]

# Add transcription service if enabled
children = 
  if Application.get_env(:piano, :transcription_enabled, true) do
    children ++ [Piano.Tools.TranscriptionService]
  else
    children
  end
```

### 4. Integrate with Telegram Voice Handler

Modify `lib/piano/telegram/bot_v2.ex` voice handler:

```elixir
# Add alias at top
alias Piano.Tools.TranscriptionService

defp handle_file_message(:voice, voice_info, msg, context) do
  log_inbound(:voice, msg, "voice message received")
  chat_id = msg.chat.id
  
  # Get file ID
  file_id = extract_file_id(:voice, voice_info)
  
  if file_id do
    # Send acknowledgment
    %ExGram.Cnt{message: %{message_id: ack_msg_id}} =
      answer(context, "🎤 Processing voice message...")
    
    # Create intake folder
    interaction_id = "#{msg.message_id}_#{:erlang.unique_integer([:positive])}"
    intake_path = Path.join([Piano.Intake.base_dir(), "telegram", interaction_id])
    
    case Piano.Intake.create_interaction_folder("telegram", interaction_id) do
      {:ok, ^intake_path} ->
        # Download voice file
        case download_and_save_file(file_id, intake_path, :voice) do
          {:ok, file_path} ->
            # Transcribe the voice message
            case TranscriptionService.transcribe(file_path) do
              {:ok, transcription} ->
                # Update message with transcription
                TelegramSurface.edit_message_text(
                  chat_id,
                  ack_msg_id,
                  "🎤 Voice message transcribed:\n\n#{transcription}"
                )
                
                # Create prompt with transcription
                caption = Map.get(msg, :caption) || ""
                prompt = build_voice_prompt(transcription, caption, intake_path)
                
                # Pass to handler
                case Handler.handle_message_with_intake(msg, prompt, intake_path) do
                  {:ok, _interaction} -> :ok
                  {:error, reason} ->
                    Logger.error("Voice handler failed: #{inspect(reason)}")
                    :ok
                end
                
              {:error, reason} ->
                Logger.error("Transcription failed: #{inspect(reason)}")
                TelegramSurface.edit_message_text(
                  chat_id,
                  ack_msg_id,
                  "❌ Failed to transcribe voice: #{inspect(reason)}"
                )
            end
            
          {:error, reason} ->
            Logger.error("Failed to download voice file: #{inspect(reason)}")
            TelegramSurface.edit_message_text(
              chat_id,
              ack_msg_id,
              "❌ Failed to download voice file"
            )
        end
        
      {:error, reason} ->
        Logger.error("Failed to create intake folder: #{inspect(reason)}")
        TelegramSurface.edit_message_text(
          chat_id,
          ack_msg_id,
          "❌ Failed to create intake folder"
        )
    end
  else
    answer(context, "⚠️ Could not extract voice file information")
  end
end

defp build_voice_prompt(transcription, caption, intake_path) do
  base = "🎤 User sent a voice message"
  with_caption = if caption != "", do: "#{base} with caption: #{caption}", else: base
  
  """
  #{with_caption}

  **Transcription:**
  #{transcription}

  📁 **Intake Folder:** `#{intake_path}`
  Original audio file available at: `#{intake_path}/voice_*.ogg`

  Please respond to the transcribed message.
  """
end
```

### 5. Docker Configuration

Update `Dockerfile` to:
1. Install Python dependencies
2. Cache model weights
3. Enable GPU support

```dockerfile
# Add to Dockerfile after mise installation

# Install Python and pip
RUN apt-get update && apt-get install -y python3 python3-pip python3-venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create Python virtual environment
RUN python3 -m venv /opt/qwen-asr-venv
ENV PATH="/opt/qwen-asr-venv/bin:$PATH"

# Install Qwen3-ASR with CPU support (no GPU required)
# For GPU support, use: pip install qwen-asr[vllm]
RUN pip install --no-cache-dir qwen-asr torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Pre-download model weights (optional - speeds up first transcription)
# RUN python3 -c "from qwen_asr import Qwen3ASRModel; Qwen3ASRModel.from_pretrained('Qwen/Qwen3-ASR-0.6B')"
```

For GPU support in docker-compose.yml:
```yaml
services:
  piano:
    # ... existing config
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    environment:
      # ... existing env vars
      - NVIDIA_VISIBLE_DEVICES=all
      - CUDA_VISIBLE_DEVICES=0
```

### 6. Configuration

Add to `config/runtime.exs`:

```elixir
config :piano, :transcription,
  enabled: System.get_env("TRANSCRIPTION_ENABLED", "true") == "true",
  model: System.get_env("TRANSCRIPTION_MODEL", "Qwen/Qwen3-ASR-0.6B"),  # or "Qwen/Qwen3-ASR-1.7B"
  timeout: String.to_integer(System.get_env("TRANSCRIPTION_TIMEOUT", "60000"))
```

## Usage Flow

1. User sends voice message to Telegram bot
2. Bot downloads .ogg file to intake folder
3. Bot calls `TranscriptionService.transcribe(file_path)`
4. Pythonx executes Python code in embedded interpreter
5. Qwen3-ASR model processes audio and returns text
6. Bot sends transcription to agent as text message
7. Agent responds to transcribed text

## Performance Considerations

- **0.6B model**: ~2GB VRAM, fast inference, good for real-time
- **1.7B model**: ~4GB VRAM, better accuracy, slower
- **CPU fallback**: Works but much slower (~10-30x)
- **Model caching**: Model loaded once at startup, reused for all requests
- **Concurrency**: Pythonx uses single Python interpreter, transcribe calls are serialized

## Fallback Strategy

If transcription fails:
1. Log error with file path
2. Notify user transcription failed
3. Still pass audio file to agent with note that transcription failed
4. Agent can work with raw audio if needed

## Testing

Test transcription in iex:
```elixir
# Download a sample audio file first
{:ok, text} = Piano.Tools.TranscriptionService.transcribe("/path/to/test.ogg")
IO.puts(text)
```

## Next Steps

1. Add `{:pythonx, "~> 0.4"}` to mix.exs
2. Create `lib/piano/tools/transcription_service.ex`
3. Add to supervision tree in application.ex
4. Modify voice handler in bot_v2.ex
5. Update Dockerfile with Python dependencies
6. Test with sample voice messages
7. Monitor memory usage and adjust model size if needed
