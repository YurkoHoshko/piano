defmodule Piano.Telegram.Handler do
  @moduledoc """
  Barebone Telegram message handler.

  Receives messages, sends placeholder, creates Interaction, and triggers the pipeline.
  """

  require Logger

  alias Piano.Core.Interaction
  alias Piano.Telegram.Surface, as: TelegramSurface

  @doc """
  Handle an incoming Telegram text message.

  1. Sends a placeholder message
  2. Creates an Interaction with reply_to
  3. Starts the Codex turn
  """
  @spec handle_message(integer(), String.t()) :: {:ok, Interaction.t()} | {:error, term()}
  def handle_message(chat_id, text) do
    with {:ok, reply_to} <- TelegramSurface.send_placeholder(chat_id),
         {:ok, interaction} <- create_interaction(text, reply_to),
         {:ok, interaction} <- start_turn(interaction) do
      Logger.info("Telegram message processed",
        chat_id: chat_id,
        interaction_id: interaction.id
      )

      {:ok, interaction}
    else
      {:error, reason} = error ->
        Logger.error("Failed to handle Telegram message",
          chat_id: chat_id,
          error: inspect(reason)
        )

        error
    end
  end

  defp create_interaction(text, reply_to) do
    Ash.create(Interaction, %{original_message: text, reply_to: reply_to}, action: :create)
  end

  defp start_turn(interaction) do
    case Piano.Codex.start_turn(interaction) do
      {:ok, interaction} -> {:ok, interaction}
      {:error, reason} -> {:error, {:codex_start_failed, reason}}
    end
  end
end
