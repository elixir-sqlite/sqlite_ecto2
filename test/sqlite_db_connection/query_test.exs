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
end
