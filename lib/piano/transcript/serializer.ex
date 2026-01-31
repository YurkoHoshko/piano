defprotocol Piano.Transcript.Serializer do
  @moduledoc """
  Protocol for serializing events to transcript format.

  Each event struct implements this to define how it appears in transcripts.
  """

  @doc """
  Serializes the event to a string for the transcript.
  Returns nil if the event shouldn't appear in the transcript.
  """
  @spec to_transcript(term()) :: String.t() | nil
  def to_transcript(event)
end
