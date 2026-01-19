ExUnit.start()

# Define Mox mock for LLM
Mox.defmock(Piano.LLM.Mock, for: Piano.LLM)
