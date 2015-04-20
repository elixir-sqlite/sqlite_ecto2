if Code.ensure_loaded?(Sqlitex.Server) do
  defmodule Sqlite.Ecto.Connection do
    @moduledoc false

    @behaviour Ecto.Adapters.SQL.Connection

    def connect(opts) do
      opts
      |> Sqlite.Ecto.get_name
      |> Sqlitex.Server.start_link
      |> configure_foreign_keys
    end

    def disconnect(pid) do
      Sqlitex.Server.stop(pid)
      :ok
    end

    def query(pid, sql, params, opts) do
      params = Enum.map(params, fn
        %Ecto.Query.Tagged{value: value} -> value
        value -> value
      end)

      if has_returning_clause?(sql) do
        returning_query(pid, sql, params, opts)
      else
        do_query(pid, sql, params, opts)
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

    # XXX How do we handle inserting datetime values?
    def insert(table, [], returning) do
      rets = returning_clause(table, returning, "INSERT")
      "INSERT INTO #{quote_id(table)} DEFAULT VALUES" <> rets
    end
    def insert(table, fields, returning) do
      cols = Enum.map_join(fields, ",", &quote_id/1)
      vals = 1..length(fields) |> Enum.map_join(",", &"?#{&1}")
      rets = returning_clause(table, returning, "INSERT")
      "INSERT INTO #{quote_id(table)} (#{cols}) VALUES (#{vals})" <> rets
    end

    def update(table, fields, filters, returning) do
      {vals, count} = Enum.map_reduce(fields, 1, fn (i, acc) ->
        {"#{quote_id(i)} = ?#{acc}", acc + 1}
      end)
      where = where_filter(filters, count)
      rets = returning_clause(table, returning, "UPDATE")
      "UPDATE #{quote_id(table)} SET " <> Enum.join(vals, ", ") <> where <> rets
    end

    def delete(table, filters, returning) do
      where = where_filter(filters)
      return = returning_clause(table, returning, "DELETE")
      "DELETE FROM " <> quote_id(table) <> where <> return
    end

    ## DDL

    alias Ecto.Migration.Table
    alias Ecto.Migration.Index

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

    # Called from connect/1.  If we are given a valid connection, enable and
    # verify foreign key constraints.  Return the result from
    # Sqlitex.Server.start_link/1.
    defp configure_foreign_keys({:ok, pid}) do
      :ok = Sqlitex.Server.exec(pid, "PRAGMA foreign_keys = ON")
      [[foreign_keys: 1]] = Sqlitex.Server.query(pid, "PRAGMA foreign_keys")
      {:ok, pid}
    end
    defp configure_foreign_keys(error_result), do: error_result

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

    alias Ecto.Migration.Reference

    # Foreign keys:
    defp column_type(%Reference{table: table, column: col}) do
      " REFERENCES #{quote_id(table)}(#{quote_id(col)})"
    end
    # Simple column types.  Note that we ignore options like :size,
    # :precision, etc. because columns do not have types, and SQLite will not
    # coerce any stored value.  Thus, "strings" are all text and "numerics"
    # have arbitrary precision regardless of the declared column type.
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

    @pseudo_returning_statement " ;--RETURNING ON "

    # SQLite does not have any sort of "RETURNING" clause upon which Ecto
    # relies.  Therefore, we have made up our own with its own syntax:
    #
    #    ;-- RETURNING ON [INSERT | UPDATE | DELETE] <table>,<col>,<col>,...
    #
    # When the query/4 function is given a query with the above returning
    # clause, (1) it strips it from the end of the query, (2) parses it, and
    # (3) performs the query with the following transaction logic:
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
    defp returning_query(pid, sql, params, opts) do
      {sql, table, returning, query, ref} = parse_returning_clause(sql)

      with_transaction(pid, fn ->
        with_temp_table(pid, returning, fn (tmp_tbl) ->
          err = with_temp_trigger(pid, table, tmp_tbl, returning, query, ref, fn ->
            do_query(pid, sql, params, opts)
          end)

          case err do
            {:error, _} -> err
            _ ->
              fields = Enum.map_join(returning, ", ", &quote_id/1)
              do_query(pid, "SELECT #{fields} FROM #{tmp_tbl}", [], opts)
          end
        end)
      end)
    end

    # Quote the given identifier.
    defp quote_id(id), do: "\"#{id}\""

    # Does this SQL statement have a returning clause in it?
    defp has_returning_clause?(sql) do
      String.contains?(sql, @pseudo_returning_statement)
    end

    # Find our fake returning clause and return the SQL statement without it,
    # table name, and returning fields that we saved from the call to
    # insert(), update(), or delete().
    defp parse_returning_clause(sql) do
      [sql, returning_clause] = String.split(sql, @pseudo_returning_statement)
      {table, cols, query, ref} = parse_return_contents(returning_clause)
      {sql, table, cols, query, ref}
    end

    defp parse_return_contents(<<"INSERT", " ", values::binary>>) do
      [table | cols] = String.split(values, ",")
      {table, cols, "INSERT", "NEW"}
    end
    defp parse_return_contents(<<"UPDATE", " ", values::binary>>) do
      [table | cols] = String.split(values, ",")
      {table, cols, "UPDATE", "NEW"}
    end
    defp parse_return_contents(<<"DELETE", " ", values::binary>>) do
      [table | cols] = String.split(values, ",")
      {table, cols, "DELETE", "OLD"}
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
      fields = Enum.map_join(returning, ", ", &quote_id/1)
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
      fields = Enum.map_join(returning, ", ", &"#{ref}.#{quote_id(&1)}")
      sql = """
      CREATE TEMP TRIGGER #{tmp} AFTER #{query} ON main.#{quote_id(table)} BEGIN
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

    defp do_query(pid, sql, params, opts) do
      opts = Keyword.put(opts, :bind, params)
      case Sqlitex.Server.query(pid, sql, opts) do
        # busy error means another process is writing to the database; try again
        {:error, {:busy, _}} -> do_query(pid, sql, params, opts)
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
    defp returning_clause(_table, [], _cmd), do: ""
    defp returning_clause(table, returning, cmd) do
      @pseudo_returning_statement <> cmd <> " " <> Enum.join([table | returning], ",")
    end

    # Generate a where clause from the given filters.
    defp where_filter(filters), do: where_filter(filters, 1)
    defp where_filter([], _start), do: ""
    defp where_filter(filters, start) do
      filters
      |> Enum.map(&quote_id/1)
      |> Enum.map_reduce(start, fn (i, acc) -> {"#{i} = ?#{acc}", acc + 1} end)
      |> (fn ({filters, _acc}) -> filters end).()
      |> Enum.join(" AND ")
      |> (fn (clause) -> " WHERE " <> clause end).()
    end
  end
end
