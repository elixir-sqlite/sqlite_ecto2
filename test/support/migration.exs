defmodule Sqlite.Ecto2.Test.Migration do
  use Ecto.Migration

  def change do
    create table(:misc_types) do
      add :name, :text
      add :start_time, :time
      add :cost, :decimal
    end
  end
end
