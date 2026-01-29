defmodule Piano.Telegram.Surface do
  @moduledoc """
  Telegram surface implementation for the Piano.Surface protocol.

  Parses `reply_to` strings like "telegram:<chat_id>:<message_id>" and
  provides callbacks for updating Telegram messages during interaction lifecycle.
  """

  alias Piano.Telegram.API

  defstruct [:chat_id, :message_id]

  @type t :: %__MODULE__{
          chat_id: integer(),
          message_id: integer()
        }

  @doc """
  Parse a reply_to string into a Telegram surface struct.

  ## Examples

      iex> Piano.Telegram.Surface.parse("telegram:123456:-789")
      {:ok, %Piano.Telegram.Surface{chat_id: 123456, message_id: -789}}

      iex> Piano.Telegram.Surface.parse("liveview:abc")
      :error
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse("telegram:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [chat_id_str, message_id_str] ->
        with {chat_id, ""} <- Integer.parse(chat_id_str),
             {message_id, ""} <- Integer.parse(message_id_str) do
          {:ok, %__MODULE__{chat_id: chat_id, message_id: message_id}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def parse(_), do: :error

  @doc """
  Build a reply_to string from chat_id and message_id.
  """
  @spec build_reply_to(integer(), integer()) :: String.t()
  def build_reply_to(chat_id, message_id) do
    "telegram:#{chat_id}:#{message_id}"
  end

  @doc """
  Send a placeholder message and return the reply_to string.
  """
  @spec send_placeholder(integer(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def send_placeholder(chat_id, text \\ "⏳ Processing...") do
    case API.send_message(chat_id, text) do
      {:ok, %{message_id: message_id}} ->
        {:ok, build_reply_to(chat_id, message_id)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Update the placeholder message with new text.
  """
  @spec update_message(t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def update_message(%__MODULE__{chat_id: chat_id, message_id: message_id}, text, opts \\ []) do
    API.edit_message_text(chat_id, message_id, text, opts)
  end
end

defimpl Piano.Surface, for: Piano.Telegram.Surface do
  alias Piano.Telegram.Surface, as: TelegramSurface

  def on_turn_started(_surface, _interaction, _params) do
    {:ok, :noop}
  end

  def on_turn_completed(surface, interaction, _params) do
    response = interaction.response || "✅ Done"
    TelegramSurface.update_message(surface, response)
  end

  def on_item_started(_surface, _interaction, _params) do
    {:ok, :noop}
  end

  def on_item_completed(_surface, _interaction, _params) do
    {:ok, :noop}
  end

  def on_agent_message_delta(surface, _interaction, params) do
    case get_in(params, ["item", "text"]) do
      text when is_binary(text) and text != "" ->
        TelegramSurface.update_message(surface, text)

      _ ->
        {:ok, :noop}
    end
  end

  def on_approval_required(surface, _interaction, _params) do
    TelegramSurface.update_message(surface, "⚠️ Approval required")
  end
end
