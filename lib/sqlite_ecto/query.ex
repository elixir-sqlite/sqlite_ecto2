defmodule Sqlite.Ecto.Query do
  @moduledoc false

  import Sqlite.Ecto.Transaction, only: [with_savepoint: 2]
  import Sqlite.Ecto.Util, only: [assemble: 1, exec: 2, random_id: 0, quote_id: 1]

  # ALTER TABLE queries:
  def query(pid, <<"ALTER TABLE ", _ :: binary>>=sql, params, opts) do
    sql
    |> String.split("; ")
    |> Enum.reduce(:ok, fn
      (_, {:error, _} = error) -> error
      (alter_stmt, _) -> do_query(pid, alter_stmt, params, opts)
    end)
  end
  # all other queries:
  def query(pid, sql, params, opts) do
    params = Enum.map(params, fn
      %Ecto.Query.Tagged{value: value} -> value
      # FIXME handle datetime conversions
      {{yr, mo, da}, {hr, mi, se, _}} -> datetime_to_string(yr, mo, da, hr, mi, se)
      value -> value
    end)

    if has_returning_clause?(sql) do
      returning_query(pid, sql, params, opts)
    else
      do_query(pid, sql, params, opts)
    end
  end

  def all(query) do
    if query.lock do
      raise ArgumentError, "locks are not supported by SQLite"
    end

    sources = create_names(query)

    select = select(query.select, query.distinct, sources)
    from = from(sources)
    join = join(query.joins, sources)
    where = where(query.wheres, sources)
    group_by = group_by(query.group_bys, query.havings, sources)
    order_by = order_by(query.order_bys, sources)
    limit = limit(query.limit, query.offset, sources)

    assemble [select, from, join, where, group_by, order_by, limit]
  end

  def update_all(query, values) do
    if query.joins != [] do
      raise ArgumentError, "JOINS are not supported on UPDATE statements by SQLite"
    end

    sources = create_names(query, :update)
    {table, _name, _model} = elem(sources, 0)

    fields = Enum.map_join(values, ", ", fn {field, expr} ->
      "#{quote_id(field)} = #{expr(expr, sources)}"
    end)
    where = where(query.wheres, sources)
    assemble ["UPDATE", quote_id(table), "SET", fields, where]
  end

  def delete_all(query) do
    if query.joins != [] do
      raise ArgumentError, "JOINS are not supported on DELETE statements by SQLite"
    end

    sources = create_names(query, :delete)
    {table, _name, _model} = elem(sources, 0)
    where = where(query.wheres, sources)
    assemble ["DELETE FROM", quote_id(table), where]
  end

  def insert(table, [], returning) do
    return = returning_clause(table, returning, "INSERT")
    assemble ["INSERT INTO", quote_id(table), "DEFAULT VALUES", return]
  end
  def insert(table, fields, returning) do
    cols = "(" <> Enum.map_join(fields, ",", &quote_id/1) <> ")"
    vals = "(" <> Enum.map_join(1..length(fields), ",", &"?#{&1}") <> ")"
    return = returning_clause(table, returning, "INSERT")
    assemble ["INSERT INTO", quote_id(table), cols, "VALUES", vals, return]
  end

  def update(table, fields, filters, returning) do
    {vals, count} = Enum.map_reduce(fields, 1, fn (i, acc) ->
      {"#{quote_id(i)} = ?#{acc}", acc + 1}
    end)
    vals = Enum.join(vals, ", ")
    where = where_filter(filters, count)
    return = returning_clause(table, returning, "UPDATE")
    assemble ["UPDATE", quote_id(table), "SET", vals, where, return]
  end

  def delete(table, filters, returning) do
    where = where_filter(filters)
    return = returning_clause(table, returning, "DELETE")
    assemble ["DELETE FROM", quote_id(table), where, return]
  end

  ## Returning Clause Helpers

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
            fields = Enum.join(returning, ", ")
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
    fields = Enum.join(returning, ", ")
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
    fields = Enum.map_join(returning, ", ", &"#{ref}.#{&1}")
    sql = """
    CREATE TEMP TRIGGER #{tmp} AFTER #{query} ON main.#{table} BEGIN
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
      rows when is_list(rows) -> query_result(pid, sql, rows)
    end
  end

  defp query_result(pid, <<"INSERT ", _::binary>>, []), do: changes_result(pid)
  defp query_result(pid, <<"UPDATE ", _::binary>>, []), do: changes_result(pid)
  defp query_result(pid, <<"DELETE ", _::binary>>, []), do: changes_result(pid)
  defp query_result(_pid, _sql, rows) do
    rows = Enum.map(rows, fn row ->
      row
      |> Keyword.values
      # FIXME handle datetime conversions
      |> Enum.map(fn {{_, _, _}=date, {hr, mi, se}} -> {date, {hr, mi, se, 0}}
                     other -> other
      end)
      |> List.to_tuple
    end)
    {:ok, %{rows: rows, num_rows: length(rows)}}
  end

  defp changes_result(pid) do
    [["changes()": count]] = Sqlitex.Server.query(pid, "SELECT changes()")
    {:ok, %{rows: nil, num_rows: count}}
  end

  # SQLite does not have a returning clause, but we append a pseudo one so
  # that query() can parse the string later and emulate it with a
  # transaction and trigger.
  # See: returning_query()
  defp returning_clause(_table, [], _cmd), do: []
  defp returning_clause(table, returning, cmd) do
    return = String.strip(@pseudo_returning_statement)
    fields = Enum.map_join([table | returning], ",", &quote_id/1)
    [return, cmd, fields]
  end

  ## Query generation

  binary_ops =
    [==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
     and: "AND", or: "OR",
     ilike: "ILIKE", like: "LIKE"]

  @binary_ops Keyword.keys(binary_ops)

  Enum.map(binary_ops, fn {op, str} ->
    defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
  end)

  defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

  ## Generic Query Helpers

  defp datetime_to_string(yr, mo, da, hr, mi, se) do
    [zero_pad(yr, 4), "-", zero_pad(mo, 2), "-", zero_pad(da, 2), " ", zero_pad(hr, 2), ":", zero_pad(mi, 2), ":", zero_pad(se, 2), ".000000"]
    |> Enum.join
  end

  defp zero_pad(num, len) do
    str = Integer.to_string num
    String.duplicate("0", len - String.length(str)) <> str
  end

  defp create_names(%{sources: sources}, stmt \\ :select) do
    create_names(sources, 0, tuple_size(sources), stmt) |> List.to_tuple()
  end
  defp create_names(sources, pos, limit, stmt) when pos < limit do
    {table, model} = elem(sources, pos)
    if stmt == :select do
      id = String.first(table) <> Integer.to_string(pos)
    else
      id = quote_id(table)
    end
    [{table, id, model} | create_names(sources, pos + 1, limit, stmt)]
  end
  defp create_names(_, pos, pos, _stmt), do: []

  defp select(%Ecto.Query.SelectExpr{fields: fields}, distinct, sources) do
    fields = Enum.map_join(fields, ", ", fn (f) ->
      assemble(expr(f, sources))
    end)
    ["SELECT", distinct(distinct), fields]
  end

  defp distinct(nil), do: []
  defp distinct(%Ecto.Query.QueryExpr{expr: true}), do: "DISTINCT"
  defp distinct(%Ecto.Query.QueryExpr{expr: false}), do: []
  defp distinct(%Ecto.Query.QueryExpr{expr: exprs}) when is_list(exprs) do
    raise ArgumentError, "DISTINCT with multiple columns is not supported by SQLite"
  end

  def from(sources) do
    {table, id, _model} = elem(sources, 0)
    ["FROM", quote_id(table), "AS", id]
  end

  defp expr({:^, [], [_ix]}, _sources) do
    "?"
  end

  defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources) when is_atom(field) do
    {_, name, _} = elem(sources, idx)
    "#{name}.#{quote_id(field)}"
  end

  defp expr({:&, _, [idx]}, sources) do
    {_table, name, model} = elem(sources, idx)
    fields = model.__schema__(:fields)
    Enum.map_join(fields, ", ", &"#{name}.#{quote_id(&1)}")
  end

  defp expr({:in, _, [left, right]}, sources) when is_list(right) do
    args = Enum.map_join(right, ", ", &expr(&1, sources))
    if args == "", do: args = []
    [expr(left, sources), "IN (", args, ")"]
  end

  defp expr({:in, _, [left, {:^, _, [ix, length]}]}, sources) do
    args = Enum.map_join(ix+1..ix+length, ", ", fn (_) -> "?" end)
    if args == "", do: args = []
    [expr(left, sources), "IN (", args, ")"]
  end

  defp expr({:is_nil, _, [arg]}, sources) do
    [expr(arg, sources), "IS", "NULL"]
  end

  defp expr({:not, _, [expr]}, sources) do
    ["NOT (", expr(expr, sources), ")"]
  end

  defp expr({:fragment, _, parts}, sources) do
    Enum.map_join(parts, "", fn
      part when is_binary(part) -> part
      expr -> expr(expr, sources)
    end)
  end

  defp expr({fun, _, args}, sources) when is_atom(fun) and is_list(args) do
    case handle_call(fun, length(args)) do
      {:binary_op, op} ->
        [left, right] = args
        [op_to_binary(left, sources), op, op_to_binary(right, sources)]

      {:fun, fun} ->
        [fun, "(", Enum.map_join(args, ", ", &expr(&1, sources)), ")"]
    end
  end

  defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources) do
    ["CAST (", expr(other, sources), "AS", ecto_to_sqlite_type(type), ")"]
  end

  defp expr(nil, _sources),   do: "NULL"
  defp expr(true, _sources),  do: "TRUE"
  defp expr(false, _sources), do: "FALSE"

  defp expr(literal, _sources) when is_integer(literal) do
    String.Chars.Integer.to_string(literal)
  end

  defp expr(literal, _sources) when is_float(literal) do
    String.Chars.Float.to_string(literal)
  end

  defp expr(literal, _sources) when is_binary(literal) do
    "'#{:binary.replace(literal, "'", "''", [:global])}'"
  end

  defp op_to_binary({op, _, [_, _]} = expr, sources) when op in @binary_ops do
    ["(", expr(expr, sources), ")"]
  end

  defp op_to_binary(expr, sources) do
    expr(expr, sources)
  end

  defp ecto_to_sqlite_type(type) do
    case type do
      {:array, _} -> raise ArgumentError, "Array type is not supported by SQLite"
      :uuid -> "TEXT" # SQLite does not support UUID
      :binary -> "BLOB"
      :float -> "NUMERIC"
      :string -> "TEXT"
      other -> other |> Atom.to_string |> String.upcase
    end
  end

  defp where([], _), do: []
  defp where(query_exprs, sources) do
    exprs = query_exprs
    |> Enum.map(fn %Ecto.Query.QueryExpr{expr: expr} ->
      ["(", expr(expr, sources), ")"]
    end)
    |> Enum.intersperse("AND")
    ["WHERE", exprs]
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
    |> (fn (clause) -> "WHERE " <> clause end).()
  end

  defp order_by(order_bys, sources) do
    exprs = order_bys
    |> Enum.map_join(", ", fn %Ecto.Query.QueryExpr{expr: expr} ->
      Enum.map_join(expr, ", ", &ordering_term(&1, sources))
    end)

    if exprs == "" do
      []
    else
      ["ORDER BY", exprs]
    end
  end

  defp ordering_term({:asc, expr}, sources), do: assemble(expr(expr, sources))
  defp ordering_term({:desc, expr}, sources) do
    assemble(expr(expr, sources)) <> " DESC"
  end

  defp limit(nil, _offset, _sources), do: []
  defp limit(%Ecto.Query.QueryExpr{expr: expr}, offset, sources) do
    ["LIMIT", expr(expr, sources), offset(offset, sources)]
  end

  defp offset(nil, _sources), do: []
  defp offset(%Ecto.Query.QueryExpr{expr: expr}, sources) do
    ["OFFSET", expr(expr, sources)]
  end

  defp group_by(group_bys, havings, sources) do
    exprs = group_bys
    |> Enum.map_join(", ", fn %Ecto.Query.QueryExpr{expr: expr} ->
      Enum.map_join(expr, ", ", &assemble(expr(&1, sources)))
    end)

    if exprs == "" do
      []
    else
      ["GROUP BY", exprs, having(havings, sources)]
    end
  end

  defp having([], _sources), do: []
  defp having(havings, sources) do
    exprs = havings
    |> Enum.map(fn %Ecto.Query.QueryExpr{expr: expr} ->
      ["(", expr(expr, sources), ")"]
    end)
    |> Enum.intersperse("AND")
    ["HAVING", exprs]
  end

  defp join([], _sources), do: []
  defp join(joins, sources) do
    Enum.map(joins, fn
      %Ecto.Query.JoinExpr{on: %Ecto.Query.QueryExpr{expr: expr}, qual: qual, ix: ix} ->
        {table, name, _model} = elem(sources, ix)

        on   = expr(expr, sources)
        qual = join_qual(qual)

        [qual, "JOIN", quote_id(table), "AS", name, "ON", on]
    end)
  end

  defp join_qual(:inner), do: "INNER"
  defp join_qual(:left),  do: "LEFT"
  defp join_qual(:right) do
    raise ArgumentError, "RIGHT OUTER JOIN not supported by SQLite"
  end
  defp join_qual(:full) do
    raise ArgumentError, "FULL OUTER JOIN not supported by SQLite"
  end
end
