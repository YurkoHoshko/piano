defmodule Piano.Surface.Resolver do
  @moduledoc """
  Resolves surfaces and users from incoming interactions.

  When an interaction arrives:
  1. Parse the reply_to to identify surface type and provider ID
  2. Find or create the surface
  3. Find or create the user (if user info provided)
  4. Link user to surface
  5. Find or create thread for the surface
  6. Create interaction for the thread
  """

  alias Piano.Surface.Router
  require Ash.Query

  @doc """
  Resolve surface, user, and thread from an incoming interaction request.

  ## Options
  - `:user_info` - Map with :display_name, :username, :metadata for user creation
  - `:thread_id` - Existing thread ID to use instead of finding/creating

  Returns `{:ok, %{surface: surface, user: user, thread: thread}}` or `{:error, reason}`
  """
  @spec resolve(String.t(), keyword()) ::
          {:ok, %{surface: struct(), user: struct() | nil, thread: struct()}}
          | {:error, term()}
  def resolve(reply_to, opts \\ []) do
    user_info = Keyword.get(opts, :user_info, %{})
    thread_id = Keyword.get(opts, :thread_id)

    with {:ok, {app, identifier, single_user?}} <- parse_reply_to(reply_to),
         {:ok, surface} <- find_or_create_surface(app, identifier, single_user?),
         {:ok, user} <- find_or_create_user(user_info, surface),
         {:ok, _link} <- link_user_to_surface(user, surface),
         {:ok, thread} <- find_or_create_thread(surface, reply_to, thread_id) do
      {:ok, %{surface: surface, user: user, thread: thread}}
    end
  end

  @doc """
  Just resolve the surface without user or thread operations.
  """
  @spec resolve_surface(String.t()) :: {:ok, struct()} | {:error, term()}
  def resolve_surface(reply_to) do
    with {:ok, {app, identifier, single_user?}} <- parse_reply_to(reply_to) do
      find_or_create_surface(app, identifier, single_user?)
    end
  end

  defp parse_reply_to(reply_to) do
    app = Router.app_type(reply_to)
    identifier = Router.base_identifier(reply_to)
    single_user? = Router.single_user?(reply_to)

    if app == :unknown or is_nil(identifier) do
      {:error, :unknown_surface_type}
    else
      {:ok, {app, identifier, single_user?}}
    end
  end

  defp find_or_create_surface(app, identifier, single_user?) do
    Piano.Core.Surface
    |> Ash.Changeset.for_create(:find_or_create, %{
      app: app,
      identifier: to_string(identifier),
      single_user?: single_user?
    })
    |> Ash.create()
  end

  defp find_or_create_user(user_info, surface) when map_size(user_info) == 0 do
    if surface.single_user? do
      Piano.Core.User
      |> Ash.Changeset.for_create(:create, %{
        display_name: "Anonymous",
        metadata: %{surface_id: surface.id}
      })
      |> Ash.create()
    else
      {:ok, nil}
    end
  end

  defp find_or_create_user(user_info, _surface) do
    username = user_info[:username] || user_info["username"]

    if username do
      case Piano.Core.User
           |> Ash.Query.for_read(:by_username, %{username: username})
           |> Ash.read_one() do
        {:ok, nil} -> create_user(user_info)
        {:ok, user} -> {:ok, user}
        error -> error
      end
    else
      create_user(user_info)
    end
  end

  defp create_user(user_info) do
    Piano.Core.User
    |> Ash.Changeset.for_create(:create, %{
      display_name: user_info[:display_name] || user_info["display_name"],
      username: user_info[:username] || user_info["username"],
      metadata: user_info[:metadata] || user_info["metadata"] || %{}
    })
    |> Ash.create()
  end

  defp link_user_to_surface(nil, _surface), do: {:ok, nil}

  defp link_user_to_surface(user, surface) do
    Piano.Core.UserSurface
    |> Ash.Changeset.for_create(:link, %{
      user_id: user.id,
      surface_id: surface.id
    })
    |> Ash.create()
  end

  defp find_or_create_thread(surface, reply_to, nil) do
    case Piano.Core.Thread
         |> Ash.Query.filter(surface_id == ^surface.id)
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read_one() do
      {:ok, nil} -> create_thread(surface, reply_to)
      {:ok, thread} -> {:ok, thread}
      error -> error
    end
  end

  defp find_or_create_thread(_surface, _reply_to, thread_id) do
    Ash.get(Piano.Core.Thread, thread_id)
  end

  defp create_thread(surface, reply_to) do
    Piano.Core.Thread
    |> Ash.Changeset.for_create(:create, %{
      surface_id: surface.id,
      reply_to: reply_to
    })
    |> Ash.create()
  end
end
