defmodule Piano.TestHarness.CodexReplay do
  @moduledoc """
  Loads and matches OpenAI replay fixtures for test-only API endpoints.

  Configure with:

      config :piano, :codex_replay_paths, ["test/fixtures/codex/turns.json"]

  Fixture format (file can be a single map or a list of maps):

      {
        "match": {
          "endpoint": "chat.completions",
          "model": "gpt-4",
          "messages": [{"role": "user", "content": "Hi"}]
        },
        "response": {
          "content": "Hello!",
          "finish_reason": "stop"
        }
      }

  If response is a full OpenAI response body, it will be returned as-is.
  Otherwise, a response body is built from the `response` fields.
  """

  alias Piano.TestHarness.OpenAIReplay

  @type endpoint :: :chat_completions | :responses

  def match_fixture(endpoint, params) when endpoint in [:chat_completions, :responses] do
    params = normalize(params)
    fixtures()
    |> Enum.find_value({:error, :no_match}, fn fixture ->
      if match_entry?(fixture.entry, endpoint, params) do
        {:ok, fixture}
      else
        false
      end
    end)
  end

  def response_for(%{entry: entry} = fixture, endpoint) do
    entry = normalize(entry)
    response = Map.get(entry, "response") || Map.get(entry, "result") || %{}
    status =
      case Map.get(entry, "status") || Map.get(response, "status") do
        value when is_integer(value) -> value
        value when is_atom(value) and not is_nil(value) -> Plug.Conn.Status.code(value)
        _ -> 200
      end

    cond do
      is_map(response) and Map.has_key?(response, "body") ->
        {status, response["body"], fixture.path}

      is_map(response) and openai_body?(response) ->
        {status, response, fixture.path}

      is_map(response) ->
        {status, OpenAIReplay.build(endpoint, response), fixture.path}

      true ->
        {status, response, fixture.path}
    end
  end

  def models do
    OpenAIReplay.models()
  end

  defp fixtures do
    paths = Application.get_env(:piano, :codex_replay_paths, [])

    paths
    |> Enum.flat_map(&load_file/1)
  end

  defp load_file(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, json} <- Jason.decode(contents) do
      entries =
        case json do
          list when is_list(list) -> list
          map when is_map(map) -> [map]
          _ -> []
        end

      Enum.map(entries, fn entry -> %{path: path, entry: entry} end)
    else
      _ -> []
    end
  end

  defp match_entry?(entry, endpoint, params) when is_map(entry) do
    entry = normalize(entry)

    match =
      Map.get(entry, "match") ||
        Map.get(entry, "request") ||
        Map.get(entry, "input") ||
        %{}

    match = normalize(match)

    expected_endpoint =
      match["endpoint"] ||
        match["path"] ||
        entry["endpoint"] ||
        entry["path"]

    if endpoint_matches?(expected_endpoint, endpoint) do
      match_body =
        match
        |> Map.delete("endpoint")
        |> Map.delete("path")
        |> Map.delete("body")

      body_match =
        case Map.get(match, "body") do
          nil -> match_body
          body when is_map(body) -> normalize(body)
          _ -> match_body
        end

      subset_match?(body_match, params)
    else
      false
    end
  end

  defp match_entry?(_, _, _), do: false

  defp endpoint_matches?(nil, _endpoint), do: true
  defp endpoint_matches?("/v1/chat/completions", :chat_completions), do: true
  defp endpoint_matches?("/v1/responses", :responses), do: true
  defp endpoint_matches?("chat.completions", :chat_completions), do: true
  defp endpoint_matches?("responses", :responses), do: true
  defp endpoint_matches?(endpoint, :chat_completions) when is_binary(endpoint) do
    String.contains?(endpoint, "chat/completions")
  end

  defp endpoint_matches?(endpoint, :responses) when is_binary(endpoint) do
    String.contains?(endpoint, "/responses")
  end

  defp endpoint_matches?(_, _), do: false

  defp subset_match?(expected, actual) when is_map(expected) and is_map(actual) do
    Enum.all?(expected, fn {key, value} ->
      case Map.fetch(actual, key) do
        {:ok, actual_value} -> subset_match?(value, actual_value)
        :error -> false
      end
    end)
  end

  defp subset_match?(expected, actual) when is_list(expected) and is_list(actual) do
    expected == actual
  end

  defp subset_match?(expected, actual), do: expected == actual

  defp normalize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), normalize(v)} end)
    |> Map.new()
  end

  defp normalize(value) when is_list(value) do
    Enum.map(value, &normalize/1)
  end

  defp normalize(value), do: value

  defp openai_body?(%{"object" => "chat.completion"}), do: true
  defp openai_body?(%{"object" => "response"}), do: true
  defp openai_body?(%{"choices" => _}), do: true
  defp openai_body?(%{"output" => _}), do: true
  defp openai_body?(_), do: false
end
