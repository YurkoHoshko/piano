ExUnit.start()

# Define Mox mock for LLM
Mox.defmock(Piano.LLM.Mock, for: Piano.LLM)

# Define Mox mock for Telegram API
Mox.defmock(Piano.Telegram.API.Mock, for: Piano.Telegram.API)
