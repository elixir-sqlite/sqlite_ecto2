defmodule Sqlite.Ecto.Query do
  @moduledoc false

  import Sqlite.Ecto.Transaction, only: [with_savepoint: 2]
  import Sqlite.Ecto.Util

  alias Sqlite.Ecto.Result

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
      %Ecto.Query.Tagged{type: :binary, value: value} when is_binary(value) -> {:blob, value}
      %Ecto.Query.Tagged{value: value} -> value
      %{__struct__: _} = value -> value
      %{} = value -> json_library.encode! value
      value -> value
    end)

    if has_returning_clause?(sql) do
      returning_query(pid, sql, params, opts)
    else
      do_query(pid, sql, params, opts)
    end
  end

  ## Query

  alias Ecto.Query
  alias Ecto.Query.SelectExpr
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr

  def all(%Ecto.Query{lock: lock}) when lock != nil do
    raise ArgumentError, "locks are not supported by SQLite"
  end
  def all(query) do
    sources = create_names(query, :select)

    select = select(query.select, query.distinct, sources)
    from = from(sources)
    join = join(query, sources)
    where = where(query, sources)
    group_by = group_by(query.group_bys, query.havings, sources)
    order_by = order_by(query.order_bys, sources)
    limit = limit(query.limit, query.offset, sources)

    assemble [select, from, join, where, group_by, order_by, limit]
  end

  def update_all(%Ecto.Query{joins: [_ | _]}) do
    raise ArgumentError, "JOINS are not supported on UPDATE statements by SQLite"
  end
  def update_all(query) do
    sources = create_names(query, :update)
    {table, _name, _model} = elem(sources, 0)

    fields = update_fields(query, sources)
    {join, wheres} = update_join(query, sources)
    where = where(%{query | wheres: wheres ++ query.wheres}, sources)

    assemble(["UPDATE #{table} SET", fields, join, where])
  end

  def delete_all(%Ecto.Query{joins: [_ | _]}) do
    raise ArgumentError, "JOINS are not supported on DELETE statements by SQLite"
  end
  def delete_all(query) do
    sources = create_names(query, :delete)
    {table, _name, _model} = elem(sources, 0)

    join  = using(query, sources)
    where = delete_all_where(query.joins, query, sources)

    assemble(["DELETE FROM #{table}", join, where])
  end

  def insert(prefix, table, [], returning) do
    return = returning_clause(prefix, table, returning, "INSERT")
    assemble ["INSERT INTO", quote_id({prefix, table}), "DEFAULT VALUES", return]
  end
  def insert(prefix, table, fields, returning) do
    cols = map_intersperse(fields, ",", &quote_id/1)
    vals = map_intersperse(1..length(fields), ",", &"?#{&1}")
    return = returning_clause(prefix, table, returning, "INSERT")
    assemble ["INSERT INTO", quote_id({prefix, table}), "(", cols, ")", "VALUES (", vals, ")", return]
  end

  def update(prefix, table, fields, filters, returning) do
    {vals, count} = Enum.map_reduce(fields, 1, fn (i, acc) ->
      {"#{quote_id(i)} = ?#{acc}", acc + 1}
    end)
    vals = Enum.intersperse(vals, ",")
    where = where_filter(filters, count)
    return = returning_clause(prefix, table, returning, "UPDATE")
    assemble ["UPDATE", quote_id({prefix, table}), "SET", vals, where, return]
  end

  def delete(prefix, table, filters, returning) do
    where = where_filter(filters)
    return = returning_clause(prefix, table, returning, "DELETE")
    assemble ["DELETE FROM", quote_id({prefix, table}), where, return]
  end

  ## Returning Clause Helpers

  @pseudo_returning_statement " ;--RETURNING ON "

  # SQLite does not have any sort of "RETURNING" clause upon which Ecto
  # relies.  Therefore, we have made up our own with its own syntax:
  #
  #    ;--RETURNING ON [INSERT | UPDATE | DELETE] <table>,<col>,<col>,...
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

  # From our returning clause, return the table, columns, command, and whether
  # we are interested in the "NEW" or "OLD" values of the modified rows.
  defp parse_return_contents(<<"INSERT ", values::binary>>) do
    [table | cols] = String.split(values, ",")
    {table, cols, "INSERT", "NEW"}
  end
  defp parse_return_contents(<<"UPDATE ", values::binary>>) do
    [table | cols] = String.split(values, ",")
    {table, cols, "UPDATE", "NEW"}
  end
  defp parse_return_contents(<<"DELETE ", values::binary>>) do
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

  # Execute a query with (possibly) binded parameters and handle busy signals
  # from the database.
  defp do_query(pid, sql, params, opts) do
    opts = opts
           |> Keyword.put(:decode, :manual)
           |> Keyword.put(:into, :raw_list)
           |> Keyword.put(:types, true)
           |> Keyword.put(:bind, params)
    case Sqlitex.Server.query(pid, sql, opts) do
      # busy error means another process is writing to the database; try again
      {:error, {:busy, _}} -> do_query(pid, sql, params, opts)
      {:error, msg} -> {:error, Sqlite.Ecto.Error.exception(msg)}
      {:ok, rows, columns, types} when is_list(rows)
        -> query_result(pid, sql, rows, columns, types, opts)
    end
  end

  # If this is an INSERT, UPDATE, or DELETE, then return the number of changed
  # rows.  Otherwise (e.g. for SELECT) return the queried column values.
  defp query_result(pid, <<"INSERT ", _::binary>>, [], _columns, _types, _opts), do: changes_result(pid)
  defp query_result(pid, <<"UPDATE ", _::binary>>, [], _columns, _types, _opts), do: changes_result(pid)
  defp query_result(pid, <<"DELETE ", _::binary>>, [], _columns, _types, _opts), do: changes_result(pid)
  defp query_result(_pid, _sql, rows, columns, types, opts) do
    {:ok, decode(rows, columns, types, Keyword.fetch(opts, :decode))}
  end

  defp decode(rows, columns, column_types, {:ok, :manual}) do
    %Result{rows: rows,
            columns: columns,
            column_types: column_types,
            num_rows: length(rows),
            decoder: :deferred}
  end
  defp decode(rows, columns, column_types, _) do # not specified or :auto
    decode(rows, columns, column_types, {:ok, :manual})
    |> Result.decode
  end

  defp changes_result(pid) do
    {:ok, [["changes()": count]]} = Sqlitex.Server.query(pid, "SELECT changes()")
    {:ok, %Result{rows: nil, num_rows: count}}
  end

  # SQLite does not have a returning clause, but we append a pseudo one so
  # that query() can parse the string later and emulate it with a
  # transaction and trigger.
  # See: returning_query()
  defp returning_clause(_prefix, _table, [], _cmd), do: []
  defp returning_clause(prefix, table, returning, cmd) do
    return = String.strip(@pseudo_returning_statement)
    fields = Enum.map_join([{prefix, table} | returning], ",", &quote_id/1)
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

  defp select(%SelectExpr{fields: fields}, distinct, sources) do
    fields = Enum.map_join(fields, ", ", fn (f) ->
      assemble(expr(f, sources, "query"))
    end)
    ["SELECT", distinct(distinct), fields]
  end

  defp distinct(nil), do: []
  defp distinct(%QueryExpr{expr: true}), do: "DISTINCT"
  defp distinct(%QueryExpr{expr: false}), do: []
  defp distinct(%QueryExpr{expr: exprs}) when is_list(exprs) do
    raise ArgumentError, "DISTINCT with multiple columns is not supported by SQLite"
  end

  defp from(sources) do
    {table, name, _model} = elem(sources, 0)
    "FROM #{table} AS #{name}"
  end

  defp using(%Query{joins: []}, _sources), do: []
  defp using(%Query{joins: joins} = query, sources) do
    Enum.map_join(joins, " ", fn
      %JoinExpr{qual: :inner, on: %QueryExpr{expr: expr}, ix: ix} ->
        {table, name, _model} = elem(sources, ix)
        where = expr(expr, sources, query)
        "USING #{table} AS #{name} WHERE " <> where
      %JoinExpr{qual: qual} ->
          error!(query, "PostgreSQL supports only inner joins on delete_all, got: `#{qual}`")
    end)
  end

  defp update_fields(%Query{updates: updates} = query, sources) do
    for(%{expr: expr} <- updates,
        {op, kw} <- expr,
        {key, value} <- kw,
        do: update_op(op, key, value, sources, query)) |> Enum.join(", ")
  end

  defp update_op(:set, key, value, sources, query) do
    quote_name(key) <> " = " <> expr(value, sources, query)
  end

  defp update_op(:inc, key, value, sources, query) do
    quoted = quote_name(key)
    quoted <> " = " <> quoted <> " + " <> expr(value, sources, query)
  end

  defp update_op(command, _key, _value, _sources, query) do
    error!(query, "Unknown update operation #{inspect command} for SQLite")
  end

  defp update_join(%Query{joins: []}, _sources), do: {[], []}
  defp update_join(%Query{joins: joins} = query, sources) do
    froms =
      "FROM " <> Enum.map_join(joins, ", ", fn
        %JoinExpr{qual: :inner, ix: ix, source: source} ->
          {join, name, _model} = elem(sources, ix)
          join = join || "(" <> expr(source, sources, query) <> ")"
          join <> " AS " <> name
        %JoinExpr{qual: qual} ->
          error!(query, "SQLite supports only inner joins on update_all, got: `#{qual}`")
      end)

    wheres =
      for %JoinExpr{on: %QueryExpr{expr: value} = expr} <- joins,
          value != true,
          do: expr

    {froms, wheres}
  end

  defp join(%Query{joins: []}, _sources), do: []
  defp join(%Query{joins: joins} = query, sources) do
    Enum.map_join(joins, " ", fn
      %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source} ->
        {join, name, _model} = elem(sources, ix)
        qual = join_qual(qual)
        join = join || "(" <> expr(source, sources, query) <> ")"
        "#{qual} JOIN " <> join <> " AS " <> name <> " ON " <> expr(expr, sources, query)
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

  defp delete_all_where([], query, sources), do: where(query, sources)
  defp delete_all_where(_joins, %Query{wheres: wheres} = query, sources) do
    boolean("AND", wheres, sources, query)
  end

  defp where(%Query{wheres: wheres} = query, sources) do
    boolean("WHERE", wheres, sources, query)
  end

  defp having([], _sources), do: []
  defp having(havings, sources) do
    exprs = map_intersperse havings, "AND", fn %QueryExpr{expr: expr} ->
      ["(", expr(expr, sources, "query"), ")"]
    end
    ["HAVING" | exprs]
  end

  defp group_by(group_bys, havings, sources) do
    Enum.map_join(group_bys, ", ", fn %QueryExpr{expr: expr} ->
      Enum.map_join(expr, ", ", &assemble(expr(&1, sources, "query")))
    end)
    |> group_by_clause(havings, sources)
  end

  defp group_by_clause("", _, _), do: []
  defp group_by_clause(exprs, havings, sources) do
    ["GROUP BY", exprs, having(havings, sources)]
  end

  defp order_by(order_bys, sources) do
    Enum.map_join(order_bys, ", ", fn %QueryExpr{expr: expr} ->
      Enum.map_join(expr, ", ", &ordering_term(&1, sources))
    end)
    |> order_by_clause
  end

  defp order_by_clause(""), do: []
  defp order_by_clause(exprs), do: ["ORDER BY", exprs]

  defp ordering_term({:asc, expr}, sources), do: assemble(expr(expr, sources, "query"))
  defp ordering_term({:desc, expr}, sources) do
    assemble(expr(expr, sources, "query")) <> " DESC"
  end

  ## Generic Query Helpers

  defp select(%SelectExpr{fields: fields}, distinct, sources) do
    fields = Enum.map_join(fields, ", ", fn (f) ->
      assemble(expr(f, sources, "query"))
    end)
    ["SELECT", distinct(distinct), fields]
  end

  defp limit(nil, _offset, _sources), do: []
  defp limit(%QueryExpr{expr: expr}, offset, sources) do
    ["LIMIT", expr(expr, sources, "query"), offset(offset, sources)]
  end

  defp offset(nil, _sources), do: []
  defp offset(%QueryExpr{expr: expr}, sources) do
    ["OFFSET", expr(expr, sources, "query")]
  end

  defp boolean(_name, [], _sources, _query), do: []
  defp boolean(name, query_exprs, sources, query) do
    name <> " " <>
      Enum.map_join(query_exprs, " AND ", fn
        %QueryExpr{expr: expr} ->
          "(" <> expr(expr, sources, query) <> ")"
      end)
  end

  defp expr({:^, [], [_ix]}, _sources, _query) do
    "?"
  end

  defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query) when is_atom(field) do
    {_, name, _} = elem(sources, idx)
    "#{name}.#{quote_id(field)}"
  end

  defp expr({:&, _, [idx]}, sources, _query) do
    {table, name, model} = elem(sources, idx)
    unless model do
      raise ArgumentError, "SQLite requires a model when using selector #{inspect name} but " <>
                           "only the table #{inspect table} was given. Please specify a model " <>
                           "or specify exactly which fields from #{inspect name} you desire"
    end
    map_intersperse(model.__schema__(:fields), ",", &"#{name}.#{quote_id(&1)}")
  end

  defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
    args = Enum.map_join right, ",", &expr(&1, sources, query)
    expr(left, sources, query) <> " IN (" <> args <> ")"
  end

  defp expr({:in, _, [left, {:^, _, [ix, length]}]}, sources, query) do
    args = Enum.map_join ix+1..ix+length, ",", &"$#{&1}"
    expr(left, sources, query) <> " IN (" <> args <> ")"
  end

  defp expr({:in, _, [left, right]}, sources, query) do
    expr(left, sources, query) <> " IN (" <> expr(right, sources, query) <> ")"
  end

  defp expr({:is_nil, _, [arg]}, sources, query) do
    "#{expr(arg, sources, query)} IS NULL"
  end

  defp expr({:not, _, [expr]}, sources, query) do
    "NOT (" <> expr(expr, sources, query) <> ")"
  end

  defp expr({:fragment, _, [kw]}, _sources, _query) when is_list(kw) or tuple_size(kw) == 3 do
    raise ArgumentError, "SQLite adapter does not support keyword or interpolated fragments"
  end

  defp expr({:fragment, _, parts}, sources, query) do
    Enum.map_join(parts, "", fn
      {:raw, part}  -> part
      {:expr, expr} -> expr(expr, sources, query)
    end)
  end

  # start of SQLite function to display date
  # NOTE the open parenthesis must be closed
  @date_format "strftime('%Y-%m-%d'"

  defp expr({:date_add, _, [date, count, interval]}, sources, query) do
    "CAST (#{@date_format},#{expr(date, sources, query)},#{interval(count, interval, sources)}) AS TEXT_DATE)"
  end

  # start of SQLite function to display datetime
  # NOTE the open parenthesis must be closed
  @datetime_format "strftime('%Y-%m-%d %H:%M:%f000'"

  defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
    "CAST (#{@datetime_format},#{expr(datetime, sources, query)},#{interval(count, interval, sources)}) AS TEXT_DATETIME)"
  end

  defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
    {modifier, args} =
      case args do
       [rest, :distinct] -> {"DISTINCT ", [rest]}
       _ -> {"", args}
     end

    case handle_call(fun, length(args)) do
      {:binary_op, op} ->
        [left, right] = args
        op_to_binary(left, sources, query) <>
        " #{op} "
        <> op_to_binary(right, sources, query)

      {:fun, fun} ->
        "#{fun}(" <> modifier <> Enum.map_join(args, ", ", &expr(&1, sources, query)) <> ")"
    end
  end

  defp expr(%Decimal{} = decimal, _sources, _query) do
    Decimal.to_string(decimal, :normal)
  end

  defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query) when is_binary(binary) do
    "X'#{Base.encode16(binary, case: :upper)}'"
  end

  defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) when type in [:id, :integer, :float] do
    expr(other, sources, query)
  end

  defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
    "CAST (#{expr(other, sources, query)} AS #{ecto_to_sqlite_type(type)})"
  end

  defp expr(nil, _sources, _query),   do: "NULL"
  defp expr(true, _sources, _query),  do: "1"
  defp expr(false, _sources, _query), do: "0"

  defp expr(literal, _sources, _query) when is_integer(literal) do
    String.Chars.Integer.to_string(literal)
  end

  defp expr(literal, _sources, _query) when is_float(literal) do
    String.Chars.Float.to_string(literal)
  end

  defp expr(literal, _sources, _query) when is_binary(literal) do
    "'#{:binary.replace(literal, "'", "''", [:global])}'"
  end

  defp interval(_, "microsecond", _sources) do
    raise ArgumentError, "SQLite does not support microsecond precision in datetime intervals"
  end

  defp interval(count, "millisecond", sources) do
    "(#{expr(count, sources, nil)} / 1000.0) || ' seconds'"
  end

  defp interval(count, "week", sources) do
    "(#{expr(count, sources, nil)} * 7) || ' days'"
  end

  defp interval(count, interval, sources) do
    "#{expr(count, sources, nil)} || ' #{interval}'"
  end

  defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
    "(" <> expr(expr, sources, query) <> ")"
  end

  defp op_to_binary(expr, sources, query) do
    expr(expr, sources, query)
  end

  defp ecto_to_sqlite_type(type) do
    case type do
      {:array, _} -> raise ArgumentError, "Array type is not supported by SQLite"
      :id -> "INTEGER"
      :binary_id -> "TEXT"
      :uuid -> "TEXT" # SQLite does not support UUID
      :binary -> "BLOB"
      :float -> "NUMERIC"
      :string -> "TEXT"
      :date -> "TEXT_DATE"          # HACK see: cast_any_datetimes/1
      :datetime -> "TEXT_DATETIME"  # HACK see: cast_any_datetimes/1
      :map -> "TEXT"
      other -> other |> Atom.to_string |> String.upcase
    end
  end

  # Generate a where clause from the given filters.
  defp where_filter(filters), do: where_filter(filters, 1)
  defp where_filter([], _start), do: []
  defp where_filter(filters, start) do
    {filters, _} = Enum.map_reduce filters, start, fn (filter, count) ->
      {"#{quote_id(filter)} = ?#{count}", count + 1}
    end
    ["WHERE" | Enum.intersperse(filters, "AND")]
  end

  defp create_names(%{prefix: prefix, sources: sources}, stmt) do
    create_names(prefix, sources, 0, tuple_size(sources), stmt) |> List.to_tuple()
  end

  defp create_names(prefix, sources, pos, limit, stmt) when pos < limit do
    current =
      case elem(sources, pos) do
        {table, model} ->
          {quote_table(prefix, table), table_identifier(stmt, table, pos), model}
        {:fragment, _, _} ->
          {nil, "f" <> Integer.to_string(pos), nil}
      end
    [current|create_names(prefix, sources, pos + 1, limit, stmt)]
  end

  defp create_names(_prefix, _sources, pos, pos, _stmt) do
    []
  end

  defp table_identifier(:select, table, pos) do
    String.first(table) <> Integer.to_string(pos)
  end
  defp table_identifier(_stmt, table, _pos), do: quote_id(table)

  defp fragment_identifier(pos), do: "f" <> Integer.to_string(pos)

  ## Helpers

  defp quote_name(name)
  defp quote_name(name) when is_atom(name),
    do: quote_name(Atom.to_string(name))
  defp quote_name(name) do
    if String.contains?(name, "\"") do
      error!(nil, "bad field name #{inspect name}")
    end
    <<?", name::binary, ?">>
  end

  defp quote_table(nil, name),    do: quote_table(name)
  defp quote_table(prefix, name), do: quote_table(prefix) <> "." <> quote_table(name)

  defp quote_table(name) when is_atom(name),
    do: quote_table(Atom.to_string(name))
  defp quote_table(name) do
    if String.contains?(name, "\"") do
      error!(nil, "bad table name #{inspect name}")
    end
    <<?", name::binary, ?">>
  end

  defp error!(nil, message) do
    raise ArgumentError, message
  end
  defp error!(query, message) do
    raise Ecto.QueryError, query: query, message: message
  end
end
