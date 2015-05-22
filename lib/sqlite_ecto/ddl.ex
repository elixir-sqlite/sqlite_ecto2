defmodule Sqlite.Ecto.DDL do
  @moduledoc false

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference
  import Sqlite.Ecto.Util, only: [assemble: 1, quote_id: 1]

  # Return a SQLite query to determine if the given table or index exists in
  # the database.
  def ddl_exists(%Table{name: name}), do: sqlite_master_query(name, "table")
  def ddl_exists(%Index{name: name}), do: sqlite_master_query(name, "index")

  # Create a table.
  def execute_ddl({:create, %Table{name: name}, columns}) do
    assemble ["CREATE TABLE", quote_id(name), column_definitions(columns)]
  end

  # Drop a table.
  def execute_ddl({:drop, %Table{name: name}}) do
    assemble ["DROP TABLE", quote_id(name)]
  end

  # Alter a table.
  def execute_ddl({:alter, %Table{name: name}, changes}) do
    Enum.map_join(changes, "; ", fn (change) ->
      assemble ["ALTER TABLE", quote_id(name), alter_table_suffix(change)]
    end)
  end

  # Create an index.
  # NOTE Ignores concurrently and using values.
  def execute_ddl({:create, %Index{}=index}) do
    [name, table] = Enum.map([index.name, index.table], &quote_id/1)
    fields = "(" <> Enum.map_join(index.columns, ", ", &quote_id/1) <> ")"
    assemble [create_unique_index(index.unique), name, "ON", table, fields]
  end

  # Drop an index.
  def execute_ddl({:drop, %Index{name: name}}) do
    assemble ["DROP INDEX", quote_id(name)]
  end

  # XXX Can SQLite alter indices?

  ## Helpers

  # called by ddl_exists/1 above
  defp sqlite_master_query(name, type) do
    "SELECT count(1) FROM sqlite_master WHERE name = '#{name}' AND type = '#{type}'"
  end

  defp column_definitions(cols) do
    "(" <> Enum.map_join(cols, ", ", &column_definition/1) <> ")"
  end

  defp column_definition({_action, name, type, opts}) do
    opts = Enum.into(opts, %{})
    assemble [quote_id(name), column_type(type), column_constraints(type, opts)]
  end

  # Foreign keys:
  defp column_type(%Reference{table: table, column: col}) do
    "REFERENCES #{quote_id(table)}(#{quote_id(col)})"
  end
  # Simple column types.  Note that we ignore options like :size, :precision,
  # etc. because columns do not have types, and SQLite will not coerce any
  # stored value.  Thus, "strings" are all text and "numerics" have arbitrary
  # precision regardless of the declared column type.
  # FIXME A bug in Sqlitex prevents captitalized "DATETIME" from being parsed
  # correctly.  When that bug is fixed, remove this line.
  defp column_type(:datetime), do: "datetime"
  defp column_type(:serial), do: "INTEGER"
  defp column_type(:string), do: "TEXT"
  defp column_type(type), do: type |> Atom.to_string |> String.upcase

  # NOTE SQLite requires autoincrement integers to be primary keys
  # XXX Are there no other constraints we need to handle for serial cols?
  defp column_constraints(:serial, _), do: "PRIMARY KEY AUTOINCREMENT"

  # Return a string of constraints for the column.
  # NOTE The order of these constraints does not matter to SQLite, but
  # rearranging them may cause tests that rely on their order to fail.
  defp column_constraints(_type, opts), do: column_constraints(opts)
  defp column_constraints(opts=%{primary_key: true}) do
    other_constraints = opts |> Map.delete(:primary_key) |> column_constraints
    ["PRIMARY KEY" | other_constraints]
  end
  defp column_constraints(opts=%{default: default}) do
    val = case default do
      {:fragment, expr} -> "(#{expr})"
      string when is_binary(string) -> "'#{string}'"
      other -> other
    end
    other_constraints = opts |> Map.delete(:default) |> column_constraints
    ["DEFAULT", val, other_constraints]
  end
  defp column_constraints(opts=%{null: false}) do
    other_constraints = opts |> Map.delete(:null) |> column_constraints
    ["NOT NULL", other_constraints]
  end
  defp column_constraints(_), do: []

  # Returns a create index prefix.
  defp create_unique_index(true), do: "CREATE UNIQUE INDEX"
  defp create_unique_index(false), do: "CREATE INDEX"

  defp alter_table_suffix(change={:add, _column, _type, _opts}) do
    ["ADD COLUMN", column_definition(change)]
  end
  defp alter_table_suffix({:modify, _column, _type, _opts}) do
    raise ArgumentError, "ALTER COLUMN not supported by SQLite"
  end
  defp alter_table_suffix({:remove, _column}) do
    raise ArgumentError, "DROP COLUMN not supported by SQLite"
  end
end
