defmodule Kniffel.User do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Kniffel.{
    Repo,
    User
  }

  require Logger

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user" do
    field :name, :string
    many_to_many :games, Kniffel.User, join_through: "game_players", on_replace: :delete
    has_many(:scores, Kniffel.Game.Score)

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> cast_assoc(:games, attrs["games"] || user.games)
    |> cast_assoc(:scores, attrs["scores"] || user.scores)
  end

  # -----------------------------------------------------------------
  # -- User
  # -----------------------------------------------------------------

  def get_users() do
    User
    |> Repo.all()
  end

  def get_user(id) do
    User
    |> Repo.get(id)
  end

  def create_user(user_params) do
    %User{}
    |> Repo.preload([:games, :scores])
    |> User.changeset(user_params)
    |> Repo.insert()
  end

  def update_user(user, user_params) do
    user
    |> Repo.preload([:games, :scores])
    |> User.changeset(user_params)
    |> Repo.update()
  end

  def delete_user(user) do
    Repo.delete(user)
  end

  def change_user(user \\ %User{}, attrs \\ %{}) do
    user
    |> Repo.preload([:games, :scores])
    |> User.changeset(attrs)
  end
end
