defmodule Piano.Tools.SurfaceToolResource do
  @moduledoc """
  Ash resource wrapper for Surface messaging tools via MCP.

  Allows the AI agent to send messages to surfaces (Telegram, etc.)
  for notifications, background task results, and user communication.
  """

  use Ash.Resource, domain: Piano.Domain

  alias Piano.Surface.Router

  actions do
    action :send_message, :map do
      description """
      Send a message to a surface (e.g., Telegram chat).
      Use this to notify users about background task completion or send results.
      The message can be plain text or markdown.
      """

      argument :surface_id, :string do
        allow_nil? false

        description """
        Surface identifier in format 'type:id' (e.g., 'telegram:123456', 'mock:test-123').
        For Telegram, use the chat_id. For mock surfaces, use the mock agent ID.
        """
      end

      argument :message, :string do
        allow_nil? false
        description "The message to send. Supports markdown formatting for Telegram."
      end

      run fn input, _ctx ->
        surface_id = input.arguments.surface_id
        message = input.arguments.message

        case resolve_and_send(surface_id, message) do
          {:ok, result} ->
            {:ok,
             %{
               success: true,
               surface_id: surface_id,
               message_preview: String.slice(message, 0, 100),
               result: inspect(result)
             }}

          {:error, reason} ->
            {:error, "Failed to send message: #{inspect(reason)}"}
        end
      end
    end

    action :send_to_chat, :map do
      description """
      Send a message directly to a Telegram chat by chat_id.
      Shorthand for send_message with telegram: prefix.
      """

      argument :chat_id, :integer do
        allow_nil? false
        description "Telegram chat ID (positive for DMs, negative for groups)"
      end

      argument :message, :string do
        allow_nil? false
        description "The message to send. Supports markdown formatting."
      end

      run fn input, _ctx ->
        chat_id = input.arguments.chat_id
        message = input.arguments.message

        surface_id = "telegram:#{chat_id}:0"

        case resolve_and_send(surface_id, message) do
          {:ok, result} ->
            {:ok,
             %{
               success: true,
               chat_id: chat_id,
               message_preview: String.slice(message, 0, 100),
               result: inspect(result)
             }}

          {:error, reason} ->
            {:error, "Failed to send message: #{inspect(reason)}"}
        end
      end
    end
  end

  defp resolve_and_send(surface_id, message) do
    case Router.parse(surface_id) do
      {:ok, surface} when is_struct(surface) ->
        Piano.Surface.send_message(surface, message)

      {:ok, :liveview_not_implemented} ->
        {:error, :liveview_not_implemented}

      :error ->
        {:error, :invalid_surface_id}
    end
  end
end
