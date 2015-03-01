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
      "INSERT INTO #{table} DEFAULT VALUES" <> returning(table, returning)
    end
    def insert(table, fields, returning) do
      cols = Enum.join(fields, ",")
      vals = 1..length(fields) |> Enum.map_join(",", &"?#{&1}")
      rets = returning(table, returning)
      "INSERT INTO #{table} (#{cols}) VALUES (#{vals})" <> rets
    end

    def update(table, fields, filters, returning) do
      {vals, count} = Enum.map_reduce(fields, 1, fn (i, acc) ->
        {"#{i} = ?#{acc}", acc + 1}
      end)
      where_clause = where_filter(filters, count)
      rets = returning(table, returning, where_clause)

      "UPDATE #{table} SET " <> Enum.join(vals, ", ") <> where_clause <> rets
      # NOTE:  SQLite does not have a "returning clause" so we have to fake
      # one by appending a "select statement" onto the end of our query (see
      # above).  This works as expected for "insert", but the appended
      # "select" will return the wrong values for "update" if the values in
      # the filters list ("where clause") are also in the fields list.
      #
      # For example, take the code `update("t", [:x, :y], [:x], [:y])`.  This
      # will produce the SQL query:
      # "UPDATE t SET x = ?1, y = ?2 WHERE x = ?3; SELECT y FROM t WHERE x = ?3"
      # This query will update the values in the x column of t that are equal
      # to ?3, but when the select statement gets executed the values of the x
      # column have changed, so the wrong values will be returned.
      #
      # Based on the tests in the Ecto repo, the filters list is typically
      # used to find a particular row id.  Since the row id is unlikely to be
      # updated, the risk of executing this bug should be small.
    end

    def delete(table, filters, returning) do
    end

    ## DDL

    ## Helpers

    @default_where_clause " WHERE _ROWID_ = last_insert_rowid()"
    defp returning(table, returning) do
      returning(table, returning, @default_where_clause)
    end
    defp returning(_table, [], _where), do: ""
    defp returning(table, returning, where) do
      "; SELECT #{Enum.join(returning, ",")} FROM " <> table <> where
    end

    defp where_filter([], _start), do: ""
    defp where_filter(filters, start) do
      filters
      |> Enum.map_reduce(start, fn (i, acc) -> {"#{i} = ?#{acc}", acc + 1} end)
      |> (fn ({filters, _acc}) -> filters end).()
      |> Enum.join(" AND ")
      |> (fn (clause) -> " WHERE " <> clause end).()
    end
  end
end
