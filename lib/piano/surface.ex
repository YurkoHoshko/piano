defprotocol Piano.Surface do
  @moduledoc """
  Protocol for Surface implementations.

  Surfaces are the interface between external messaging platforms
  (Telegram, LiveView, etc.) and the Piano orchestration system.

  ## Lifecycle Callbacks

  These callbacks are invoked during interaction processing:
  - `on_turn_started/3` - Called when a Codex turn begins
  - `on_turn_completed/3` - Called when a Codex turn finishes
  - `on_item_started/3` - Called when an item (message, tool call, etc.) starts
  - `on_item_completed/3` - Called when an item completes
  - `on_agent_message_delta/3` - Called for streaming agent message updates
  - `on_approval_required/3` - Called when user approval is needed

  ## Thread Operations

  - `send_thread_transcript/2` - Sends a formatted thread transcript to the surface

  ## Context

  All lifecycle callbacks receive a `Piano.Surface.Context` struct as the second
  parameter. This provides unified access to core constructs:
  - `:interaction` - The Core.Interaction (may be nil for thread-level events)
  - `:turn_id` - Codex turn ID
  - `:thread_id` - Codex thread ID
  - `:thread` - Core.Thread struct (if loaded)
  - `:event` - Parsed Codex.Events struct
  - `:raw_params` - Raw event parameters

  This allows surface implementations to work universally with interaction/turn/thread
  constructs and access the same amount of context regardless of the event type.
  """
  @fallback_to_any true

  alias Piano.Surface.Context

  @doc """
  Called when a Codex turn starts processing.
  """
  @spec on_turn_started(t(), Context.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_turn_started(surface, context, params)

  @doc """
  Called when a Codex turn completes.
  """
  @spec on_turn_completed(t(), Context.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_turn_completed(surface, context, params)

  @doc """
  Called when an item (message, tool call, file change, etc.) starts.
  """
  @spec on_item_started(t(), Context.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_item_started(surface, context, params)

  @doc """
  Called when an item completes.
  """
  @spec on_item_completed(t(), Context.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_item_completed(surface, context, params)

  @doc """
  Called for streaming agent message updates (deltas).
  """
  @spec on_agent_message_delta(t(), Context.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_agent_message_delta(surface, context, params)

  @doc """
  Called when user approval is required for a tool call or file change.
  """
  @spec on_approval_required(t(), Context.t(), map()) :: {:ok, term()} | {:ok, :noop}
  def on_approval_required(surface, context, params)

  @doc """
  Send a thread transcript to the surface.

  The `thread_data` map contains the raw Codex `thread/read` response with:
  - `"thread"` - Thread metadata (id, etc.)
  - `"turns"` - List of turns, each containing items

  Implementations should format the transcript appropriately for their platform
  (e.g., Telegram may send as a file if too long).
  """
  @spec send_thread_transcript(t(), map()) :: {:ok, term()} | {:error, term()}
  def send_thread_transcript(surface, thread_data)

  @doc """
  Called when account login process starts.

  Receives the login response with auth_url, login_id, and optional error.
  """
  @spec on_account_login_start(t(), map()) :: :ok
  def on_account_login_start(surface, response)

  @doc """
  Called when account read response is received.

  Receives the account response with account info and optional error.
  """
  @spec on_account_read(t(), map()) :: :ok
  def on_account_read(surface, response)

  @doc """
  Called when account logout response is received.

  Receives the generic response with optional error.
  """
  @spec on_account_logout(t(), map()) :: :ok
  def on_account_logout(surface, response)

  @doc """
  Called when thread transcript response is received.

  Receives the thread transcript response with thread data, turns, optional error,
  and optional placeholder_id for removing temporary messages.
  """
  @spec on_thread_transcript(t(), map(), integer() | nil) :: :ok
  def on_thread_transcript(surface, response, placeholder_id)

  @doc """
  Send a message to the surface.

  Used to send notifications, updates, or results to the user.
  The message can be plain text or markdown depending on surface support.

  ## Examples

      Piano.Surface.send_message(surface, "Task completed successfully!")
      Piano.Surface.send_message(surface, "## Results\n\n- Item 1\n- Item 2")
  """
  @spec send_message(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def send_message(surface, message)

  @doc """
  Send a file to the surface.

  Used to send files (documents, images, etc.) to the user.
  The `file` can be:
  - A binary (file contents)
  - A path to a file on disk
  - A tuple `{:binary, binary, filename}` for sending binary with a filename

  Options:
  - `:filename` - Override the filename for display
  - `:caption` - Optional caption/description for the file
  - `:mime_type` - MIME type hint

  ## Examples

      Piano.Surface.send_file(surface, "/path/to/file.pdf")
      Piano.Surface.send_file(surface, {:binary, content, "report.txt"}, caption: "Generated report")
  """
  @spec send_file(t(), binary() | String.t() | {:binary, binary(), String.t()}, keyword()) ::
          {:ok, term()} | {:error, term()}
  def send_file(surface, file, opts \\ [])
end

defimpl Piano.Surface, for: Any do
  @moduledoc false

  def on_turn_started(_surface, _context, _params), do: {:ok, :noop}
  def on_turn_completed(_surface, _context, _params), do: {:ok, :noop}
  def on_item_started(_surface, _context, _params), do: {:ok, :noop}
  def on_item_completed(_surface, _context, _params), do: {:ok, :noop}
  def on_agent_message_delta(_surface, _context, _params), do: {:ok, :noop}
  def on_approval_required(_surface, _context, _params), do: {:ok, :noop}
  def send_thread_transcript(_surface, _thread_data), do: {:ok, :noop}
  def on_account_login_start(_surface, _response), do: :ok
  def on_account_read(_surface, _response), do: :ok
  def on_account_logout(_surface, _response), do: :ok
  def on_thread_transcript(_surface, _response, _placeholder_id), do: :ok
  def send_message(_surface, _message), do: {:ok, :noop}
  def send_file(_surface, _file, _opts), do: {:ok, :noop}
end
