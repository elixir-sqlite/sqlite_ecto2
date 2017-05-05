defmodule ConnectionTest do
  use ExUnit.Case, async: true

  alias Sqlite.DbConnection.Query

  setup do
    opts = [database: ":memory:", backoff_type: :stop]
    {:ok, pid} = DBConnection.start_link(Sqlite.DbConnection.Protocol, opts)

    query = %Query{name: "", statement: "CREATE TABLE uniques (a int UNIQUE)"}
    {:ok, _, _} = DBConnection.prepare_execute(pid, query, [])

    {:ok, [pid: pid]}
  end

  test "prepare failure case", context do
    pid = context[:pid]
    query = %Query{name: "test", statement: "huh"}
    assert {:error, err} = DBConnection.prepare(pid, query)
    assert %Sqlite.DbConnection.Error{message: "near \"huh\": syntax error",
                                      sqlite: %{code: :sqlite_error}} = err
  end
end
