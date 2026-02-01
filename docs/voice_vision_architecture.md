# Voice & Vision Integration Architecture

## Overview
llama-swap now manages both traditional GGUF models (via llama.cpp) AND multimodal models (via vLLM) on the same port. Models swap automatically when requested.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    llama-swap (port 8000)                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  llama.cpp      │  │     vLLM        │  │   vLLM       │ │
│  │  (GGUF models)  │  │   (ASR)         │  │  (Vision)    │ │
│  │                 │  │                 │  │              │ │
│  │ • glm-47-flash  │  │ qwen3-asr-0.6b  │  │ qwen3-vl-4b  │ │
│  │ • devstral      │  │                 │  │              │ │
│  │ • qwen-coder    │  │ Voice→Text      │  │ Image→Text   │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│                                                             │
│  All models share port 8000, swap on-demand                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Piano App (port 4000)                  │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ Telegram Bot    │  │   Codex Agent   │                   │
│  │                 │  │                 │                   │
│  │ Voice messages  │  │ LLM reasoning   │                   │
│  │ → ASR (vLLM)    │  │                 │                   │
│  │                 │  │ Vision queries  │                   │
│  │ Image messages  │  │ → VL (vLLM)     │                   │
│  │ → VL (vLLM)     │  │                 │                   │
│  └─────────────────┘  └─────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

## Model Configuration

### ASR (Voice → Text)
- **Model**: Qwen3-ASR-0.6B
- **Type**: vLLM (HuggingFace format)
- **GPU Memory**: 30% of GPU 0
- **Max Context**: 8192 tokens
- **Alias**: `asr`, `transcription`
- **Status**: ✅ Working

### Vision (Image → Text)
- **Model**: Qwen3-VL-4B-Instruct
- **Type**: vLLM (HuggingFace format)
- **GPU Memory**: 40% of GPU 0
- **Max Context**: 16384 tokens
- **Images**: Up to 4 per prompt
- **Alias**: `vision`, `vl`, `ocr`
- **Status**: 🔄 Model downloading

### Text Models (GGUF via llama.cpp)
- glm-47-flash
- glm-47-flash-q
- devstral
- qwen-coder
- etc.

## File Structure

```
~/.cache/llama.cpp/
├── qwen3-asr/              # ASR model (1.8GB) ✅ Ready
│   ├── config.json
│   ├── model.safetensors
│   └── vocab.json
├── qwen3-vl-vllm/          # Vision model (downloading)
│   ├── config.json         ✅
│   ├── model-0000x-of-00004.safetensors  🔄
│   └── ...
├── *.gguf                  # Text models (existing)
└── mmproj-*.gguf           # Vision projections
```

## Usage Examples

### ASR (Voice Transcription)
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-asr-0.6b",
    "messages": [{
      "role": "user",
      "content": [{
        "type": "audio_url",
        "audio_url": {"url": "https://example.com/audio.wav"}
      }]
    }]
  }'
```

### Vision (OCR/Image Understanding)
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-vl-4b-vllm",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "What's in this image?"},
        {"type": "image_url", "image_url": {"url": "https://example.com/image.png"}}
      ]
    }]
  }'
```

### Text Generation (existing)
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-47-flash",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Implementation Notes

1. **llama-swap manages swapping**: When you request a different model, llama-swap stops the current one and starts the new one
2. **vLLM and llama.cpp coexist**: Both run inside the same llama-swap container
3. **Port sharing**: All models share port 8000, managed by llama-swap proxy
4. **GPU allocation**: Both vLLM models use GPU 0 (they don't run simultaneously)

## Next Steps

1. ✅ ASR working - voice messages can be transcribed
2. 🔄 Vision model downloading (will enable OCR and image understanding)
3. ⏳ TTS (Text-to-Speech) - for voice responses
4. ⏳ Integration with Telegram bot

## Files Modified

- `infra/llama-swap/config.yaml` - Added ASR and Vision vLLM models
- `docker-compose.yml` - Single llama-swap service (removed separate containers)
- `lib/piano/tools/transcription_client.ex` - ASR HTTP client
- `lib/piano/telegram/bot_v2.ex` - Voice message handling
