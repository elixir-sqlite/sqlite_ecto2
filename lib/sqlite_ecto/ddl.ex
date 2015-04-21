defmodule Sqlite.Ecto.DDL do
  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference
  import Sqlite.Ecto.Util, only: [quote_id: 1]

  # Return a SQLite query to determine if the given table or index exists in
  # the database.
  def ddl_exists(%Table{name: name}), do: sqlite_master_query(name, "table")
  def ddl_exists(%Index{name: name}), do: sqlite_master_query(name, "index")

  # Create a table.
  def execute_ddl({:create, %Table{name: name}, columns}) do
    "CREATE TABLE #{quote_id(name)} (#{column_definitions(columns)})"
  end

  # Drop a table.
  def execute_ddl({:drop, %Table{name: name}}) do
    "DROP TABLE #{quote_id(name)}"
  end

  # Alter a table.
  def execute_ddl({:alter, %Table{}=table, changes}) do
    # TODO
  end

  # Create an index.
  # NOTE Ignores concurrently and using values.
  def execute_ddl({:create, %Index{}=index}) do
    [name, table] = Enum.map([index.name, index.table], &quote_id/1)
    fields = Enum.map_join(index.columns, ", ", &quote_id/1)
    "#{create_unique_index(index.unique)} #{name} ON #{table} (#{fields})"
  end

  # Drop an index.
  def execute_ddl({:drop, %Index{name: name}}) do
    "DROP INDEX #{quote_id(name)}"
  end

  # XXX Can SQLite alter indices?

  ## Helpers

  # called by ddl_exists/1 above
  defp sqlite_master_query(name, type) do
    "SELECT count(1) FROM sqlite_master WHERE name = '#{name}' AND type = '#{type}'"
  end

  defp column_definitions(cols) do
    Enum.map_join(cols, ", ", &column_definition/1)
  end

  defp column_definition({:add, name, type, opts}) do
    opts = Enum.into(opts, %{})
    quote_id(name) <> column_type(type) <> column_constraints(type, opts)
  end

  # Foreign keys:
  defp column_type(%Reference{table: table, column: col}) do
    " REFERENCES #{quote_id(table)}(#{quote_id(col)})"
  end
  # Simple column types.  Note that we ignore options like :size, :precision,
  # etc. because columns do not have types, and SQLite will not coerce any
  # stored value.  Thus, "strings" are all text and "numerics" have arbitrary
  # precision regardless of the declared column type.
  defp column_type(type) do
    case type do
      :boolean -> " BOOLEAN"
      :datetime -> " DATETIME"
      :integer -> " INTEGER"
      :numeric -> " NUMERIC"
      :serial -> " INTEGER"
      :string -> " TEXT"
    end
  end

  # NOTE SQLite requires autoincrement integers to be primary keys
  # XXX Are there no other constraints we need to handle for serial cols?
  defp column_constraints(:serial, _), do: " PRIMARY KEY AUTOINCREMENT"

  # Return a string of constraints for the column.
  # NOTE The order of these constraints does not matter to SQLite, but
  # rearranging them may cause tests that rely on their order to fail.
  defp column_constraints(_type, opts), do: column_constraints(opts)
  defp column_constraints(opts=%{primary_key: true}) do
    " PRIMARY KEY" <> column_constraints(Map.delete(opts, :primary_key))
  end
  defp column_constraints(opts=%{default: default}) do
    val = case default do
      {:fragment, expr} -> "(#{expr})"
      string when is_binary(string) -> "'#{string}'"
      other -> other
    end
    " DEFAULT #{val}" <> column_constraints(Map.delete(opts, :default))
  end
  defp column_constraints(opts=%{null: false}) do
    " NOT NULL" <> column_constraints(Map.delete(opts, :null))
  end
  defp column_constraints(_), do: ""

  # Returns a create index prefix.
  defp create_unique_index(true), do: "CREATE UNIQUE INDEX"
  defp create_unique_index(false), do: "CREATE INDEX"
end
