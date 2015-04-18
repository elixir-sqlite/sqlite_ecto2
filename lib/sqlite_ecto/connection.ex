if Code.ensure_loaded?(Sqlitex.Server) do
  defmodule Sqlite.Ecto.Connection do
    @moduledoc false

    @behaviour Ecto.Adapters.SQL.Connection

    def connect(opts) do
      opts |> Sqlite.Ecto.get_name |> Sqlitex.Server.start_link
    end

    def disconnect(pid) do
      Sqlitex.Server.stop(pid)
      :ok
    end

    def query(pid, sql, params \\ []) do
      params = Enum.map(params, fn
        %Ecto.Query.Tagged{value: value} -> value
        value -> value
      end)

      if has_returning_clause?(sql) do
        returning_query(pid, sql, params)
      else
        do_query(pid, sql, params)
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
      rets = returning_clause(table, returning)
      "INSERT INTO #{table} DEFAULT VALUES" <> rets
    end
    def insert(table, fields, returning) do
      cols = Enum.join(fields, ",")
      vals = 1..length(fields) |> Enum.map_join(",", &"?#{&1}")
      rets = returning_clause(table, returning)
      "INSERT INTO #{table} (#{cols}) VALUES (#{vals})" <> rets
    end

    def update(table, fields, filters, returning) do
      {vals, count} = Enum.map_reduce(fields, 1, fn (i, acc) ->
        {"#{i} = ?#{acc}", acc + 1}
      end)
      where = where_filter(filters, count)
      rets = returning_clause(table, returning)
      "UPDATE #{table} SET " <> Enum.join(vals, ", ") <> where <> rets
    end

    def delete(table, filters, returning) do
      where = where_filter(filters)
      return = returning_clause(table, returning)
      "DELETE FROM " <> table <> where <> return
    end

    ## DDL

    ## Helpers

    @pseudo_returning_statement " ;--RETURNING "

    # SQLite does not have any sort of "RETURNING" clause... so we have to
    # fake one with the following transaction:
    #
    #   BEGIN TRANSACTION;
    #   CREATE TEMP TABLE temp.t_<random> (<returning>);
    #   CREATE TEMP TRIGGER tr_<random> AFTER UPDATE ON main.<table> BEGIN
    #       INSERT INTO t_<random> SELECT NEW.<returning>;
    #   END;
    #   UPDATE ...;
    #   DROP TRIGGER tr_<random>;
    #   SELECT <returning> FROM temp.t_<random>;
    #   DROP TABLE temp.t_<random>;
    #   END TRANSACTION;
    #
    # which is implemented by the following code:
    defp returning_query(pid, sql, params) do
      {sql, table, returning} = parse_returning_clause(sql)
      {query, ref} = parse_query_type(sql)

      with_transaction(pid, fn ->
        with_temp_table(pid, returning, fn (tmp_tbl) ->
          err = with_temp_trigger(pid, table, tmp_tbl, returning, query, ref, fn ->
            do_query(pid, sql, params)
          end)

          case err do
            {:error, _} -> err
            _ ->
              do_query(pid, "SELECT #{Enum.join(returning, ", ")} FROM #{tmp_tbl}")
          end
        end)
      end)
    end

    # Does this SQL statement have a returning clause in it?
    defp has_returning_clause?(sql) do
      String.contains?(sql, @pseudo_returning_statement)
    end

    # Find our fake returning clause and return the SQL statement without it,
    # table name, and returning fields that we saved from the call to
    # insert(), update(), or delete().
    defp parse_returning_clause(sql) do
      [sql, returning_clause] = String.split(sql, @pseudo_returning_statement)
      returning_clause
      |> String.split(",")
      |> (fn [table | rest] -> {sql, table, rest} end).()
    end

    # Determine whether our trigger should be concerned with the OLD or NEW
    # values that our query will affect in the table.
    defp parse_query_type(sql) do
      case sql do
        << "INSERT", _ :: binary >> -> {"INSERT", "NEW"}
        << "UPDATE", _ :: binary >> -> {"UPDATE", "NEW"}
        << "DELETE", _ :: binary >> -> {"DELETE", "OLD"}
      end
    end

    # Initiate a transaction.  If we are already within a transaction, then do
    # nothing.  If any error occurs when we call the func parameter, rollback
    # our changes.  Returns the result of the call to func.
    defp with_transaction(pid, func) do
      should_commit? = (do_exec(pid, "BEGIN TRANSACTION") == :ok)
      result = safe_call(pid, func, should_commit?)
      error? = (is_tuple(result) and :erlang.element(1, result) == :error)

      cond do
        error? -> do_exec(pid, "ROLLBACK")
        should_commit? -> do_exec(pid, "END TRANSACTION")
      end
      result
    end

    # Call func.() and return the result.  If any exceptions are encountered,
    # safely rollback the transaction.
    defp safe_call(pid, func, should_rollback?) do
      try do
        func.()
      rescue
        e in RuntimeError ->
          if should_rollback?, do: do_exec(pid, "ROLLBACK")
          raise e
      end
    end

    # Create a temp table to save the values we will write with our trigger
    # (below), call func.(), and drop the table afterwards.  Returns the
    # result of func.().
    defp with_temp_table(pid, returning, func) do
      tmp = "t_" <> (:random.uniform |> Float.to_string |> String.slice(2..10))
      fields = Enum.join(returning, ", ")
      results = case do_exec(pid, "CREATE TEMP TABLE #{tmp} (#{fields})") do
        {:error, _} = err -> err
        _ -> func.(tmp)
      end
      do_exec(pid, "DROP TABLE IF EXISTS #{tmp}")
      results
    end

    # Create a trigger to capture the changes from our query, call func.(),
    # and drop the trigger when done.  Returns the result of func.().
    defp with_temp_trigger(pid, table, tmp_tbl, returning, query, ref, func) do
      tmp = "tr_" <> (:random.uniform |> Float.to_string |> String.slice(2..10))
      fields = Enum.map_join(returning, ", ", &"#{ref}.#{&1}")
      sql = """
      CREATE TEMP TRIGGER #{tmp} AFTER #{query} ON main.#{table} BEGIN
          INSERT INTO #{tmp_tbl} SELECT #{fields};
      END;
      """
      results = case do_exec(pid, sql) do
        {:error, _} = err -> err
        _ -> func.()
      end
      do_exec(pid, "DROP TRIGGER IF EXISTS #{tmp}")
      results
    end

    defp do_query(pid, sql, params \\ []) do
      case Sqlitex.Server.query(pid, sql, bind: params) do
        # busy error means another process is writing to the database; try again
        {:error, {:busy, _}} -> do_query(pid, sql, params)
        {:error, _} = error -> error
        rows when is_list(rows) ->
          {:ok, %{rows: rows, num_rows: length(rows)}}
      end
    end

    defp do_exec(pid, sql) do
      case Sqlitex.Server.exec(pid, sql) do
        # busy error means another process is writing to the database; try again
        {:error, {:busy, _}} -> do_exec(pid, sql)
        {:error, _} = error -> error
        :ok -> :ok
      end
    end

    # SQLite does not have a returning clause, but we append a pseudo one so
    # that query() can parse the string later and emulate it with a
    # transaction and trigger.
    # See: returning_query()
    defp returning_clause(_table, []), do: ""
    defp returning_clause(table, returning) do
      @pseudo_returning_statement <> Enum.join([table | returning], ",")
    end

    # Generate a where clause from the given filters.
    defp where_filter(filters), do: where_filter(filters, 1)
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
