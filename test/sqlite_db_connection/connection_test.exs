defmodule ConnectionTest do
  use ExUnit.Case, async: true
  alias Sqlite.DbConnection.Connection, as: P

  setup do
    opts = [database: ":memory:", backoff_type: :stop]
    {:ok, pid} = P.start_link(opts)
    {:ok, _} = Sqlite.DbConnection.Connection.query(pid, "CREATE TABLE uniques (a int UNIQUE)", [])
    {:ok, [pid: pid]}
  end

  test "prepare", context do
    pid = context[:pid]
    assert {:ok, stmt} = P.prepare(pid, "prepare_test", "SELECT 42", [])
    assert %Sqlite.DbConnection.Query{prepared: sqlitex,
                                      name: "prepare_test",
                                      statement: "SELECT 42"} = stmt
    assert %Sqlitex.Statement{column_names: [:"42"]} = sqlitex
  end

  test "prepare failure case", context do
    pid = context[:pid]
    assert {:error, err} = P.prepare(pid, "prepare_test", "huh", [])
    assert %Sqlite.DbConnection.Error{message: "near \"huh\": syntax error",
                                      sqlite: %{code: :sqlite_error}} = err
  end

  test "prepare!", context do
    pid = context[:pid]
    stmt = P.prepare!(pid, "prepare_test", "SELECT 42", [])
    assert %Sqlite.DbConnection.Query{prepared: sqlitex,
                                      name: "prepare_test",
                                      statement: "SELECT 42"} = stmt
    assert %Sqlitex.Statement{column_names: [:"42"]} = sqlitex
  end

  test "prepare! failure case", context do
    pid = context[:pid]
    assert_raise Sqlite.DbConnection.Error, fn ->
      P.prepare!(pid, "prepare_test", "huh", [])
    end
  end

  test "execute", context do
    pid = context[:pid]
    assert {:ok, result} = P.execute(pid, "prepare_test", "SELECT 42", [])
    IO.puts "execute result = #{inspect result}"
  end
end
