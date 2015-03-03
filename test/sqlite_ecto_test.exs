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
    assert query == ~s{INSERT INTO model (x,y) VALUES (?1,?2) RETURNING model|id}

    query = SQL.insert("model", [], [:id])
    assert query == ~s{INSERT INTO model DEFAULT VALUES RETURNING model|id}

    query = SQL.insert("model", [], [])
    assert query == ~s{INSERT INTO model DEFAULT VALUES}
  end

  test "update" do
    query = SQL.update("model", [:x, :y], [:id], [:x, :z])
    assert query == ~s{UPDATE model SET x = ?1, y = ?2 WHERE id = ?3 RETURNING model|x,z}

    query = SQL.update("model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE model SET x = ?1, y = ?2 WHERE id = ?3}
  end

  test "query" do
    {:ok, sql} = SQL.connect(database: ":memory:")
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "CREATE TABLE model (id, x, y, z)")

    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "INSERT INTO model VALUES (1, 2, 3, 4)")
    query = ~s{UPDATE model SET x = ?1, y = ?2 WHERE id = ?3 RETURNING model|x,z}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:foo, :bar, 1])
    assert row == [x: "foo", z: 4]

    query = ~s{INSERT INTO model VALUES (?1, ?2, ?3, ?4) RETURNING model|id}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:a, :b, :c, :d])
    assert row == [id: "a"]

    query = ~s{DELETE FROM model WHERE id = ?1 RETURNING model|id,x,y,z}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [1])
    assert row == [id: 1, x: "foo", y: "bar", z: 4]

    SQL.disconnect(sql)
  end
end
