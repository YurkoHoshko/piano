defmodule Piano.Surface.Router do
  @moduledoc """
  Routes reply_to strings to appropriate surface implementations.
  """

  alias Piano.Mock.Surface, as: MockSurface
  alias Piano.Telegram.Surface, as: TelegramSurface

  @doc """
  Parse a reply_to string and return the appropriate surface struct.

  ## Examples

      iex> Piano.Surface.Router.parse("telegram:123456:789")
      {:ok, %Piano.Telegram.Surface{chat_id: 123456, message_id: 789}}

      iex> Piano.Surface.Router.parse("mock:test-123")
      {:ok, %Piano.Mock.Surface{mock_id: "test-123"}}

      iex> Piano.Surface.Router.parse("unknown:foo")
      :error
  """
  @spec parse(String.t()) :: {:ok, struct()} | :error
  def parse(reply_to) do
    cond do
      String.starts_with?(reply_to, "telegram:") -> TelegramSurface.parse(reply_to)
      String.starts_with?(reply_to, "mock:") -> MockSurface.parse(reply_to)
      String.starts_with?(reply_to, "liveview:") -> {:ok, :liveview_not_implemented}
      true -> :error
    end
  end

  @doc """
  Determine the surface app type from a reply_to string.

  ## Examples

      iex> Piano.Surface.Router.app_type("telegram:123:456")
      :telegram

      iex> Piano.Surface.Router.app_type("mock:test")
      :mock

      iex> Piano.Surface.Router.app_type("unknown:foo")
      :unknown
  """
  @spec app_type(String.t()) :: atom()
  def app_type("telegram:" <> _), do: :telegram
  def app_type("mock:" <> _), do: :mock
  def app_type("liveview:" <> _), do: :liveview
  def app_type(_), do: :unknown

  @doc """
  Extract the base identifier from a reply_to string.
  For telegram, this strips the message_id to get just the chat_id.
  For mock, this returns the mock_id.

  ## Examples

      iex> Piano.Surface.Router.base_identifier("telegram:123:456")
      "123"

      iex> Piano.Surface.Router.base_identifier("mock:test-123")
      "test-123"
  """
  @spec base_identifier(String.t()) :: String.t() | nil
  def base_identifier("telegram:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [chat_id, _msg_id] -> chat_id
      [chat_id] -> chat_id
    end
  end

  def base_identifier("mock:" <> mock_id), do: mock_id
  def base_identifier("liveview:" <> session_id), do: session_id
  def base_identifier(_), do: nil

  @doc """
  Determine if a surface type is single-user by default.
  Telegram DMs (positive chat_id) are single-user.
  Telegram groups (negative chat_id) are multi-user.
  Mock surfaces are always single-user.
  """
  @spec single_user?(String.t()) :: boolean()
  def single_user?("telegram:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [chat_id_str, _] ->
        case Integer.parse(chat_id_str) do
          {chat_id, ""} -> chat_id > 0
          _ -> true
        end

      _ ->
        true
    end
  end

  def single_user?("mock:" <> _), do: true
  def single_user?("liveview:" <> _), do: true
  def single_user?(_), do: true
end
