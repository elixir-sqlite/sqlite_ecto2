if Code.ensure_loaded?(Sqlitex.Server) do
  defmodule Sqlite.Ecto2.Connection do
    @moduledoc false

    @behaviour Ecto.Adapters.SQL.Connection

    # IMPORTANT: This is closely modeled on Ecto's postgres/connection.exs file.
    # We strive to avoid structural differences between that file and this one.

    ## Module and Options

    def child_spec(opts) do
      {:ok, _} = Application.ensure_all_started(:db_connection)
      DBConnection.child_spec(Sqlite.DbConnection.Protocol, opts)
    end

    def to_constraints(_), do: []

    ## Query

    def prepare_execute(conn, name, sql, params, opts) do
      query = %Sqlite.DbConnection.Query{name: name, statement: sql}
      case DBConnection.prepare_execute(conn, query, map_params(params), opts) do
        {:ok, _, _} = ok ->
          ok
        {:error, %Sqlite.DbConnection.Error{}} = error ->
          error
        {:error, err} ->
          raise err
      end
    end

    def execute(conn, sql, params, opts) when is_binary(sql) or is_list(sql) do
      query = %Sqlite.DbConnection.Query{name: "", statement: IO.iodata_to_binary(sql)}
      case DBConnection.prepare_execute(conn, query, map_params(params), opts) do
        {:ok, %Sqlite.DbConnection.Query{}, result} ->
          {:ok, result}
        {:error, %Sqlite.DbConnection.Error{}} = error ->
          error
        {:error, err} ->
          raise err
      end
    end

    def execute(conn, query, params, opts) do
      case DBConnection.execute(conn, query, map_params(params), opts) do
        {:ok, _} = ok ->
          ok
        {:error, %ArgumentError{} = err} ->
          {:reset, err}
        {:error, %Sqlite.DbConnection.Error{}} = error ->
          error
        {:error, err} ->
          raise err
      end
    end

    def stream(conn, sql, params, opts) do
      %Sqlite.DbConnection.Stream{conn: conn, query: sql, params: params, options: opts}
    end

    defp map_params(params) do
      Enum.map params, fn
        %{__struct__: _} = data_type ->
          {:ok, value} = Ecto.DataType.dump(data_type)
          value
        %{} = value ->
          Ecto.Adapter.json_library().encode!(value)
        value ->
          value
      end
    end

    alias Ecto.Query
    alias Ecto.Query.BooleanExpr
    alias Ecto.Query.JoinExpr
    alias Ecto.Query.QueryExpr

    def all(%Ecto.Query{lock: lock}) when lock != nil do
      raise ArgumentError, "locks are not supported by SQLite"
    end
    def all(query) do
      sources = create_names(query, :select)
      {select_distinct, order_by_distinct} = distinct(query.distinct, sources, query)

      from = from(query, sources)
      select = select(query, select_distinct, sources)
      join = join(query, sources)
      where = where(query, sources)
      group_by = group_by(query, sources)
      having = having(query, sources)
      order_by = order_by(query, order_by_distinct, sources)
      limit = limit(query, sources)
      offset = offset(query, sources)

      [select, from, join, where, group_by, having, order_by, limit, offset]
    end

    def update_all(%Ecto.Query{joins: [_ | _]}) do
      raise ArgumentError, "JOINS are not supported on UPDATE statements by SQLite"
    end
    def update_all(%{from: from} = query, prefix \\ nil) do
      sources = create_names(query, :update)
      {from, _name} = get_source(query, sources, 0, from)

      prefix = prefix || ["UPDATE ", from, " SET "]
      fields = update_fields(query, sources)
      where = where(%{query | wheres: query.wheres}, sources)

      [prefix, fields, where | returning(query, sources, :update)]
    end

    def delete_all(%Ecto.Query{joins: [_ | _]}) do
      raise ArgumentError, "JOINS are not supported on DELETE statements by SQLite"
    end
    def delete_all(%{from: from} = query) do
      sources = create_names(query, :delete)
      {from, _name} = get_source(query, sources, 0, from)

      where = where(%{query | wheres: query.wheres}, sources)

      ["DELETE FROM ", from, where | returning(query, sources, :delete)]
    end

    def insert(prefix, table, header, rows, on_conflict, returning) do
      values =
        if header == [] do
          " DEFAULT VALUES"
        else
          [?\s, ?(, intersperse_map(header, ?,, &quote_name/1), ") VALUES " | insert_all(rows, 1)]
        end

      on_conflict = case on_conflict do
        {:raise, [], []} -> ""
        {:nothing, [], []} -> " OR IGNORE"
        _ -> raise ArgumentError, "Upsert in SQLite must use on_conflict: :nothing"
      end
      returning = returning_clause(prefix, table, returning, "INSERT")
      ["INSERT", on_conflict, " INTO ", quote_table(prefix, table), values, returning]
    end

    defp insert_all(rows, counter) do
      intersperse_reduce(rows, ?,, counter, fn row, counter ->
        {row, counter} = insert_each(row, counter)
        {[?(, row, ?)], counter}
      end)
      |> elem(0)
    end

    defp insert_each(values, counter) do
      intersperse_reduce(values, ?,, counter, fn
        nil, _counter ->
          raise ArgumentError, "Cell-wise default values are not supported on INSERT statements by SQLite"
        _, counter ->
          {[?? | Integer.to_string(counter)], counter + 1}
      end)
    end

    def update(prefix, table, fields, filters, returning) do
      {fields, count} = intersperse_reduce(fields, ", ", 1, fn field, acc ->
        {[quote_name(field), " = ?" | Integer.to_string(acc)], acc + 1}
      end)

      {filters, _count} = intersperse_reduce(filters, " AND ", count, fn field, acc ->
        {[quote_name(field), " = ?" | Integer.to_string(acc)], acc + 1}
      end)

      return = returning_clause(prefix, table, returning, "UPDATE")

      ["UPDATE ", quote_table(prefix, table), " SET ",
       fields, " WHERE ", filters | return]
    end

    def delete(prefix, table, filters, returning) do
      {filters, _} = intersperse_reduce(filters, " AND ", 1, fn field, acc ->
        {[quote_name(field), " = ?" | Integer.to_string(acc)], acc + 1}
      end)

      ["DELETE FROM ", quote_table(prefix, table), " WHERE ",
       filters | returning_clause(prefix, table, returning, "DELETE")]
    end

    ## Query generation

    binary_ops =
      [==: " = ", !=: " != ", <=: " <= ", >=: " >= ", <: " < ", >: " > ",
       and: " AND ", or: " OR ", ilike: " ILIKE ", like: " LIKE "]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%Query{select: %{fields: fields}} = query, select_distinct, sources) do
      ["SELECT", select_distinct, ?\s | select_fields(fields, sources, query)]
    end

    defp select_fields([], _sources, _query),
      do: "1"
    defp select_fields(fields, sources, query) do
      intersperse_map(fields, ", ", fn
        {key, value} ->
          [expr(value, sources, query), " AS " | quote_name(key)]
        value ->
          expr(value, sources, query)
      end)
    end

    defp distinct(nil, _, _), do: {[], []}
    defp distinct(%QueryExpr{expr: []}, _, _), do: {[], []}
    defp distinct(%QueryExpr{expr: true}, _, _), do: {" DISTINCT", []}
    defp distinct(%QueryExpr{expr: false}, _, _), do: {[], []}
    defp distinct(_expr, _sources, _query) do
      raise ArgumentError, "DISTINCT with multiple columns is not supported by SQLite"
    end

    defp from(%{from: from} = query, sources) do
      {from, name} = get_source(query, sources, 0, from)
      [" FROM ", from, " AS " | name]
    end

    defp update_fields(%Query{updates: updates} = query, sources) do
      for(%{expr: expr} <- updates,
          {op, kw} <- expr,
          {key, value} <- kw,
          do: update_op(op, key, value, sources, query)) |> Enum.intersperse(", ")
    end

    defp update_op(:set, key, value, sources, query) do
      [quote_name(key), " = ", expr(value, sources, query)]
    end

    defp update_op(:inc, key, value, sources, query) do
      [quote_name(key), " = ", quote_qualified_name(key, sources, 0), " + " |
       expr(value, sources, query)]
    end

    defp update_op(:push, _key, _value, _sources, _query) do
      raise ArgumentError, "Array operations are not supported by SQLite"
    end

    defp update_op(:pull, _key, _value, _sources, _query) do
      raise ArgumentError, "Array operations are not supported by SQLite"
    end

    defp join(%Query{joins: []}, _sources), do: []
    defp join(%Query{joins: joins} = query, sources) do
      [?\s | intersperse_map(joins, ?\s, fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source} ->
          {join, name} = get_source(query, sources, ix, source)
          [join_qual(qual), join, " AS ", name, " ON " | expr(expr, sources, query)]
      end)]
    end

    defp join_qual(:inner), do: "INNER JOIN "
    defp join_qual(:left), do: "LEFT JOIN "
    defp join_qual(mode), do: raise ArgumentError, "join `#{inspect mode}` not supported by SQLite"

    defp where(%Query{wheres: wheres} = query, sources) do
      boolean(" WHERE ", wheres, sources, query)
    end

    defp having(%Query{havings: havings} = query, sources) do
      boolean(" HAVING ", havings, sources, query)
    end

    defp group_by(%Query{group_bys: []}, _sources), do: []
    defp group_by(%Query{group_bys: group_bys} = query, sources) do
      [" GROUP BY " |
       intersperse_map(group_bys, ", ", fn
          %QueryExpr{expr: expr} ->
           intersperse_map(expr, ", ", &expr(&1, sources, query))
       end)]
    end

    defp order_by(%Query{order_bys: []}, _distinct, _sources), do: []
    defp order_by(%Query{order_bys: order_bys} = query, distinct, sources) do
      order_bys = Enum.flat_map(order_bys, & &1.expr)
      [" ORDER BY " |
       intersperse_map(distinct ++ order_bys, ", ", &order_by_expr(&1, sources, query))]
    end

    defp order_by_expr({dir, expr}, sources, query) do
      str = expr(expr, sources, query)
      case dir do
        :asc  -> str
        :desc -> [str | " DESC"]
      end
    end

    defp limit(%Query{limit: nil}, _sources), do: []
    defp limit(%Query{limit: %QueryExpr{expr: expr}} = query, sources) do
      [" LIMIT " | expr(expr, sources, query)]
    end

    defp offset(%Query{offset: nil}, _sources), do: []
    defp offset(%Query{offset: %QueryExpr{expr: expr}} = query, sources) do
      [" OFFSET " | expr(expr, sources, query)]
    end

    defp boolean(_name, [], _sources, _query), do: []
    defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
      [name |
       Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
         %BooleanExpr{expr: expr, op: op}, {op, acc} ->
           {op, [acc, operator_to_boolean(op), paren_expr(expr, sources, query)]}
         %BooleanExpr{expr: expr, op: op}, {_, acc} ->
           {op, [?(, acc, ?), operator_to_boolean(op), paren_expr(expr, sources, query)]}
       end) |> elem(1)]
    end

    defp operator_to_boolean(:and), do: " AND "
    defp operator_to_boolean(:or), do: " OR "

    defp paren_expr(expr, sources, query) do
      [?(, expr(expr, sources, query), ?)]
    end

    defp expr({:^, [], [ix]}, _sources, _query) do
      [?? | Integer.to_string(ix + 1)]
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query) when is_atom(field) do
      quote_qualified_name(field, sources, idx)
    end

    defp expr({:&, _, [idx]}, sources, query) do
      {source, _name, _schema} = elem(sources, idx)
      error!(query, "SQLite does not support selecting all fields from #{source} without a schema. " <>
                      "Please specify a schema or specify exactly which fields you want to select")
    end

    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = intersperse_map(right, ?,, &expr(&1, sources, query))
      [expr(left, sources, query), " IN (", args, ?)]
    end

    defp expr({:in, _, [left, {:^, _, [_ix, 0]}]}, sources, query) do
      [expr(left, sources, query), " IN ()"]
    end

    defp expr({:in, _, [left, {:^, _, [ix, length]}]}, sources, query) do
      args = Enum.map_join ix + 1 .. ix + length, ",", &"?#{&1}"
      [expr(left, sources, query), " IN (", args, ")"]
    end

    defp expr({:in, _, [left, right]}, sources, query) do
      [expr(left, sources, query), " IN (", expr(right, sources, query), ?)]
    end

    defp expr({:is_nil, _, [arg]}, sources, query) do
      [expr(arg, sources, query) | " IS NULL"]
    end

    defp expr({:not, _, [expr]}, sources, query) do
      ["NOT (", expr(expr, sources, query), ?)]
    end

    defp expr(%Ecto.SubQuery{query: query}, _sources, _query) do
      all(query)
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "SQLite adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map(parts, fn
        {:raw, part}  -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
    end

    @datetime_format "strftime('%Y-%m-%d %H:%M:%f000'" # NOTE: Open paren must be closed

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      ["CAST (", @datetime_format, ",", expr(datetime, sources, query), ",", interval(count, interval, sources), ") AS TEXT_DATETIME)"]
    end

    @date_format "strftime('%Y-%m-%d'" # NOTE: Open paren must be closed

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      ["CAST (", @date_format, ",", expr(date, sources, query), ",", interval(count, interval, sources), ") AS TEXT_DATE)"]
    end

    defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
      {modifier, args} =
        case args do
          [rest, :distinct] -> {"DISTINCT ", [rest]}
          _ -> {[], args}
       end

      case handle_call(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          [op_to_binary(left, sources, query), op | op_to_binary(right, sources, query)]
        {:fun, fun} ->
          [fun, ?(, modifier, intersperse_map(args, ", ", &expr(&1, sources, query)), ?)]
      end
    end

    defp expr(list, _sources, _query) when is_list(list) do
      raise ArgumentError, "Array values are not supported by SQLite"
    end

    defp expr(%Decimal{} = decimal, _sources, _query) do
      Decimal.to_string(decimal, :normal)
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
        when is_binary(binary) do
      ["X'", Base.encode16(binary, case: :upper), "'"]
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) when type in [:id, :integer, :float] do
      expr(other, sources, query)
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
      ["CAST (", expr(other, sources, query), " AS ", ecto_to_db(type), ?)]
    end

    defp expr(nil, _sources, _query),   do: "NULL"
    defp expr(true, _sources, _query),  do: "1"
    defp expr(false, _sources, _query), do: "0"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      [?\', escape_string(literal), ?\']
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      Float.to_string(literal)
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
      paren_expr(expr, sources, query)
    end

    defp op_to_binary(expr, sources, query) do
      expr(expr, sources, query)
    end

    ## Returning Clause Helpers

    @pseudo_returning_statement " ;--RETURNING ON "

    # SQLite does not have a returning clause, but we append a pseudo one so
    # that query() can parse the string later and emulate it with a
    # transaction and trigger. See corresponding code in Sqlitex.

    defp returning(%Query{select: nil}, _sources, _cmd), do: []
    defp returning(%Query{select: %{fields: field_tuples}}, sources, cmd) do
      cmd = cmd |> Atom.to_string |> String.upcase
      table = table_from_first_source(sources)
      fields = Enum.map_join([table | Enum.map(field_tuples, &field_from_field_tuple/1)],
                             ",", &quote_id/1)
      [@pseudo_returning_statement, cmd, ?\s, fields]
    end

    defp table_from_first_source(sources) do
      sources
      |> elem(0)
      |> elem(1) # yeah, this is odd
      |> IO.iodata_to_binary
      |> String.trim("\"")
    end

    defp field_from_field_tuple({{:., [], [{:&, [], [0]}, f]}, [], []}), do: f

    defp returning_clause(_prefix, _table, [], _cmd), do: []
    defp returning_clause(prefix, table, returning, cmd) do
      fields = Enum.map_join([{prefix, table} | returning], ",", &quote_id/1)
      [@pseudo_returning_statement, cmd, ?\s, fields]
    end

    defp ecto_to_db({:array, _}) do
      raise ArgumentError, "Array type is not supported by SQLite"
    end

    defp ecto_to_db(:id), do: "INTEGER"
    defp ecto_to_db(:binary_id), do: "TEXT"
    defp ecto_to_db(:uuid), do: "TEXT" # SQLite does not support UUID
    defp ecto_to_db(:binary), do: "BLOB"
    defp ecto_to_db(:float), do: "NUMERIC"
    defp ecto_to_db(:string), do: "TEXT"
    defp ecto_to_db(:utc_datetime), do: "TEXT_DATETIME"    # see below
    defp ecto_to_db(:naive_datetime), do: "TEXT_DATETIME"  # see below
    defp ecto_to_db(:map), do: "TEXT"
    defp ecto_to_db(other), do: other |> Atom.to_string |> String.upcase

    # We use a special conversion for when the user is trying to cast to a
    # DATETIME type. We introduce a TEXT_DATETIME psudo-type to preserve the
    # datetime string. When we get here, we look for a CAST function as a signal
    # to convert that back to Elixir date types.

    defp create_names(%{prefix: prefix, sources: sources}, stmt) do
      create_names(prefix, sources, 0, tuple_size(sources), stmt)
      |> prohibit_subquery_if_necessary(stmt)
      |> List.to_tuple
    end

    defp create_names(prefix, sources, pos, limit, stmt) when pos < limit do
      current =
        case elem(sources, pos) do
          {table, schema} ->
            name = [String.first(table) | Integer.to_string(pos)]
            {quote_table(prefix, table), name, schema}
          {:fragment, _, _} ->
            {nil, [?f | Integer.to_string(pos)], nil}
          %Ecto.SubQuery{} ->
            {nil, [?s | Integer.to_string(pos)], nil}
        end
      [current | create_names(prefix, sources, pos + 1, limit, stmt)]
    end

    defp create_names(_prefix, _sources, pos, pos, _stmt) do
      []
    end

    defp prohibit_subquery_if_necessary([first | rest], stmt)
      when stmt in [:update, :delete]
    do
      [rewrite_main_table(first) | prohibit_subquery_tables(rest)]
    end

    defp prohibit_subquery_if_necessary(sources, _stmt), do: sources

    defp rewrite_main_table({table, _name, schema}) do
      {table, table, schema}
    end

    defp prohibit_subquery_tables(other_sources) do
      if Enum.any?(other_sources, &subquery_table?/1) do
        raise ArgumentError, "SQLite adapter does not support subqueries"
      else
        other_sources
      end
    end

    defp subquery_table?({nil, _, _}), do: false
    defp subquery_table?(_), do: true

    # DDL

    alias Ecto.Migration.Constraint
    alias Ecto.Migration.Index
    alias Ecto.Migration.Reference
    alias Ecto.Migration.Table

    @drops [:drop, :drop_if_exists]

    # Raise error on NoSQL arguments.
    def execute_ddl({_command, %Table{options: keyword}, _}) when is_list(keyword) do
      raise ArgumentError, "SQLite adapter does not support keyword lists in :options"
    end

    def execute_ddl({command, %Table{} = table, columns}) when command in [:create, :create_if_not_exists] do
      # If more than one has primary_key: true then we alter table with %{table | primary_key: :composite}.
      {table, composite_pk_def} = composite_pk_definition(table, columns)

      [["CREATE TABLE ",
        if_do(command == :create_if_not_exists, "IF NOT EXISTS "),
        quote_table(table.prefix, table.name), ?\s, ?(,
        column_definitions(table, columns), composite_pk_def, ?),
        options_expr(table.options)]]
    end

    def execute_ddl({command, %Table{} = table}) when command in @drops do
      [["DROP TABLE ", if_do(command == :drop_if_exists, "IF EXISTS "),
        quote_table(table.prefix, table.name)]]
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      Enum.map(changes, fn (change) ->
        ["ALTER TABLE ", quote_table(table.prefix, table.name), ?\s, column_change(table, change)]
      end)
    end

    # NOTE Ignores concurrently and using values.
    def execute_ddl({command, %Index{} = index})
      when command in [:create, :create_if_not_exists]
    do
      fields = intersperse_map(index.columns, ", ", &index_expr/1)

      [["CREATE ",
        if_do(index.unique, "UNIQUE "),
        "INDEX",
        if_do(command == :create_if_not_exists, " IF NOT EXISTS"),
        ?\s,
        quote_name(index.name),
        " ON ",
        quote_table(index.prefix, index.table),
        ?\s, ?(, fields, ?),
        if_do(index.where, [" WHERE ", to_string(index.where)])]]
    end

    def execute_ddl({command, %Index{} = index}) when command in @drops do
      if_exists = if command == :drop_if_exists, do: "IF EXISTS ", else: []

      [["DROP INDEX ",
        if_exists,
        quote_table(index.prefix, index.name)]]
    end

    def execute_ddl({:rename, %Table{} = current_table, %Table{} = new_table}) do
      [["ALTER TABLE ", quote_table(current_table.prefix, current_table.name),
        " RENAME TO ", quote_table(nil, new_table.name)]]
    end

    def execute_ddl({:rename, %Table{}, _old_col, _new_col}) do
      raise ArgumentError, "RENAME COLUMN not supported by SQLite"
    end

    def execute_ddl({command, %Constraint{}})
      when command in [:create, :drop]
    do
      raise ArgumentError, "ALTER TABLE with constraints not supported by SQLite"
    end

    def execute_ddl(string) when is_binary(string), do: [string]

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "SQLite adapter does not support keyword lists in execute")

    defp column_definitions(table, columns) do
      intersperse_map(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      [quote_name(name), ?\s, reference_column_type(ref.type, opts),
        column_options(table, ref.type, opts), reference_expr(ref, table, name)]
    end

    defp column_definition(table, {:add, name, type, opts}) do
      [quote_name(name), ?\s, column_type(type, opts), column_options(table, type, opts)]
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      ["ADD COLUMN ", quote_name(name), ?\s, reference_column_type(ref.type, opts),
        column_options(table, ref.type, opts), reference_expr(ref, table, name)]
    end

    # If we are adding a DATETIME column with the NOT NULL constraint, SQLite
    # will force us to give it a DEFAULT value. The only default value
    # that makes sense is CURRENT_TIMESTAMP, but when adding a column to a
    # table, defaults must be constant values.
    #
    # Therefore the best option is just to remove the NOT NULL constraint when
    # we add new datetime columns.
    defp column_change(table, {:add, name, type, opts})
      when type in [:utc_datetime, :naive_datetime]
    do
      opts = Keyword.delete(opts, :null)
      ["ADD COLUMN ", quote_name(name), ?\s, column_type(type, opts), column_options(table, type, opts)]
    end

    defp column_change(table, {:add, name, type, opts}) do
      ["ADD COLUMN ", quote_name(name), ?\s, column_type(type, opts), column_options(table, type, opts)]
    end

    defp column_change(_table, {:modify, _name, _type, _opts}) do
      raise ArgumentError, "ALTER COLUMN not supported by SQLite"
    end

    defp column_change(_table, {:remove, _name, _type, _opts}) do
      raise ArgumentError, "ALTER COLUMN not supported by SQLite"
    end

    defp column_change(_table, {:remove, :summary}) do
      raise ArgumentError, "DROP COLUMN not supported by SQLite"
    end

    defp column_options(table, type, opts) do
      default = Keyword.fetch(opts, :default)
      null    = Keyword.get(opts, :null)
      pk      = (table.primary_key != :composite) and Keyword.get(opts, :primary_key, false)

      column_options(default, type, null, pk)
    end

    defp column_options(_default, :serial, _, true) do
      " PRIMARY KEY AUTOINCREMENT"
    end
    defp column_options(default, type, null, pk) do
      [default_expr(default, type), null_expr(null), pk_expr(pk)]
    end

    defp pk_expr(true), do: " PRIMARY KEY"
    defp pk_expr(_), do: []

    defp composite_pk_definition(%Table{} = table, columns) do
      pks = Enum.reduce(columns, [], fn({_, name, _, opts}, pk_acc) ->
        case Keyword.get(opts, :primary_key, false) do
          true -> [name | pk_acc]
          false -> pk_acc
        end
      end)
      if length(pks) > 1 do
        composite_pk_expr = pks |> Enum.reverse |> Enum.map_join(", ", &quote_name/1)
        {%{table | primary_key: :composite}, ", PRIMARY KEY (" <> composite_pk_expr <> ")"}
      else
        {table, ""}
      end
    end

    defp null_expr(false), do: " NOT NULL"
    # defp null_expr(true), do: " NULL"  # SQLite does not allow this syntax.
    defp null_expr(_), do: []

    defp default_expr({:ok, nil}, _type),
      do: " DEFAULT NULL"
    defp default_expr({:ok, true}, _type),
      do: " DEFAULT 1"
    defp default_expr({:ok, false}, _type),
      do: " DEFAULT 0"
    defp default_expr({:ok, literal}, _type) when is_binary(literal),
      do: [" DEFAULT '", escape_string(literal), ?']
    defp default_expr({:ok, literal}, _type) when is_number(literal) or is_boolean(literal),
      do: [" DEFAULT ", to_string(literal)]
    defp default_expr({:ok, %{} = map}, :map) do
      default = Ecto.Adapter.json_library().encode!(map)
      [" DEFAULT ", single_quote(default)]
    end
    defp default_expr({:ok, {:fragment, expr}}, _type),
      do: [" DEFAULT ", expr]
    defp default_expr({:ok, expr}, type),
      do: raise(ArgumentError, "unknown default `#{inspect expr}` for type `#{inspect type}`. " <>
                               ":default may be a string, number, boolean, empty list, map (when type is Map), or a fragment(...)")
    defp default_expr(:error, _),
      do: []

    defp index_expr(literal) when is_binary(literal),
      do: literal
    defp index_expr(literal),
      do: quote_name(literal)

    defp options_expr(nil),
      do: []
    defp options_expr(options) when is_binary(options),
      do: [?\s, options]

    # Simple column types. Note that we ignore options like :size, :precision,
    # etc. because columns do not have types, and SQLite will not coerce any
    # stored value. Thus, "strings" are all text and "numerics" have arbitrary
    # precision regardless of the declared column type. Decimals are the
    # only exception.
    defp column_type(:serial, _opts), do: "INTEGER"
    defp column_type(:bigserial, _opts), do: "INTEGER"
    defp column_type(:string, _opts), do: "TEXT"
    defp column_type(:map, _opts), do: "TEXT"
    defp column_type({:map, _}, _opts), do: "TEXT"
    defp column_type({:array, _}, _opts), do: raise(ArgumentError, "Array type is not supported by SQLite")
    defp column_type(:decimal, opts) do
      # We only store precision and scale for DECIMAL.
      precision = Keyword.get(opts, :precision)
      scale = Keyword.get(opts, :scale, 0)

      decimal_column_type(precision, scale)
    end
    defp column_type(type, _opts), do: type |> Atom.to_string |> String.upcase

    defp decimal_column_type(precision, scale) when is_integer(precision), do:
      "DECIMAL(#{precision},#{scale})"
    defp decimal_column_type(_precision, _scale), do: "DECIMAL"

    defp reference_expr(%Reference{} = ref, table, name),
      do: [" CONSTRAINT ", reference_name(ref, table, name), " REFERENCES ",
           quote_table(table.prefix, ref.table), ?(, quote_name(ref.column), ?),
           reference_on_delete(ref.on_delete), reference_on_update(ref.on_update)]

    # A reference pointing to a serial column becomes integer in SQLite
    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")
    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "INTEGER"
    defp reference_column_type(:bigserial, _opts), do: "INTEGER"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(_), do: []

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(_), do: []

        ## Helpers

    defp get_source(query, sources, ix, source) do
      {expr, name, _schema} = elem(sources, ix)
      {expr || paren_expr(source, sources, query), name}
    end

    defp quote_qualified_name(name, sources, ix) do
      {_, source, _} = elem(sources, ix)
      [source, ?. | quote_name(name)]
    end

    defp quote_name(name) when is_atom(name) do
      quote_name(Atom.to_string(name))
    end
    defp quote_name(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad field name #{inspect name}")
      end
      [?", name, ?"]
    end

    # Quote the given identifier.
    defp quote_id({nil, id}), do: quote_name(id)
    defp quote_id({prefix, id}), do: [quote_name(prefix), ?., quote_name(id)]
    defp quote_id(id), do: quote_name(id)

    defp quote_table(nil, name),    do: quote_table(name)
    defp quote_table(prefix, name), do: [quote_table(prefix), ?., quote_table(name)]

    defp quote_table(name) when is_atom(name),
      do: quote_table(Atom.to_string(name))
    defp quote_table(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad table name #{inspect name}")
      end
      [?", name, ?"]
    end

    defp single_quote(value), do: [?', escape_string(value), ?']

    defp intersperse_map(list, separator, mapper, acc \\ [])
    defp intersperse_map([], _separator, _mapper, acc),
      do: acc
    defp intersperse_map([elem], _separator, mapper, acc),
      do: [acc | mapper.(elem)]
    defp intersperse_map([elem | rest], separator, mapper, acc),
      do: intersperse_map(rest, separator, mapper, [acc, mapper.(elem), separator])

    defp intersperse_reduce(list, separator, user_acc, reducer, acc \\ [])
    defp intersperse_reduce([], _separator, user_acc, _reducer, acc),
      do: {acc, user_acc}
    defp intersperse_reduce([elem], _separator, user_acc, reducer, acc) do
      {elem, user_acc} = reducer.(elem, user_acc)
      {[acc | elem], user_acc}
    end
    defp intersperse_reduce([elem | rest], separator, user_acc, reducer, acc) do
      {elem, user_acc} = reducer.(elem, user_acc)
      intersperse_reduce(rest, separator, user_acc, reducer, [acc, elem, separator])
    end

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end

    defp error!(nil, message) do
      raise ArgumentError, message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
