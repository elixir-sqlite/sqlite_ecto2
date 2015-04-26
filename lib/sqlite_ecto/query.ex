defmodule Sqlite.Ecto.Query do
  import Sqlite.Ecto.Transaction, only: [with_savepoint: 2]
  import Sqlite.Ecto.Util, only: [exec: 2, random_id: 0, quote_id: 1]

  def query(pid, sql=<<"ALTER TABLE ", _::binary>>, _params, _opts) do
    alter_table_query(pid, sql)
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

  ## Helpers

  # for algorithm see: http://www.sqlite.org/lang_altertable.html
  defp alter_table_query(pid, alter) do
    {name, fields} = parse_alter_table_query(alter)
    with_foreign_keys_disabled(pid, fn ->
      with_savepoint(pid, fn ->
        :ok = modify_table(pid, name, fields)
        [] = Sqlitex.Server.query(pid, "PRAGMA foreign_key_check")
      end)
    end)
    {:ok, %{num_rows: 0, rows: []}}
  end

  defp parse_alter_table_query(sql) do
    name = parse_alter_table_name(sql)
    {name, parse_alter_table_fields(name, sql)}
  end

  defp parse_alter_table_name("ALTER TABLE " <> rest) do
    rest |> String.split("\"") |> Enum.at(1)
  end

  defp parse_alter_table_fields(name, sql) do
    sql
    |> String.split("; ")
    |> Enum.map(fn alter ->
      length = name |> quote_id |> bit_size
      <<"ALTER TABLE ", _name::size(length), " ", suffix::binary>> = alter
      to_field(suffix)
    end)
  end

  defp to_field(<<"ADD COLUMN ", _::binary>> = stmt), do: {:add, stmt}
  defp to_field("ALTER COLUMN " <> field), do: {:modify, field}
  defp to_field("DROP COLUMN " <> col_name), do: {:remove, col_name}

  defp with_foreign_keys_disabled(pid, func) do
    :ok = exec(pid, "PRAGMA foreign_keys = OFF")
    func.()
    :ok = exec(pid, "PRAGMA foreign_keys = ON")
  end

  defp modify_table(pid, name, changes) do
    # save indices associated with the table
    query = "SELECT sql FROM sqlite_master WHERE tbl_name = '#{name}' AND type = 'index'"
    create_indices = Sqlitex.Server.query(pid, query) |> Enum.map(fn row -> row[:sql] end)

    # split the fields for the original table columns
    length = name |> quote_id |> bit_size
    <<"CREATE TABLE ", _name::size(length), " (", fields::binary>> = table_schema(pid, name)
    fields = fields |> String.rstrip(?)) |> String.split(", ")

    # go through each of the fields applying drops and modifications
    {column_names, fields} = fields
    |> Enum.reduce({[], []}, fn (col, {names, fields}) ->
      col_name = col |> String.split("\"") |> Enum.at(1) |> quote_id
      case find_matching_change(col_name, changes) do
        {:modify, new_field} ->
          {[col_name | names], [new_field | fields]}
        {:remove, _} ->
          {names, fields}
        _ ->
          {[col_name | names], [col | fields]}
      end
    end)
    |> (fn ({names, fields}) -> {Enum.reverse(names), Enum.reverse(fields)} end).()

    # reconstruct the table schema with new fields and create a new table
    new_tbl = "tbl_" <> random_id
    create_tbl = "CREATE TABLE #{new_tbl} (#{Enum.join(fields, ", ")})"
    :ok = exec(pid, create_tbl)

    # INSERT INTO new SELECT ... FROM name;
    name = quote_id(name)
    move_tbl = "INSERT INTO #{new_tbl} SELECT #{Enum.join(column_names, ",")} FROM #{name}"
    :ok = exec(pid, move_tbl)

    # DROP TABLE name;
    :ok = exec(pid, "DROP TABLE #{name}")

    # ALTER TABLE new RENAME TO name;
    :ok = exec(pid, "ALTER TABLE #{new_tbl} RENAME TO #{name}")

    # add new columns
    for {:add, col} <- changes do
      :ok = exec(pid, "ALTER TABLE #{name} #{col}")
    end

    # restore saved indices
    Enum.each(create_indices, fn sql -> :ok = exec(pid, sql) end)

    :ok
  end

  defp find_matching_change(name, changes) do
    idx = Enum.find_index(changes, fn ({_action, stmt}) ->
      String.starts_with?(stmt, name)
    end)

    if idx do
      Enum.at(changes, idx)
    else
      nil
    end
  end

  # find the schema for the table given by 'name'
  defp table_schema(pid, name) do
    query = "SELECT sql FROM sqlite_master WHERE name = '#{name}' AND type = 'table'"
    [sql] = Sqlitex.Server.query(pid, query)
    sql[:sql]
  end

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
  #   SAVEPOINT sp_<random>;
  #   CREATE TEMP TABLE temp.t_<random> (<returning>);
  #   CREATE TEMP TRIGGER tr_<random> AFTER UPDATE ON main.<table> BEGIN
  #       INSERT INTO t_<random> SELECT NEW.<returning>;
  #   END;
  #   UPDATE ...;
  #   DROP TRIGGER tr_<random>;
  #   SELECT <returning> FROM temp.t_<random>;
  #   DROP TABLE temp.t_<random>;
  #   RELEASE sp_<random>;
  #
  # which is implemented by the following code:
  defp returning_query(pid, sql, params, opts) do
    {sql, table, returning, query, ref} = parse_returning_clause(sql)

    with_savepoint(pid, fn ->
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

  # Create a temp table to save the values we will write with our trigger
  # (below), call func.(), and drop the table afterwards.  Returns the
  # result of func.().
  defp with_temp_table(pid, returning, func) do
    tmp = "t_" <> random_id
    fields = Enum.map_join(returning, ", ", &quote_id/1)
    results = case exec(pid, "CREATE TEMP TABLE #{tmp} (#{fields})") do
      {:error, _} = err -> err
      _ -> func.(tmp)
    end
    exec(pid, "DROP TABLE IF EXISTS #{tmp}")
    results
  end

  # Create a trigger to capture the changes from our query, call func.(),
  # and drop the trigger when done.  Returns the result of func.().
  defp with_temp_trigger(pid, table, tmp_tbl, returning, query, ref, func) do
    tmp = "tr_" <> random_id
    fields = Enum.map_join(returning, ", ", &"#{ref}.#{quote_id(&1)}")
    sql = """
    CREATE TEMP TRIGGER #{tmp} AFTER #{query} ON main.#{quote_id(table)} BEGIN
        INSERT INTO #{tmp_tbl} SELECT #{fields};
    END;
    """
    results = case exec(pid, sql) do
      {:error, _} = err -> err
      _ -> func.()
    end
    exec(pid, "DROP TRIGGER IF EXISTS #{tmp}")
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
