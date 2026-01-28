# TASK-013: Telegram Bot

**Status:** pending  
**Dependencies:** TASK-009, TASK-010  
**Phase:** 6 - Telegram Bot

## Description
Create the Telegram bot that receives messages and routes them through the pipeline.

## Acceptance Criteria
- [ ] `Piano.Telegram.Bot` using ExGram
- [ ] On text message: create Surface, create Interaction, call `InteractionPipeline.enqueue`
- [ ] Handles `/start`, `/newthread` commands
- [ ] `mix compile` passes

## Implementation Notes
- Use ExGram for bot framework
- Bot token from config/env `TELEGRAM_BOT_TOKEN`
- `/start` - welcome message
- `/newthread` - archive current thread, next message starts fresh
- On text message: 
  1. Get or create Surface for chat_id
  2. Create Interaction with original_message
  3. Call InteractionPipeline.enqueue (async via Task?)
- Handle callback_query for approval inline keyboards
