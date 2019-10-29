defmodule Kniffel.Game.Roll do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "roll" do
    field :dices, :map
    belongs_to(:predecessor, Kniffel.Game.Roll)

    timestamps()
  end

  @doc false
  def changeset(roll, attrs) do
    dices =
      attrs["dices"]
      |> Enum.map(fn x ->
        {x, :rand.uniform(6)}
      end)
      |> Map.new()

    attrs =
      attrs
      |> Map.drop(["dices"])
      |> Map.put("dices", dices)

    roll
    |> cast(attrs, [:dices])
    |> put_assoc(:predecessor, attrs["predecessor"])

    # |> unique_constraint("predecessor")
  end
end
