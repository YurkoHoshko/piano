defmodule Piano.Telegram.Handler do
  @moduledoc """
  Barebone Telegram message handler.

  Receives messages, sends placeholder, creates Interaction, and triggers the pipeline.
  """

  require Logger

  alias Piano.Core.Interaction
  alias Piano.Core.Thread
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

  @doc """
  Force-start a new Codex thread for a Telegram chat.
  """
  @spec force_new_thread(integer()) :: {:ok, term()} | {:error, term()}
  def force_new_thread(chat_id) do
    reply_to = "telegram:#{chat_id}"

    case find_recent_thread(reply_to) do
      {:ok, thread} ->
        case Piano.Codex.force_start_thread(thread) do
          {:ok, request_id} -> {:ok, %{status: :started, request_id: request_id}}
          {:error, reason} -> {:error, {:codex_force_start_failed, reason}}
        end

      {:error, :not_found} ->
        case Ash.create(Thread, %{reply_to: reply_to}, action: :create) do
          {:ok, thread} ->
            case Piano.Codex.start_thread(thread) do
              {:ok, request_id} -> {:ok, %{status: :started, request_id: request_id}}
              {:error, reason} -> {:error, {:codex_start_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:thread_create_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:thread_lookup_failed, reason}}
    end
  end

  defp create_interaction(text, reply_to) do
    Ash.create(Interaction, %{original_message: text, reply_to: reply_to}, action: :create)
  end

  defp find_recent_thread(reply_to) do
    query = Ash.Query.for_read(Thread, :find_recent_for_reply_to, %{reply_to: reply_to})

    case Ash.read(query) do
      {:ok, [thread | _]} -> {:ok, thread}
      {:ok, []} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp start_turn(interaction) do
    case Piano.Codex.start_turn(interaction) do
      {:ok, interaction} -> {:ok, interaction}
      {:error, reason} -> {:error, {:codex_start_failed, reason}}
    end
  end
end
