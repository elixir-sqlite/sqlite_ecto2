defmodule QueryTest do
  # IMPORTANT: This is closely modeled on Postgrex's query_test.exs file.
  # We strive to avoid structural differences between that file and this one.

  use ExUnit.Case, async: true
  import Sqlite.DbConnection.TestHelper
  alias Sqlite.DbConnection.Connection, as: P

  setup do
    opts = [ database: ":memory:", backoff_type: :stop ]
    {:ok, pid} = P.start_link(opts)
    {:ok, [pid: pid]}
  end

  test "iodata", context do
    assert [[123]] = query(["S", ?E, ["LEC"|"T"], " ", '123'], [])
  end
end
