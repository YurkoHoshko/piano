defmodule Piano.Telegram.API do
  @moduledoc """
  Wrapper for ExGram API calls, allowing mocking in tests.
  """

  @callback send_message(integer(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  @callback send_chat_action(integer(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  @callback edit_message_text(integer(), integer(), String.t(), keyword()) ::
              {:ok, any()} | {:error, any()}
  @callback answer_callback_query(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  @callback send_document(integer(), any(), keyword()) :: {:ok, any()} | {:error, any()}

  @spec send_message(integer(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def send_message(chat_id, text, opts \\ []) do
    impl().send_message(chat_id, text, opts)
  end

  @spec send_chat_action(integer(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def send_chat_action(chat_id, action, opts \\ []) do
    impl().send_chat_action(chat_id, action, opts)
  end

  @spec edit_message_text(integer(), integer(), String.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def edit_message_text(chat_id, message_id, text, opts \\ []) do
    impl().edit_message_text(chat_id, message_id, text, opts)
  end

  @spec answer_callback_query(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def answer_callback_query(callback_query_id, opts \\ []) do
    impl().answer_callback_query(callback_query_id, opts)
  end

  @spec send_document(integer(), any(), keyword()) :: {:ok, any()} | {:error, any()}
  def send_document(chat_id, document, opts \\ []) do
    impl().send_document(chat_id, document, opts)
  end

  defp impl, do: Application.get_env(:piano, :telegram_api_impl, Piano.Telegram.API.Impl)
end

defmodule Piano.Telegram.API.Impl do
  @moduledoc false
  @behaviour Piano.Telegram.API

  @impl true
  def send_message(chat_id, text, opts) do
    ExGram.send_message(chat_id, text, opts)
  end

  @impl true
  def send_chat_action(chat_id, action, opts) do
    ExGram.send_chat_action(chat_id, action, opts)
  end

  @impl true
  def edit_message_text(chat_id, message_id, text, opts) do
    ExGram.edit_message_text(text, [chat_id: chat_id, message_id: message_id] ++ opts)
  end

  @impl true
  def answer_callback_query(callback_query_id, opts) do
    ExGram.answer_callback_query(callback_query_id, opts)
  end

  @impl true
  def send_document(chat_id, document, opts) do
    ExGram.send_document(chat_id, document, opts)
  end
end
