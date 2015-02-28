if Code.ensure_loaded?(Sqlitex.Server) do
  defmodule Sqlite.Ecto.Connection do
    @behaviour Ecto.Adapters.SQL.Connection

    def connect(opts) do
      opts |> Sqlite.Ecto.get_name |> Sqlitex.Server.start_link
    end

    def disconnect(pid) do
      Sqlitex.Server.stop(pid)
      :ok
    end

    def query(pid, sql, params, opts) do
      case Sqlitex.query(pid, sql) do
        rows when is_list(rows) -> {:ok, %{rows: rows, num_rows: length(rows)}}
        {:error, _} = err -> err
      end
    end

    ## Transaction

    def begin_transaction, do: "BEGIN"

    def rollback, do: "ROLLBACK"

    def commit, do: "COMMIT"

    def savepoint(name), do: "SAVEPOINT " <> name

    def rollback_to_savepoint(name), do: "ROLLBACK TO " <> name

    ## Query

    def all(query) do
    end

    def update_all(query, values) do
    end

    def delete_all(query) do
    end

    def insert(table, fields, returning) do
    end

    def update(table, fields, filters, returning) do
    end

    def delete(table, filters, returning) do
    end

    ## DDL
  end
end
