# IMPORTANT: This is closely modeled on Sqlite.DbConnection's test_helper.exs file
# (though note that it lacks the .exs extension).
# We strive to avoid structural differences between that file and this one.

defmodule Sqlite.DbConnection.TestHelper do
  defmacro query(stat, params, opts \\ []) do
    quote do
      case Sqlite.DbConnection.Connection.query(var!(context)[:pid], unquote(stat),
                                                unquote(params), unquote(opts)) do
        {:ok, %Sqlite.DbConnection.Result{rows: nil}} -> :ok
        {:ok, %Sqlite.DbConnection.Result{rows: rows}} -> rows
        {:error, %Sqlite.DbConnection.Error{} = err} -> err
      end
    end
  end

  defmacro prepare(name, stat, opts \\ []) do
    quote do
      case Sqlite.DbConnection.Connection.prepare(var!(context)[:pid], unquote(name),
                                                  unquote(stat), unquote(opts)) do
        {:ok, %Sqlite.DbConnection.Query{} = query} -> query
        {:error, %Sqlite.DbConnection.Error{} = err} -> err
      end
    end
  end

  defmacro execute(query, params, opts \\ []) do
    quote do
      case Sqlite.DbConnection.Connection.execute(var!(context)[:pid], unquote(query),
                                                  unquote(params), unquote(opts)) do
        {:ok, %Sqlite.DbConnection.Result{rows: nil}} -> :ok
        {:ok, %Sqlite.DbConnection.Result{rows: rows}} -> rows
        {:error, %Sqlite.DbConnection.Error{} = err} -> err
      end
    end
  end

  defmacro close(query, opts \\ []) do
    quote do
      case Sqlite.DbConnection.Connection.close(var!(context)[:pid], unquote(query),
                                                unquote(opts)) do
        :ok -> :ok
        {:error, %Sqlite.DbConnection.Error{} = err} -> err
      end
    end
  end
end
