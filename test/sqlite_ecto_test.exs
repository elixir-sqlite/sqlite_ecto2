defmodule Sqlite.Ecto.Test do
  use ExUnit.Case, async: true

  alias Sqlite.Ecto.Connection, as: SQL
  alias Ecto.Migration.Table

  setup do
    {:ok, sql} = SQL.connect(database: ":memory:")
    #on_exit fn -> SQL.disconnect(sql) end
    {:ok, sql: sql}
  end

  test "storage up (twice)" do
    tmp = [database: tempfilename]
    assert Sqlite.Ecto.storage_up(tmp) == :ok
    assert Sqlite.Ecto.storage_up(tmp) == {:error, :already_up}
    File.rm(tmp[:database])
  end

  test "storage down (twice)" do
    tmp = [database: tempfilename]
    assert Sqlite.Ecto.storage_up(tmp) == :ok
    assert Sqlite.Ecto.storage_down(tmp) == :ok
    assert not File.exists?(tmp[:database])
    assert Sqlite.Ecto.storage_down(tmp) == {:error, :already_down}
  end

  test "insert" do
    query = SQL.insert("model", [:x, :y], [:id])
    assert query == ~s{INSERT INTO model (x,y) VALUES (?1,?2) ;--RETURNING ON INSERT model,id}

    query = SQL.insert("model", [], [:id])
    assert query == ~s{INSERT INTO model DEFAULT VALUES ;--RETURNING ON INSERT model,id}

    query = SQL.insert("model", [], [])
    assert query == ~s{INSERT INTO model DEFAULT VALUES}
  end

  test "update" do
    query = SQL.update("model", [:x, :y], [:id], [:x, :z])
    assert query == ~s{UPDATE model SET x = ?1, y = ?2 WHERE id = ?3 ;--RETURNING ON UPDATE model,x,z}

    query = SQL.update("model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE model SET x = ?1, y = ?2 WHERE id = ?3}
  end

  test "delete" do
    query = SQL.delete("model", [:x, :y], [:z])
    assert query == ~s{DELETE FROM model WHERE x = ?1 AND y = ?2 ;--RETURNING ON DELETE model,z}

    query = SQL.delete("model", [:x, :y], [])
    assert query == ~s{DELETE FROM model WHERE x = ?1 AND y = ?2}
  end

  test "query", context do
    #sql = context[:sql]
    {:ok, sql} = SQL.connect(database: ":memory:")
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "CREATE TABLE model (id, x, y, z)", [], [])

    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "INSERT INTO model VALUES (1, 2, 3, 4)", [], [])
    query = ~s{UPDATE model SET x = ?1, y = ?2 WHERE id = ?3 ;--RETURNING ON UPDATE model,x,z}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:foo, :bar, 1], [])
    assert row == [x: "foo", z: 4]

    query = ~s{INSERT INTO model VALUES (?1, ?2, ?3, ?4) ;--RETURNING ON INSERT model,id}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:a, :b, :c, :d], [])
    assert row == [id: "a"]

    query = ~s{DELETE FROM model WHERE id = ?1 ;--RETURNING ON DELETE model,id,x,y,z}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [1], [])
    assert row == [id: 1, x: "foo", y: "bar", z: 4]
    SQL.disconnect(sql)
  end

  test "table exists", context do
    #sql = context[:sql]
    {:ok, sql} = SQL.connect(database: ":memory:")
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "CREATE TABLE model (id, x, y, z)", [], [])
    query = SQL.ddl_exists(%Table{name: "model"})
    assert query == "SELECT count(1) FROM sqlite_master WHERE name = 'model' AND type = 'table'"
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [], [])
    assert row == ["count(1)": 1]
    query = SQL.ddl_exists(%Table{name: "not_model"})
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [], [])
    assert row == ["count(1)": 0]
    SQL.disconnect(sql)
  end

  ## Helpers

  # return a unique temporary filename
  defp tempfilename do
    :erlang.now |> :random.seed
    1..10
    |> Enum.map(fn(_) -> :random.uniform(10) - 1 end)
    |> Enum.join
    |> (fn(name) -> "/tmp/test_" <> name <> ".db" end).()
  end
end
