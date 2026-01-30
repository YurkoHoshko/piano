defmodule Piano.Telegram.Prompt do
  @moduledoc """
  Build the user prompt text for Telegram messages.

  In groups, we include basic attribution (who asked) and explicitly note that
  the chat has multiple users, while still using a shared thread per chat.
  """

  @spec build(map(), String.t(), keyword()) :: String.t()
  def build(msg, text, opts \\ []) when is_map(msg) and is_binary(text) and is_list(opts) do
    chat_type = dig(msg, [:chat, :type])
    participants = Keyword.get(opts, :participants)

    if chat_type in ["group", "supergroup"] do
      title = dig(msg, [:chat, :title])

      user_id = dig(msg, [:from, :id])
      username = dig(msg, [:from, :username])
      first_name = dig(msg, [:from, :first_name])
      last_name = dig(msg, [:from, :last_name])

      display =
        cond do
          is_binary(username) and username != "" -> "@#{username}"
          is_binary(first_name) and is_binary(last_name) -> String.trim("#{first_name} #{last_name}")
          is_binary(first_name) and first_name != "" -> first_name
          true -> "unknown"
        end

      header =
        [
          "This is a group chat with multiple users.",
          if(is_binary(title) and title != "", do: "Chat: #{title}", else: nil),
          if(is_integer(participants), do: "Participants: #{participants}", else: nil),
          if(is_integer(user_id), do: "From: #{display} (telegram_user_id=#{user_id})", else: "From: #{display}"),
          "",
          "Message:"
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      header <> "\n" <> text
    else
      text
    end
  end

  defp dig(data, []), do: data
  defp dig(nil, _keys), do: nil

  defp dig(data, [key | rest]) when is_map(data) and is_atom(key) do
    value = Map.get(data, key) || Map.get(data, Atom.to_string(key))
    dig(value, rest)
  end

  defp dig(_data, [_key | _rest]), do: nil
end
