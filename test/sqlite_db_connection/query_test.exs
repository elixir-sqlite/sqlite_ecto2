defmodule QueryTest do
  # IMPORTANT: This is closely modeled on Postgrex's query_test.exs file.
  # We strive to avoid structural differences between that file and this one.

  use ExUnit.Case, async: true
  import Sqlite.DbConnection.TestHelper
  alias Sqlite.DbConnection.Connection, as: P

  setup do
    opts = [database: ":memory:", backoff_type: :stop]
    {:ok, pid} = P.start_link(opts)
    {:ok, _} = Sqlite.DbConnection.Connection.query(pid, "CREATE TABLE uniques (a int UNIQUE)", [])
    {:ok, [pid: pid]}
  end

  test "iodata", context do
    assert [[123]] = query(["S", ?E, ["LEC"|"T"], " ", '123'], [])
  end

  test "decode basic types", context do
    assert [[nil]] = query("SELECT NULL", [])
    # assert [[true, false]] = query("SELECT true, false", [])
      # ^^ doesn't exist in SQLite
    assert [["e"]] = query("SELECT 'e'", [])
    assert [["ẽ"]] = query("SELECT 'ẽ'", [])
    assert [[42]] = query("SELECT 42", [])
    assert [[42.0]] = query("SELECT cast(42 as float)", [])
    # assert [[:NaN]] = query("SELECT 'NaN'::float", [])
    # assert [[:inf]] = query("SELECT 1/0", [])
    # assert [[:"-inf"]] = query("SELECT -1/0", [])
      # ^^ doesn't exist in SQLite
    assert [["ẽric"]] = query("SELECT 'ẽric'", [])
    assert [[<<1, 2, 3>>]] = query("SELECT cast(x'010203' as blob)", [])
  end

  # Note: Most of the decoding tests don't apply because those types don't exist
  # in SQLite.

  test "encode basic types", context do
    assert [[nil, nil]] = query("SELECT cast($1 as text), cast($2 as int)", [nil, nil])
    assert [[1, 0]] = query("SELECT $1, $2", [true, false])
    assert [["ẽ"]] = query("SELECT cast($1 as char)", ["ẽ"])
    assert [[42]] = query("SELECT cast($1 as int)", [42])
    assert [[42.0, 43.0]] = query("SELECT cast($1 as float), cast($2 as float)", [42, 43.0])
    # assert [[:NaN]] = query("SELECT $1::float", [:NaN])
    # assert [[:inf]] = query("SELECT $1::float", [:inf])
    # assert [[:"-inf"]] = query("SELECT $1::float", [:"-inf"])
      # ^^ doesn't exist in SQLite
    assert [["ẽric"]] = query("SELECT cast($1 as varchar)", ["ẽric"])
    assert [[<<1, 2, 3>>]] = query("SELECT cast($1 as blob)", [<<1, 2, 3>>])
  end

  test "fail on parameter length mismatch", context do
    assert_raise ArgumentError, "parameters must match number of placeholders in query", fn ->
      query("SELECT $1::integer", [1, 2])
    end

    assert_raise ArgumentError, "parameters must match number of placeholders in query", fn ->
      query("SELECT 42", [1])
    end

    assert [[42]] = query("SELECT 42", [])
  end

  test "non data statement", context do
    assert :ok = query("BEGIN", [])
    assert :ok = query("COMMIT", [])
  end

  test "result struct", context do
    assert {:ok, res} = P.query(context[:pid], "SELECT 123 AS a, 456 AS b", [])
    assert %Sqlite.DbConnection.Result{} = res
    assert res.command == :select
    assert res.columns == ["a", "b"]
    assert res.num_rows == 1
  end

  test "query! result struct", context do
    res = Sqlite.DbConnection.Connection.query!(context[:pid], "SELECT 123 AS a, 456 AS b", [])
    assert %Sqlite.DbConnection.Result{} = res
    assert res.command == :select
    assert res.columns == ["a", "b"]
    assert res.num_rows == 1
  end

  # Disabled: I don't know of a way to trigger a runtime error in Sqlite.
  # test "error struct", context do
  #   assert {:error, %Sqlite.DbConnection.Error{}} = P.query(context[:pid], "SELECT 123 + 'a'", [])
  # end

  test "multi row result struct", context do
    assert {:ok, res} = P.query(context[:pid], "VALUES (1, 2), (3, 4)", [])
    assert res.num_rows == 2
    assert res.rows == [[1, 2], [3, 4]]
  end

  test "multi row result struct with decode mapper", context do
    map = &Enum.map(&1, fn x -> x * 2 end)
    assert [[2,4], [6,8]] = query("VALUES (1, 2), (3, 4)", [], decode_mapper: map)
  end

  test "insert", context do
    :ok = query("CREATE TABLE test (id int, text text)", [])
    [] = query("SELECT * FROM test", [])
    :ok = query("INSERT INTO test VALUES ($1, $2)", [42, "fortytwo"], [])
    [[42, "fortytwo"]] = query("SELECT * FROM test", [])
  end

  test "prepare, execute and close", context do
    assert (%Sqlite.DbConnection.Query{} = query) = prepare("42", "SELECT 42")
    assert [[42]] = execute(query, [])
    assert [[42]] = execute(query, [])
    assert :ok = close(query)
    assert [[42]] = query("SELECT 42", [])
  end

  test "prepare, close and execute", context do
    assert (%Sqlite.DbConnection.Query{} = query) = prepare("reuse", "SELECT $1::int")
    assert [[42]] = execute(query, [42])
    assert :ok = close(query)
    assert [[42]] = execute(query, [42])
  end

  test "execute with encode mapper", context do
    assert (%Sqlite.DbConnection.Query{} = query) = prepare("mapper", "SELECT cast($1 as int)")
    assert [[84]] = execute(query, [42], [encode_mapper: fn(n) -> n * 2 end])
    assert :ok = close(query)
    assert [[42]] = query("SELECT 42", [])
  end

  test "closing prepared query that does not exist succeeds", context do
    assert (%Sqlite.DbConnection.Query{} = query) = prepare("42", "SELECT 42")
    assert :ok = close(query)
    assert :ok = close(query)
  end

  test "error codes are translated", context do
    assert %Sqlite.DbConnection.Error{sqlite: %{code: :sqlite_error}} = query("wat", [])
  end

  test "query! raises error on bad query", context do
    assert_raise Sqlite.DbConnection.Error, fn ->
      Sqlite.DbConnection.Connection.query!(context.pid, "wat", [])
    end
  end

  test "connection works after failure in parsing state", context do
    assert %Sqlite.DbConnection.Error{} = query("wat", [])
    assert [[42]] = query("SELECT 42", [])
  end

  test "connection works after failure in executing state", context do
    assert %Sqlite.DbConnection.Error{sqlite: %{code: :constraint}} =
      query("insert into uniques values (1), (1);", [])
    assert [[42]] = query("SELECT 42", [])
  end

  test "connection works after failure during transaction", context do
    assert :ok = query("BEGIN", [])
    assert %Sqlite.DbConnection.Error{sqlite: %{code: :constraint}} =
      query("insert into uniques values (1), (1);", [])
    # assert %Sqlite.DbConnection.Error{postgres: %{code: :in_failed_sql_transaction}} =
    #   query("SELECT 42", [])
    # ^^ Unlike Postgres, SQLite does not fail this second command. Skip that test.
    assert :ok = query("ROLLBACK", [])
    assert [[42]] = query("SELECT 42", [])
  end

  test "connection works on custom transactions", context do
    assert :ok = query("BEGIN", [])
    assert :ok = query("COMMIT", [])
    assert :ok = query("BEGIN", [])
    assert :ok = query("ROLLBACK", [])
    assert [[42]] = query("SELECT 42", [])
  end

  test "connection works after failure in prepare", context do
    assert %Sqlite.DbConnection.Error{} = prepare("bad", "wat")
    assert [[42]] = query("SELECT 42", [])
  end

  test "connection works after failure in execute", context do
    %Sqlite.DbConnection.Query{} = query = prepare("unique", "insert into uniques values (1), (1);")
    assert %Sqlite.DbConnection.Error{sqlite: %{code: :constraint}} =
      execute(query, [])
    assert %Sqlite.DbConnection.Error{sqlite: %{code: :constraint}} =
      execute(query, [])
    assert [[42]] = query("SELECT 42", [])
  end

  test "connection reuses prepared query after query", context do
    %Sqlite.DbConnection.Query{} = query = prepare("", "SELECT 41")
    assert [[42]] = query("SELECT 42", [])
    assert [[41]] = execute(query, [])
  end

  test "connection reuses prepared query after failure in preparing state", context do
    %Sqlite.DbConnection.Query{} = query = prepare("", "SELECT 41")
    assert %Sqlite.DbConnection.Error{} = query("wat", [])
    assert [[41]] = execute(query, [])
  end

  test "connection reuses prepared query after failure in executing state", context do
    %Sqlite.DbConnection.Query{} = query = prepare("", "SELECT 41")
    assert %Sqlite.DbConnection.Error{sqlite: %{code: :constraint}} =
      query("insert into uniques values (1), (1);", [])
    assert [[41]] = execute(query, [])
  end

  # SQLite adapter auto-prepares statements, so --by design-- this won't happen.
  # test "raise when trying to execute unprepared query", context do
  #   assert_raise ArgumentError, ~r/has not been prepared/,
  #     fn -> execute(%Sqlite.DbConnection.Query{name: "hi", statement: "BEGIN"}, []) end
  # end

  test "query struct interpolates to statement" do
    assert "#{%Sqlite.DbConnection.Query{statement: "BEGIN"}}" == "BEGIN"
  end
end
