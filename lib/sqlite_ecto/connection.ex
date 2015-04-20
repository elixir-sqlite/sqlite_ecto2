if Code.ensure_loaded?(Sqlitex.Server) do
  defmodule Sqlite.Ecto.Connection do
    @moduledoc false

    @behaviour Ecto.Adapters.SQL.Connection

    # Connect to a new Sqlite.Server.  Enable and verify the foreign key
    # constraints for the connection.
    def connect(opts) do
      conn = opts |> Sqlite.Ecto.get_name |> Sqlitex.Server.start_link
      if :ok == elem(conn, 0) do
        pid = elem(conn, 1)
        :ok = Sqlitex.Server.exec(pid, "PRAGMA foreign_keys = ON")
        [[foreign_keys: 1]] = Sqlitex.Server.query(pid, "PRAGMA foreign_keys")
      end
      conn
    end

    def disconnect(pid) do
      Sqlitex.Server.stop(pid)
      :ok
    end

    ## Transaction

    def begin_transaction, do: "BEGIN"

    def rollback, do: "ROLLBACK"

    def commit, do: "COMMIT"

    def savepoint(name), do: "SAVEPOINT " <> name

    def rollback_to_savepoint(name), do: "ROLLBACK TO " <> name

    ## Query

    alias Sqlite.Ecto.Query

    def query(pid, sql, params, opts) do
      Query.query(pid, sql, params, opts)
    end

    def all(query) do
      Query.all(query)
    end

    def update_all(query, values) do
      Query.update_all(query, values)
    end

    def delete_all(query) do
      Query.delete_all(query)
    end

    def insert(table, fields, returning) do
      Query.insert(table, fields, returning)
    end

    def update(table, fields, filters, returning) do
      Query.update(table, fields, filters, returning)
    end

    def delete(table, filters, returning) do
      Query.delete(table, filters, returning)
    end

    ## DDL

    alias Sqlite.Ecto.DDL

    def ddl_exists(ddl) do
      DDL.ddl_exists(ddl)
    end

    def execute_ddl(ddl) do
      DDL.execute_ddl(ddl)
    end
  end
end
