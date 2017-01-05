if Code.ensure_loaded?(Sqlitex.Server) do

  defmodule Sqlite.Ecto.Connection do
    @moduledoc false

    @behaviour Ecto.Adapters.SQL.Query

    ## Connection

    # Connect to a new Sqlite.Server.  Enable and verify the foreign key
    # constraints for the connection.
    def connect(opts) do
      {database, opts} = Keyword.pop(opts, :database)
      case Sqlitex.Server.start_link(database, opts) do
        {:ok, pid} ->
          :ok = Sqlitex.Server.exec(pid, "PRAGMA foreign_keys = ON")
          {:ok, [[foreign_keys: 1]]} = Sqlitex.Server.query(pid, "PRAGMA foreign_keys")
          {:ok, pid}
        error -> error
      end
    end

    def disconnect(pid) do
      Sqlitex.Server.stop(pid)
      :ok
    end

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

    alias Sqlite.Ecto.Result

    defdelegate decode(result_set, mapper), to: Result

    def to_constraints(_), do: []

    ## Transaction

    def begin_transaction do
      "BEGIN"
    end

    def rollback do
      "ROLLBACK"
    end

    def commit do
      "COMMIT"
    end

    def savepoint(savepoint) do
      "SAVEPOINT " <> savepoint
    end

    def rollback_to_savepoint(savepoint) do
      "ROLLBACK TO SAVEPOINT " <> savepoint
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
      distinct_exprs = distinct_exprs(query, sources)

      from = from(sources)
      select = select(query, distinct_exprs, sources)
      join = join(query, sources)
      where = where(query, sources)
      group_by = group_by(query, sources)
      having = having(query, sources)
      order_by = order_by(query, distinct_exprs, sources)
      limit = limit(query, sources)
      offset = offset(query, sources)

      assemble([select, from, join, where, group_by, having, order_by, limit, offset])
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

    defp select(%Query{select: %SelectExpr{fields: fields}, distinct: distinct} = query,
                distinct_exprs, sources) do
      "SELECT " <>
        distinct(distinct, distinct_exprs) <>
        select_fields(fields, sources, query)
    end

    defp select_fields([], _sources, _query),
      do: "1"
    defp select_fields(fields, sources, query),
      do: Enum.map_join(fields, ", ", &expr(&1, sources, query))

    defp distinct_exprs(%Query{distinct: %QueryExpr{expr: exprs}} = query, sources)
        when is_list(exprs) do
      Enum.map_join(exprs, ", ", &expr(&1, sources, query))
    end
    defp distinct_exprs(_, _), do: ""

    defp distinct(nil, _sources), do: ""
    defp distinct(%QueryExpr{expr: true}, _exprs),  do: "DISTINCT "
    defp distinct(%QueryExpr{expr: false}, _exprs), do: ""
    defp distinct(_query, exprs) do
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
            error!(query, "SQLite supports only inner joins on delete_all, got: `#{qual}`")
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

    # Generate a where clause from the given filters.
    defp where_filter(filters), do: where_filter(filters, 1)
    defp where_filter([], _start), do: []
    defp where_filter(filters, start) do
      {filters, _} = Enum.map_reduce filters, start, fn (filter, count) ->
        {"#{quote_id(filter)} = ?#{count}", count + 1}
      end
      ["WHERE" | Enum.intersperse(filters, "AND")]
    end

    defp having(%Query{havings: havings} = query, sources) do
      boolean("HAVING", havings, sources, query)
    end

    defp group_by(%Query{group_bys: group_bys} = query, sources) do
      exprs =
        Enum.map_join(group_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &expr(&1, sources, query))
        end)

      case exprs do
        "" -> []
        _  -> "GROUP BY " <> exprs
      end
    end

    defp order_by(%Query{order_bys: order_bys} = query, distinct_exprs, sources) do
      exprs =
        Enum.map_join(order_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &order_by_expr(&1, sources, query))
        end)

      case {distinct_exprs, exprs} do
        {_, ""} ->
          []
        {"", _} ->
          "ORDER BY " <> exprs
        {_, _}  ->
          "ORDER BY " <> distinct_exprs <> ", " <> exprs
      end
    end

    defp order_by_expr({dir, expr}, sources, query) do
      str = expr(expr, sources, query)
      case dir do
        :asc  -> str
        :desc -> str <> " DESC"
      end
    end

    defp limit(%Query{limit: nil}, _sources), do: []
    defp limit(%Query{limit: %QueryExpr{expr: expr}} = query, sources) do
      "LIMIT " <> expr(expr, sources, query)
    end

    defp offset(%Query{offset: nil}, _sources), do: []
    defp offset(%Query{offset: %QueryExpr{expr: expr}} = query, sources) do
      "OFFSET " <> expr(expr, sources, query)
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
      "#{name}.#{quote_name(field)}"
    end

    defp expr({:&, _, [idx]}, sources, query) do
      {table, name, model} = elem(sources, idx)
      unless model do
        error!(query, "SQLite requires a schema module when using selector " <>
          "#{inspect name} but only the table #{inspect table} was given. " <>
          "Please specify a model or specify exactly which fields from " <>
          "#{inspect name} you desire")
      end
      fields = model.__schema__(:fields)
      Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
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

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "SQLite adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map_join(parts, "", fn
        {:raw, part}  -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
    end

    @datetime_format "strftime('%Y-%m-%d %H:%M:%f000'" # NOTE: Open paren must be closed

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      "CAST (#{@datetime_format},#{expr(datetime, sources, query)},#{interval(count, interval, sources)}) AS TEXT_DATETIME)"
    end

    @date_format "strftime('%Y-%m-%d'" # NOTE: Open paren must be closed

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      "CAST (#{@date_format},#{expr(date, sources, query)},#{interval(count, interval, sources)}) AS TEXT_DATE)"
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

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
        when is_binary(binary) do
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

    # DDL

    alias Ecto.Migration.Table
    alias Ecto.Migration.Index
    alias Ecto.Migration.Reference

    # Raise error on NoSQL arguments.
    def execute_ddl({_command, %Table{options: keyword}, _}) when is_list(keyword) do
      raise ArgumentError, "SQLite adapter does not support keyword lists in :options"
    end

    # Create a table.
    def execute_ddl({command, %Table{} = table, columns})
    when command in [:create, :create_if_not_exists] do
      assemble [create_table(command), quote_table(table), column_definitions(table, columns), table.options]
    end

    # Drop a table.
    def execute_ddl({command, %Table{} = table})
    when command in [:drop, :drop_if_exists] do
      assemble [drop_table(command), quote_table(table)]
    end

    # Alter a table.
    def execute_ddl({:alter, %Table{} = table, changes}) do
      Enum.map_join(changes, "; ", fn (change) ->
        assemble ["ALTER TABLE", quote_table(table), alter_table_suffix(table, change)]
      end)
    end

    # Rename a table.
    def execute_ddl({:rename, %Table{} = old, %Table{} = new}) do
      "ALTER TABLE #{quote_table(old)} RENAME TO #{quote_table(new)}"
    end

    # Rename a table column.
    def execute_ddl({:rename, %Table{}, _old_col, _new_col}) do
      raise ArgumentError, "RENAME COLUMN not supported by SQLite"
    end

    # Create an index.
    # NOTE Ignores concurrently and using values.
    def execute_ddl({command, %Index{}=index})
    when command in [:create, :create_if_not_exists] do
      create_index = create_index(command, index.unique)
      table = quote_table(index.prefix, index.table)
      fields = map_intersperse(index.columns, ",", &quote_id/1)
      assemble [create_index, quote_id(index.name), "ON", table, "(", fields, ")"]
    end

    # Drop an index.
    def execute_ddl({command, %Index{name: name}})
    when command in [:drop, :drop_if_exists] do
      assemble [drop_index(command), quote_id(name)]
    end

    # Raise error on NoSQL arguments.
    def execute_ddl(keyword) when is_list(keyword) do
      raise ArgumentError, "SQLite adapter does not support keyword lists in execute"
    end

    # Default:
    def execute_ddl(default) when is_binary(default), do: default

    defp column_definitions(table, cols) do
      ["(", map_intersperse(cols, ",", &column_definition(table, &1)), ")"]
    end

    defp column_definition(table, {_action, name, ref = %Reference{}, opts}) do
      opts = Enum.into(opts, %{})
      [quote_id(name), column_constraints(opts), reference_expr(ref, table, name)]
    end
    defp column_definition(_table, action), do: column_definition(action)
    defp column_definition({_action, name, type, opts}) do
      opts = Enum.into(opts, %{})
      [quote_id(name), column_type(type, opts), column_constraints(type, opts)]
    end

    # Returns a create table prefix.
    defp create_table(:create), do: "CREATE TABLE"
    defp create_table(:create_if_not_exists), do: "CREATE TABLE IF NOT EXISTS"

    # Returns a drop table prefix.
    defp drop_table(:drop), do: "DROP TABLE"
    defp drop_table(:drop_if_exists), do: "DROP TABLE IF EXISTS"

    # Foreign keys:
    defp reference_expr(%Reference{} = ref, %Table{} = table, col) do
      ["CONSTRAINT", reference_name(ref, table, col),
       "REFERENCES #{quote_table(table.prefix, ref.table)}(#{quote_id(ref.column)})",
       reference_on_delete(ref.on_delete)]
    end

    defp reference_name(%Reference{name: nil}, %Table{name: table}, col) do
      [table, col, "fkey"] |> Enum.join("_") |> quote_id
    end
    defp reference_name(%Reference{name: name}, _table, _col), do: quote_id(name)

    # Decimals are the only type for which we care about the options:
    defp column_type(:decimal, opts=%{precision: precision}) do
      scale = Dict.get(opts, :scale, 0)
      "DECIMAL(#{precision},#{scale})"
    end
    # Simple column types.  Note that we ignore options like :size, :precision,
    # etc. because columns do not have types, and SQLite will not coerce any
    # stored value.  Thus, "strings" are all text and "numerics" have arbitrary
    # precision regardless of the declared column type.  Decimals above are the
    # only exception.
    defp column_type(:serial, _opts), do: "INTEGER"
    defp column_type(:string, _opts), do: "TEXT"
    defp column_type(:map, _opts), do: "TEXT"
    defp column_type({:array, _}, _opts), do: raise(ArgumentError, "Array type is not supported by SQLite")
    defp column_type(type, _opts), do: type |> Atom.to_string |> String.upcase

    # NOTE SQLite requires autoincrement integers to be primary keys
    defp column_constraints(:serial, _), do: "PRIMARY KEY AUTOINCREMENT"
    # Return a string of constraints for the column.
    # NOTE The order of these constraints does not matter to SQLite, but
    # rearranging them may cause tests that rely on their order to fail.
    defp column_constraints(_type, opts), do: column_constraints(opts)
    defp column_constraints(opts=%{primary_key: true}) do
      other_constraints = opts |> Map.delete(:primary_key) |> column_constraints
      ["PRIMARY KEY" | other_constraints]
    end
    defp column_constraints(opts=%{default: default}) do
      val = case default do
        true -> 1
        false -> 0
        {:fragment, expr} -> "(#{expr})"
        string when is_binary(string) -> "'#{string}'"
        other -> other
      end
      other_constraints = opts |> Map.delete(:default) |> column_constraints
      ["DEFAULT", val, other_constraints]
    end
    defp column_constraints(opts=%{null: false}) do
      other_constraints = opts |> Map.delete(:null) |> column_constraints
      ["NOT NULL", other_constraints]
    end
    defp column_constraints(_), do: []

    # Define how to handle deletion of foreign keys on parent table.
    # See: https://www.sqlite.org/foreignkeys.html#fk_actions
    defp reference_on_delete(:nilify_all), do: "ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: "ON DELETE CASCADE"
    defp reference_on_delete(_), do: []

    # Returns a create index prefix.
    defp create_index(:create, unique?), do: create_unique_index(unique?)
    defp create_index(:create_if_not_exists, unique?) do
      [create_unique_index(unique?), "IF NOT EXISTS"]
    end

    defp create_unique_index(true), do: "CREATE UNIQUE INDEX"
    defp create_unique_index(false), do: "CREATE INDEX"

    # Returns a drop index prefix.
    defp drop_index(:drop), do: "DROP INDEX"
    defp drop_index(:drop_if_exists), do: "DROP INDEX IF EXISTS"

    # If we are adding a DATETIME column with the NOT NULL constraint, SQLite
    # will force us to give it a DEFAULT value.  The only default value
    # that makes sense is CURRENT_TIMESTAMP, but when adding a column to a
    # table, defaults must be constant values.
    #
    # Therefore the best option is just to remove the NOT NULL constraint when
    # we add new datetime columns.
    defp alter_table_suffix(_table, {:add, column, :datetime, opts}) do
      opts = opts |> Enum.into(%{}) |> Dict.delete(:null)
      change = {:add, column, :datetime, opts}
      ["ADD COLUMN", column_definition(change)]
    end

    defp alter_table_suffix(table, change={:add, _column, _type, _opts}) do
      ["ADD COLUMN", column_definition(table, change)]
    end

    defp alter_table_suffix(_table, {:modify, _column, _type, _opts}) do
      raise ArgumentError, "ALTER COLUMN not supported by SQLite"
    end

    defp alter_table_suffix(_table, {:remove, _column}) do
      raise ArgumentError, "DROP COLUMN not supported by SQLite"
    end

    ## Helpers

    # Use Ecto's JSON library (currently Poison) for embedded JSON datatypes.
    def json_library, do: Application.get_env(:ecto, :json_library)

    # Initiate a transaction with a savepoint. If any error occurs when we call
    # the func parameter, rollback our changes. Returns the result of the call
    # to func.
    defp with_savepoint(pid, func) do
      sp = "sp_" <> random_id
      :ok = exec(pid, savepoint(sp))
      result = safe_call(pid, func, sp)
      if is_tuple(result) and elem(result, 0) == :error do
        :ok = exec(pid, rollback_to_savepoint(sp))
      end
      :ok = exec(pid, release_savepoint(sp))
      result
    end

    defp release_savepoint(name) do
      "RELEASE " <> name
    end

    # Call func.() and return the result. If any exceptions are encountered,
    # safely rollback and release the transaction.
    defp safe_call(pid, func, sp) do
      try do
        func.()
      rescue
        e in RuntimeError ->
          :ok = exec(pid, rollback_to_savepoint(sp))
          :ok = exec(pid, release_savepoint(sp))
          raise e
      end
    end

    # Execute a SQL query.
    defp exec(pid, sql) do
      case Sqlitex.Server.exec(pid, sql) do
        # busy error means another process is writing to the database; try again
        {:error, {:busy, _}} -> exec(pid, sql)
        res -> res
      end
    end

    # Generate a random string.
    defp random_id, do: :random.uniform |> Float.to_string |> String.slice(2..10)

    defp quote_name(name)
    defp quote_name(name) when is_atom(name),
      do: quote_name(Atom.to_string(name))
    defp quote_name(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad field name #{inspect name}")
      end
      <<?", name::binary, ?">>
    end

    # Quote the given identifier.
    defp quote_id({nil, id}), do: quote_id(id)
    defp quote_id({prefix, table}), do: quote_id(prefix) <> "." <> quote_id(table)
    defp quote_id(id) when is_atom(id), do: id |> Atom.to_string |> quote_id
    defp quote_id(id) do
      if String.contains?(id, "\"") || String.contains?(id, ",") do
        raise ArgumentError, "bad identifier #{inspect id}"
      end
      "\"#{id}\""
    end

    defp quote_table(nil, name),    do: quote_table(name)
    defp quote_table(prefix, name), do: quote_table(prefix) <> "." <> quote_table(name)

    defp quote_table(%Table{prefix: prefix, name: name}) do
      quote_table(prefix, name)
    end
    defp quote_table(name) when is_atom(name),
      do: quote_table(Atom.to_string(name))
    defp quote_table(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad table name #{inspect name}")
      end
      <<?", name::binary, ?">>
    end

    def assemble(list) when is_list(list) do
      list = for x <- List.flatten(list), x != nil, do: x
      Enum.reduce list, fn word, result ->
          if word == "," || word == ")" || String.ends_with?(result, "(") do
            Enum.join([result, word])
          else
            Enum.join([result, word], " ")
          end
      end
    end
    def assemble(literal), do: literal

    # Take a list of items, apply a map, then intersperse the result with
    # another item. Most often used for generating comma-separated fields to
    # assemble.
    defp map_intersperse(list, item, func) when is_function(func, 1) do
      list |> Enum.map(&func.(&1)) |> Enum.intersperse(item)
    end

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end

    defp error!(nil, message) do
      raise ArgumentError, message: message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
