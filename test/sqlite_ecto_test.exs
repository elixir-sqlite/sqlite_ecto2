defmodule Sqlite.Ecto.Test do
  use ExUnit.Case, async: true

  alias Sqlite.Ecto, as: SQL

  test "storage up (twice)" do
    tmp = [database: "/tmp/test1.db"]
    assert SQL.storage_up(tmp) == :ok
    assert SQL.storage_up(tmp) == {:error, :already_up}
    File.rm(tmp[:database])
  end

  test "storage down (twice)" do
    tmp = [database: "/tmp/test2.db"]
    assert SQL.storage_up(tmp) == :ok
    assert SQL.storage_down(tmp) == :ok
    assert not File.exists?(tmp[:database])
    assert SQL.storage_down(tmp) == {:error, :already_down}
  end
end
