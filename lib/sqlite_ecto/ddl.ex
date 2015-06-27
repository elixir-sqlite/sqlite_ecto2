defmodule Sqlite.Ecto.DDL do
  @moduledoc false

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference
  import Sqlite.Ecto.Util, only: [assemble: 1, map_intersperse: 3, quote_id: 1]

  # Return a SQLite query to determine if the given table or index exists in
  # the database.
  def ddl_exists(%Table{name: name}), do: sqlite_master_query(name, "table")
  def ddl_exists(%Index{name: name}), do: sqlite_master_query(name, "index")

  # Create a table.
  def execute_ddl({:create, %Table{name: name, options: options}, columns}) do
    assemble ["CREATE TABLE", quote_id(name), column_definitions(columns), options]
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
    create_index = create_unique_index(index.unique)
    [name, table] = Enum.map([index.name, index.table], &quote_id/1)
    fields = map_intersperse(index.columns, ",", &quote_id/1)
    assemble [create_index, name, "ON", table, "(", fields, ")"]
  end

  # Drop an index.
  def execute_ddl({:drop, %Index{name: name}}) do
    assemble ["DROP INDEX", quote_id(name)]
  end

  # Default:
  def execute_ddl(default) when is_binary(default), do: default

  ## Helpers

  # called by ddl_exists/1 above
  defp sqlite_master_query(name, type) do
    "SELECT count(1) FROM sqlite_master WHERE name = '#{name}' AND type = '#{type}'"
  end

  defp column_definitions(cols) do
    ["(", map_intersperse(cols, ",", &column_definition/1), ")"]
  end

  defp column_definition({_action, name, type, opts}) do
    opts = Enum.into(opts, %{})
    [quote_id(name), column_type(type, opts), column_constraints(type, opts)]
  end

  # Foreign keys:
  defp column_type(%Reference{table: table, column: col}, _opts) do
    "REFERENCES #{quote_id(table)}(#{quote_id(col)})"
  end
  # Decimals are the only type for which we care about the options:
  defp column_type(:decimal, opts=%{precision: precision}) do
    scale = Dict.get(opts, :scale, 0)
    "DECIMAL(#{precision},#{scale})"
  end
  # Simple column types.  Note that we ignore options like :size, :precision,
  # etc. because columns do not have types, and SQLite will not coerce any
  # stored value.  Thus, "strings" are all text and "numerics" have arbitrary
  # precision regardless of the declared column type.  Decimals above are the
  # only exception.
  defp column_type(:serial, _opts), do: "INTEGER"
  defp column_type(:string, _opts), do: "TEXT"
  defp column_type(:map, _opts), do: "TEXT"
  defp column_type({:array, _}, _opts), do: raise(ArgumentError, "Array type is not supported by SQLite")
  defp column_type(type, _opts), do: type |> Atom.to_string |> String.upcase

  # NOTE SQLite requires autoincrement integers to be primary keys
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
      true -> 1
      false -> 0
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

  # If we are adding a DATETIME column with the NOT NULL constraint, SQLite
  # will force us to give it a DEFAULT value.  The only default value
  # that makes sense is CURRENT_TIMESTAMP, but when adding a column to a
  # table, defaults must be constant values.
  #
  # Therefore the best option is just to remove the NOT NULL constraint when
  # we add new datetime columns.
  defp alter_table_suffix({:add, column, :datetime, opts}) do
    opts = opts |> Enum.into(%{}) |> Dict.delete(:null)
    change = {:add, column, :datetime, opts}
    ["ADD COLUMN", column_definition(change)]
  end

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
