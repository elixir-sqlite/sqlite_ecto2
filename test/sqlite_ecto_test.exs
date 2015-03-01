defmodule Sqlite.Ecto.Test do
  use ExUnit.Case, async: true

  alias Sqlite.Ecto.Connection, as: SQL

  test "storage up (twice)" do
    tmp = [database: "/tmp/test1.db"]
    assert Sqlite.Ecto.storage_up(tmp) == :ok
    assert Sqlite.Ecto.storage_up(tmp) == {:error, :already_up}
    File.rm(tmp[:database])
  end

  test "storage down (twice)" do
    tmp = [database: "/tmp/test2.db"]
    assert Sqlite.Ecto.storage_up(tmp) == :ok
    assert Sqlite.Ecto.storage_down(tmp) == :ok
    assert not File.exists?(tmp[:database])
    assert Sqlite.Ecto.storage_down(tmp) == {:error, :already_down}
  end

  test "insert" do
    query = SQL.insert("model", [:x, :y], [:id])
    assert query == ~s{INSERT INTO model (x,y) VALUES (?1,?2); SELECT id FROM model WHERE _ROWID_ = last_insert_rowid()}

    query = SQL.insert("model", [], [:id])
    assert query == ~s{INSERT INTO model DEFAULT VALUES; SELECT id FROM model WHERE _ROWID_ = last_insert_rowid()}

    query = SQL.insert("model", [], [])
    assert query == ~s{INSERT INTO model DEFAULT VALUES}
  end
end
