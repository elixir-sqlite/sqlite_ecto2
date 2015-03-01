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

    def query(pid, sql, params \\ []) do
      case Sqlitex.query(pid, sql, params) do
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

    def insert(table, [], returning) do
      "INSERT INTO #{table} DEFAULT VALUES#{returning(table, returning)}"
    end
    def insert(table, fields, returning) do
      cols = Enum.join(fields, ",")
      vals = 1..length(fields) |> Enum.map_join(",", &"?#{&1}")
      rets = returning(table, returning)
      "INSERT INTO #{table} (#{cols}) VALUES (#{vals})#{rets}"
    end

    def update(table, fields, filters, returning) do
    end

    def delete(table, filters, returning) do
    end

    ## DDL

    ## Helpers

    defp returning(_table, []), do: ""
    defp returning(table, returning) do
      rets = Enum.join(returning, ",")
      "; SELECT #{rets} FROM #{table} WHERE _ROWID_ = last_insert_rowid()"
    end
  end
end
