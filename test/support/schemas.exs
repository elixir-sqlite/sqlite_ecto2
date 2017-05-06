defmodule Sqlite.Ecto2.Test.MiscTypes do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "misc_types" do
    field :name, :string
    field :start_time, :time
    field :cost, :decimal
  end

  def changeset(schema, params) do
    cast(schema, params, ~w(name start_time cost))
  end
end
