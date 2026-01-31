defmodule Piano.Codex.Responses do
  @moduledoc """
  Structured responses from the Codex app-server protocol.

  This module provides Elixir structs for RPC responses from the Codex app-server.
  Unlike events (which are notifications), responses are sent in reply to specific
  requests and contain request IDs.
  """

  # ============================================================================
  # Response Types
  # ============================================================================

  defmodule ThreadStartResponse do
    @moduledoc "Response from thread/start request."
    defstruct [:request_id, :thread_id, :raw_response]

    @type t :: %__MODULE__{
            request_id: String.t(),
            thread_id: String.t(),
            raw_response: map()
          }

    @doc """
    Extracts the thread ID from the response.
    """
    @spec extract_thread_id(map()) :: String.t() | nil
    def extract_thread_id(response) when is_map(response) do
      Kernel.get_in(response, ["result", "thread", "id"]) ||
        Kernel.get_in(response, ["result", "threadId"]) ||
        Kernel.get_in(response, ["result", "thread", "threadId"])
    end

    def extract_thread_id(_), do: nil
  end

  defmodule TurnStartResponse do
    @moduledoc "Response from turn/start request."
    defstruct [:request_id, :turn_id, :error, :raw_response]

    @type t :: %__MODULE__{
            request_id: String.t(),
            turn_id: String.t() | nil,
            error: map() | nil,
            raw_response: map()
          }

    @doc """
    Extracts the turn ID from the response.
    """
    @spec extract_turn_id(map()) :: String.t() | nil
    def extract_turn_id(response) when is_map(response) do
      Kernel.get_in(response, ["result", "turn", "id"]) ||
        Kernel.get_in(response, ["result", "turnId"])
    end

    def extract_turn_id(_), do: nil

    @doc """
    Extracts error from the response.
    """
    @spec extract_error(map()) :: map() | nil
    def extract_error(response) when is_map(response) do
      response["error"]
    end

    def extract_error(_), do: nil

    @doc """
    Checks if the response indicates an error.
    """
    @spec error?(map()) :: boolean()
    def error?(response) when is_map(response) do
      Map.has_key?(response, "error")
    end

    def error?(_), do: false
  end

  defmodule AccountReadResponse do
    @moduledoc "Response from account/read request."
    defstruct [:request_id, :account, :requires_openai_auth, :error, :raw_response]

    @type t :: %__MODULE__{
            request_id: String.t(),
            account: map() | nil,
            requires_openai_auth: boolean(),
            error: map() | nil,
            raw_response: map()
          }
  end

  defmodule ConfigReadResponse do
    @moduledoc "Response from config/read request."
    defstruct [:request_id, :config, :error, :raw_response]

    @type t :: %__MODULE__{
            request_id: String.t(),
            config: map(),
            error: map() | nil,
            raw_response: map()
          }
  end

  defmodule LoginStartResponse do
    @moduledoc "Response from account/login/start request."
    defstruct [:request_id, :auth_url, :login_id, :error, :raw_response]

    @type t :: %__MODULE__{
            request_id: String.t(),
            auth_url: String.t() | nil,
            login_id: String.t() | nil,
            error: map() | nil,
            raw_response: map()
          }

    @doc """
    Extracts login info from the response.
    """
    @spec extract_login_info(map()) :: {String.t() | nil, String.t() | nil}
    def extract_login_info(response) when is_map(response) do
      auth_url = Kernel.get_in(response, ["result", "authUrl"])
      login_id = Kernel.get_in(response, ["result", "loginId"])
      {auth_url, login_id}
    end

    def extract_login_info(_), do: {nil, nil}

    @doc """
    Checks if the response contains an error.
    """
    @spec error?(map()) :: boolean()
    def error?(response) when is_map(response) do
      Map.has_key?(response, "error")
    end

    def error?(_), do: false
  end

  defmodule GenericResponse do
    @moduledoc "Generic response for simple success/error cases."
    defstruct [:request_id, :success, :error, :raw_response]

    @type t :: %__MODULE__{
            request_id: String.t(),
            success: boolean(),
            error: map() | nil,
            raw_response: map()
          }

    @doc """
    Creates a generic response from raw payload.
    """
    @spec from_payload(map()) :: t()
    def from_payload(%{"id" => id} = payload) do
      error = payload["error"]

      %__MODULE__{
        request_id: to_string(id),
        success: is_nil(error),
        error: error,
        raw_response: payload
      }
    end

    def from_payload(payload) do
      %__MODULE__{
        request_id: "unknown",
        success: false,
        error: %{"message" => "Invalid response format"},
        raw_response: payload
      }
    end
  end

  defmodule ThreadTranscriptResponse do
    @moduledoc "Response from thread/read request containing transcript data."
    defstruct [:request_id, :thread, :turns, :error, :raw_response]

    @type t :: %__MODULE__{
            request_id: String.t(),
            thread: map() | nil,
            turns: list(map()),
            error: map() | nil,
            raw_response: map()
          }

    @doc """
    Extracts thread data from the response.
    """
    @spec extract_thread_data(map()) :: {map() | nil, list(map())}
    def extract_thread_data(response) when is_map(response) do
      thread = Kernel.get_in(response, ["result", "thread"]) || response["thread"]
      # Turns may be at: result.turns, result.thread.turns, or thread.turns
      turns =
        Kernel.get_in(response, ["result", "turns"]) ||
          Kernel.get_in(response, ["result", "thread", "turns"]) ||
          Kernel.get_in(response, ["thread", "turns"]) ||
          []

      {thread, turns}
    end

    def extract_thread_data(_), do: {nil, []}
  end

  # ============================================================================
  # Response Parsing
  # ============================================================================

  @type response ::
          ThreadStartResponse.t()
          | TurnStartResponse.t()
          | AccountReadResponse.t()
          | ConfigReadResponse.t()
          | LoginStartResponse.t()
          | ThreadTranscriptResponse.t()
          | GenericResponse.t()

  @doc """
  Parses a raw RPC response into a structured response struct.

  ## Parameters

  - `request_type` - Atom identifying the request type (:thread_start, :turn_start, etc.)
  - `payload` - The raw response map with "id" and "result"/"error" keys

  ## Returns

  A response struct appropriate for the request type.

  ## Examples

      iex> Piano.Codex.Responses.parse(:thread_start, %{"id" => 1, "result" => %{"thread" => %{"id" => "thr_123"}}})
      %Piano.Codex.Responses.ThreadStartResponse{request_id: "1", thread_id: "thr_123", ...}
  """
  @spec parse(atom(), map()) :: response()
  def parse(request_type, payload)

  def parse(:thread_start, %{"id" => id} = payload) do
    %ThreadStartResponse{
      request_id: to_string(id),
      thread_id: ThreadStartResponse.extract_thread_id(payload),
      raw_response: payload
    }
  end

  def parse(:turn_start, %{"id" => id} = payload) do
    %TurnStartResponse{
      request_id: to_string(id),
      turn_id: TurnStartResponse.extract_turn_id(payload),
      error: TurnStartResponse.extract_error(payload),
      raw_response: payload
    }
  end

  def parse(:account_read, %{"id" => id} = payload) do
    result = payload["result"] || %{}

    %AccountReadResponse{
      request_id: to_string(id),
      account: result["account"] || result,
      requires_openai_auth: result["requiresOpenaiAuth"] == true,
      error: payload["error"],
      raw_response: payload
    }
  end

  def parse(:config_read, %{"id" => id} = payload) do
    result = payload["result"] || %{}

    %ConfigReadResponse{
      request_id: to_string(id),
      config: result["config"] || %{},
      error: payload["error"],
      raw_response: payload
    }
  end

  def parse(:account_login_start, %{"id" => id} = payload) do
    {auth_url, login_id} = LoginStartResponse.extract_login_info(payload)

    %LoginStartResponse{
      request_id: to_string(id),
      auth_url: auth_url,
      login_id: login_id,
      error: payload["error"],
      raw_response: payload
    }
  end

  def parse(:thread_transcript, %{"id" => id} = payload) do
    {thread, turns} = ThreadTranscriptResponse.extract_thread_data(payload)

    %ThreadTranscriptResponse{
      request_id: to_string(id),
      thread: thread,
      turns: turns,
      error: payload["error"],
      raw_response: payload
    }
  end

  def parse(:account_logout, payload) do
    GenericResponse.from_payload(payload)
  end

  def parse(:account_login_cancel, payload) do
    GenericResponse.from_payload(payload)
  end

  def parse(_request_type, payload) do
    GenericResponse.from_payload(payload)
  end

  @doc """
  Extracts the request ID from a response payload.
  """
  @spec extract_request_id(map()) :: String.t() | nil
  def extract_request_id(%{"id" => id}) when is_binary(id), do: id
  def extract_request_id(%{"id" => id}) when is_integer(id), do: to_string(id)
  def extract_request_id(_), do: nil

  @doc """
  Checks if a response contains an error.
  """
  @spec error?(map()) :: boolean()
  def error?(%{"error" => _}), do: true
  def error?(_), do: false

  @doc """
  Extracts error information from a response.
  """
  @spec get_error(map()) :: map() | nil
  def get_error(%{"error" => error}) when is_map(error), do: error
  def get_error(%{"error" => error}) when is_binary(error), do: %{"message" => error}
  def get_error(_), do: nil
end
