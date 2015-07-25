if Code.ensure_loaded?(Sqlitex.Server) do
  defmodule Sqlite.Ecto.Connection do
    @moduledoc false

    @behaviour Ecto.Adapters.SQL.Query

    # Connect to a new Sqlite.Server.  Enable and verify the foreign key
    # constraints for the connection.
    def connect(opts) do
      {database, opts} = Keyword.pop(opts, :database)
      case Sqlitex.Server.start_link(database, opts) do
        {:ok, pid} ->
          :ok = Sqlitex.Server.exec(pid, "PRAGMA foreign_keys = ON")
          [[foreign_keys: 1]] = Sqlitex.Server.query(pid, "PRAGMA foreign_keys")
          {:ok, pid}
        error -> error
      end
    end

    def disconnect(pid) do
      Sqlitex.Server.stop(pid)
      :ok
    end

    ## Transaction

    alias Sqlite.Ecto.Transaction

    defdelegate begin_transaction, to: Transaction

    defdelegate rollback, to: Transaction

    defdelegate commit, to: Transaction

    defdelegate savepoint(name), to: Transaction

    defdelegate rollback_to_savepoint(name), to: Transaction

    ## Query

    alias Sqlite.Ecto.Query

    defdelegate query(pid, sql, params, opts), to: Query

    defdelegate all(query), to: Query

    defdelegate update_all(query), to: Query

    defdelegate delete_all(query), to: Query

    defdelegate insert(prefix, table, fields, returning), to: Query

    defdelegate update(prefix, table, fields, filters, returning), to: Query

    defdelegate delete(prefix, table, filters, returning), to: Query

    ## DDL

    alias Sqlite.Ecto.DDL

    defdelegate execute_ddl(ddl), to: DDL
  end
end
