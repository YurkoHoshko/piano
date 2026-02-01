# ASR/TTS Integration Status

## Current Status

### ASR (Automatic Speech Recognition) - ⚠️ PARTIALLY WORKING
- **Model**: Qwen3-ASR-0.6B
- **Integration**: Added to llama-swap config
- **Issue**: Model crashes on startup with exit code 1
- **Root Cause**: Likely vLLM incompatibility with Qwen3-ASR model format
- **Note**: Qwen3-ASR uses a custom architecture that may not be fully supported by vLLM

### TTS (Text-to-Speech) - 🔄 IN PROGRESS  
- **Model**: Qwen3-TTS-12Hz-1.7B-Base (planned)
- **Goal**: Enable voice responses from the agent

## Architecture

```
User Voice → Telegram → Piano App → llama-swap → vLLM → Qwen3-ASR → Text → Agent
                                                                ↓
Agent Text Response → TTS Service → Audio File → Telegram → User
```

## Known Issues

### ASR Model Loading Failure
The vLLM process exits immediately when trying to load Qwen3-ASR-0.6B:
```
[WARN] <qwen3-asr-0.6b> ExitError >> exit status 1, exit code: 1
```

**Potential Solutions:**
1. Use transformers backend instead of vLLM for ASR
2. Convert model to GGUF format (if possible)
3. Use Qwen's official Docker image with their inference server
4. Use separate Python service with qwen-asr package directly

### TTS Model Considerations
Qwen3-TTS is a text-to-speech model that generates audio from text. Similar architecture concerns apply.

## Next Steps

1. **Debug ASR**: Try alternative deployment methods
2. **Implement TTS**: Add TTS client and service
3. **Integration**: Connect TTS to Telegram bot for voice responses

## Files Modified

- `infra/llama-swap/config.yaml` - Added qwen3-asr-0.6b model
- `infra/llama-swap/Dockerfile` - Added Python + vLLM support
- `infra/llama-swap/build_llama_server.nu` - Build script (from yadro)
- `lib/piano/tools/transcription_client.ex` - HTTP client for ASR API
- `lib/piano/telegram/bot_v2.ex` - Voice message handling with transcription
