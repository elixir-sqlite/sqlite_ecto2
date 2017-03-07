if Code.ensure_loaded?(Sqlitex.Server) do

  defmodule Sqlite.Ecto.Connection do
    @moduledoc false

    @behaviour Ecto.Adapters.SQL.Connection

    ## Module and Options

    def connection(opts) do
      {Sqlite.DbConnection.Protocol, opts}
    end

    def to_constraints(_), do: []

    ## Query

    def prepare_execute(conn, name, sql, params, opts) do
      query = %Sqlite.DbConnection.Query{name: name, statement: sql}
      DBConnection.prepare_execute(conn, query, map_params(params), opts)
    end

    def execute(conn, sql, params, opts) when is_binary(sql) do
      query = %Sqlite.DbConnection.Query{name: "", statement: sql}
      case DBConnection.prepare_execute(conn, query, map_params(params), opts) do
        {:ok, %Sqlite.DbConnection.Query{}, result} ->
          {:ok, result}
        other ->
          other
      end
    end

    def execute(conn, query, params, opts) do
      DBConnection.execute(conn, query, map_params(params), opts)
    end

    defp map_params(params) do
      Enum.map params, fn
        %Ecto.Query.Tagged{type: :binary, value: value} -> {:blob, value}
        %Ecto.Query.Tagged{value: value} -> value
        %{__struct__: _} = value -> value
        %{} = value -> json_library().encode!(value)
        value -> value
      end
    end

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

    def insert(prefix, table, header, rows, returning) do
      values =
        if header == [] do
          "DEFAULT VALUES"
        else
          "(" <> Enum.map_join(header, ",", &quote_name/1) <> ") " <>
          "VALUES " <> insert_all(rows, 1, "")
        end

      return = String.rstrip(" " <> assemble(returning_clause(prefix, table, returning, "INSERT")))
      "INSERT INTO #{quote_table(prefix, table)} #{values}#{return}"
    end

    defp insert_all([row|rows], counter, acc) do
      {counter, row} = insert_each(row, counter, "")
      insert_all(rows, counter, acc <> ",(" <> row <> ")")
    end
    defp insert_all([], _counter, "," <> acc) do
      acc
    end

    defp insert_each([nil|_t], _counter, _acc),
      do: raise ArgumentError, "Cell-wise default values are not supported on INSERT statements by SQLite"
    defp insert_each([_|t], counter, acc),
      do: insert_each(t, counter + 1, acc <> ",?" <> Integer.to_string(counter))
    defp insert_each([], counter, "," <> acc),
      do: {counter, acc}

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

    # SQLite does not have a returning clause, but we append a pseudo one so
    # that query() can parse the string later and emulate it with a
    # transaction and trigger. See corresponding code in Sqlitex.

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
    defp distinct(_query, _exprs) do
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

    defp expr({:&, _, [idx, fields]}, sources, query) do
      {table, name, schema} = elem(sources, idx)
      if is_nil(schema) and is_nil(fields) do
        error!(query, "SQLite requires a schema module when using selector " <>
          "#{inspect name} but only the table #{inspect table} was given. " <>
          "Please specify a model or specify exactly which fields from " <>
          "#{inspect name} you desire")
      end
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

    # DDL

    alias Ecto.Migration.{Table, Index, Reference, Constraint}

    @drops [:drop, :drop_if_exists]

    # Raise error on NoSQL arguments.
    def execute_ddl({_command, %Table{options: keyword}, _}) when is_list(keyword) do
      raise ArgumentError, "SQLite adapter does not support keyword lists in :options"
    end

    def execute_ddl({command, %Table{} = table, columns})
      when command in [:create, :create_if_not_exists]
    do
      options       = options_expr(table.options)
      if_not_exists = if command == :create_if_not_exists, do: " IF NOT EXISTS", else: ""
      # if more than one has primary_key: true then we alte table with %{table | primary_key: :composite}
      {table, composite_pk_def} = composite_pk_definition(table, columns)

      "CREATE TABLE" <> if_not_exists <>
        " #{quote_table(table.prefix, table.name)} (#{column_definitions(table, columns)}#{composite_pk_def})" <> options
    end

    def execute_ddl({command, %Table{}=table}) when command in @drops do
      if_exists = if command == :drop_if_exists, do: " IF EXISTS", else: ""

      "DROP TABLE" <> if_exists <> " #{quote_table(table.prefix, table.name)}"
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      Enum.map_join(changes, "; ", fn (change) ->
        "ALTER TABLE #{quote_table(table.prefix, table.name)} #{column_change(table, change)}"
      end)
    end

    # NOTE Ignores concurrently and using values.
    def execute_ddl({command, %Index{}=index})
      when command in [:create, :create_if_not_exists]
    do
      fields = Enum.map_join(index.columns, ", ", &index_expr/1)
      if_not_exists = if command == :create_if_not_exists, do: "IF NOT EXISTS", else: []

      assemble(["CREATE",
                if_do(index.unique, "UNIQUE"),
                "INDEX",
                if_not_exists,
                quote_name(index.name),
                "ON",
                quote_table(index.prefix, index.table),
                "(#{fields})",
                if_do(index.where, "WHERE #{index.where}")])
    end

    def execute_ddl({command, %Index{}=index}) when command in @drops do
      if_exists = if command == :drop_if_exists, do: "IF EXISTS", else: []

      assemble(["DROP",
                "INDEX",
                if_exists,
                quote_table(index.prefix, index.name)])
    end

    def execute_ddl({:rename, %Table{}=current_table, %Table{}=new_table}) do
      "ALTER TABLE #{quote_table(current_table.prefix, current_table.name)} RENAME TO #{quote_table(new_table.prefix, new_table.name)}"
    end

    def execute_ddl({:rename, %Table{}, _old_col, _new_col}) do
      raise ArgumentError, "RENAME COLUMN not supported by SQLite"
    end

    def execute_ddl({command, %Constraint{}})
      when command in [:create, :drop]
    do
      raise ArgumentError, "ALTER TABLE with constraints not supported by SQLite"
    end

    def execute_ddl(string) when is_binary(string), do: string

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "SQLite adapter does not support keyword lists in execute")

        defp column_definitions(table, columns) do
      Enum.map_join(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      assemble([
        quote_name(name), reference_column_type(ref.type, opts),
        column_options(table, ref.type, opts), reference_expr(ref, table, name)
      ])
    end

    defp column_definition(table, {:add, name, type, opts}) do
      assemble([quote_name(name), column_type(type, opts), column_options(table, type, opts)])
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      assemble([
        "ADD COLUMN", quote_name(name), reference_column_type(ref.type, opts),
        column_options(table, ref.type, opts), reference_expr(ref, table, name)
      ])
    end

    # If we are adding a DATETIME column with the NOT NULL constraint, SQLite
    # will force us to give it a DEFAULT value.  The only default value
    # that makes sense is CURRENT_TIMESTAMP, but when adding a column to a
    # table, defaults must be constant values.
    #
    # Therefore the best option is just to remove the NOT NULL constraint when
    # we add new datetime columns.
    defp column_change(table, {:add, name, :datetime, opts}) do
      opts = opts |> Enum.into(%{}) |> Map.delete(:null)
      assemble(["ADD COLUMN", quote_name(name), column_type(:datetime, opts), column_options(table, :datetime, opts)])
    end

    defp column_change(table, {:add, name, type, opts}) do
      assemble(["ADD COLUMN", quote_name(name), column_type(type, opts), column_options(table, type, opts)])
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
      "PRIMARY KEY AUTOINCREMENT"
    end
    defp column_options(default, type, null, pk) do
      [default_expr(default, type), null_expr(null), pk_expr(pk)]
    end

    defp pk_expr(true), do: "PRIMARY KEY"
    defp pk_expr(_), do: []

    defp composite_pk_definition(%Table{}=table, columns) do
      pks = Enum.reduce(columns, [], fn({_, name, _, opts}, pk_acc) ->
        case Keyword.get(opts, :primary_key, false) do
          true -> [name|pk_acc]
          false -> pk_acc
        end
      end)
      if length(pks)>1 do
        composite_pk_expr = pks |> Enum.reverse |> Enum.map_join(", ", &quote_name/1)
        {%{table | primary_key: :composite}, ", PRIMARY KEY (" <> composite_pk_expr <> ")"}
      else
        {table, ""}
      end
    end

    defp null_expr(false), do: "NOT NULL"
    # defp null_expr(true), do: "NULL"  # SQLite does not allow this syntax.
    defp null_expr(_), do: []

    defp default_expr({:ok, nil}, _type),
      do: "DEFAULT NULL"
    defp default_expr({:ok, true}, _type),
      do: "DEFAULT 1"
    defp default_expr({:ok, false}, _type),
      do: "DEFAULT 0"
    defp default_expr({:ok, literal}, _type) when is_binary(literal),
      do: "DEFAULT '#{escape_string(literal)}'"
    defp default_expr({:ok, literal}, _type) when is_number(literal) or is_boolean(literal),
      do: "DEFAULT #{literal}"
    defp default_expr({:ok, {:fragment, expr}}, _type),
      do: "DEFAULT (#{expr})"
    defp default_expr({:ok, expr}, type),
      do: raise(ArgumentError, "unknown default `#{inspect expr}` for type `#{inspect type}`. " <>
                               ":default may be a string, number, boolean, empty list or a fragment(...)")
    defp default_expr(:error, _),
      do: []

    defp index_expr(literal) when is_binary(literal),
      do: literal
    defp index_expr(literal),
      do: quote_name(literal)

    defp options_expr(nil),
      do: ""
    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in :options")
    defp options_expr(options),
      do: " #{options}"

    # Simple column types. Note that we ignore options like :size, :precision,
    # etc. because columns do not have types, and SQLite will not coerce any
    # stored value. Thus, "strings" are all text and "numerics" have arbitrary
    # precision regardless of the declared column type. Decimals are the
    # only exception.
    defp column_type(:serial, _opts), do: "INTEGER"
    defp column_type(:string, _opts), do: "TEXT"
    defp column_type(:map, _opts), do: "TEXT"
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
      do: "CONSTRAINT #{reference_name(ref, table, name)} REFERENCES " <>
          "#{quote_table(table.prefix, ref.table)}(#{quote_name(ref.column)})" <>
          reference_on_delete(ref.on_delete)

    # A reference pointing to a serial column becomes integer in SQLite
    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")
    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "INTEGER"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    # Define how to handle deletion of foreign keys on parent table.
    # See: https://www.sqlite.org/foreignkeys.html#fk_actions
    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(_), do: ""

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

    def assemble([]), do: ""
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

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    # Not sure if this will be valid in SQLite.
    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end

    defp error!(nil, message) do
      raise ArgumentError, message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end

    # Use Ecto's JSON library (currently Poison) for embedded JSON datatypes.
    defp json_library, do: Application.get_env(:ecto, :json_library)
  end
end
