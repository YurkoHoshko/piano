defmodule PianoWeb.CodexReplayController do
  use PianoWeb, :controller

  require Logger

  alias Piano.TestHarness.CodexReplay

  def chat_completions(conn, _params) do
    respond(conn, :chat_completions, conn.body_params)
  end

  def responses(conn, _params) do
    params = conn.body_params

    if wants_sse?(conn, params) do
      respond_stream(conn, :responses, params)
    else
      respond(conn, :responses, params)
    end
  end

  def models(conn, _params) do
    json(conn, CodexReplay.models())
  end

  defp respond(conn, endpoint, params) do
    Logger.debug("Codex replay #{endpoint} request: #{inspect(params)}")

    case CodexReplay.match_fixture(endpoint, params) do
      {:ok, fixture} ->
        {status, body, path} = CodexReplay.response_for(fixture, endpoint)

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("x-codex-replay", path)
        |> send_resp(status, Jason.encode!(body))

      {:error, :no_match} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "no_replay_match"}))
    end
  end

  defp respond_stream(conn, endpoint, params) do
    Logger.debug("Codex replay #{endpoint} SSE request: #{inspect(params)}")

    case CodexReplay.match_fixture(endpoint, params) do
      {:ok, fixture} ->
        {status, body, path} = CodexReplay.response_for(fixture, endpoint)

        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("x-codex-replay", path)
          |> send_chunked(status)

        stream_events(conn, body)

      {:error, :no_match} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "no_replay_match"}))
    end
  end

  defp wants_sse?(conn, params) do
    stream_param = params["stream"] in [true, "true"]
    accept = Enum.join(get_req_header(conn, "accept"), ",")
    String.contains?(accept, "text/event-stream") or stream_param
  end

  defp stream_events(conn, body) do
    events = Piano.TestHarness.OpenAIReplay.stream_events(body)

    Enum.reduce_while(events, conn, fn event, conn ->
      data = "data: " <> Jason.encode!(event) <> "\n\n"

      case Plug.Conn.chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, _} -> {:halt, conn}
      end
    end)
  end
end
