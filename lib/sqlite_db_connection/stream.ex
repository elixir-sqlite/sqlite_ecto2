defmodule Sqlite.DbConnection.Stream do
  @moduledoc false
  defstruct [:conn, :query, :params, :options, max_rows: 500]
  @type t :: %Sqlite.DbConnection.Stream{}
end

defimpl Enumerable, for: Sqlite.DbConnection.Stream do
  alias Sqlite.DbConnection.Query

  def reduce(%Sqlite.DbConnection.Stream{query: %Query{} = _query}, _acc, _fun) do
    raise "UNIMPLEMENTED"
  end
  def reduce(%Sqlite.DbConnection.Stream{query: statement,
                                         conn: conn,
                                         params: params,
                                         options: opts}, acc, fun)
  do
    query = %Query{name: "", statement: statement}
    case DBConnection.prepare_execute(conn, query, params, opts) do
      {:ok, _, %{rows: _rows} = result} ->
        Enumerable.reduce([result], acc, fun)
      {:error, err} ->
        raise err
    end
  end

  def member?(_, _) do
    {:error, __MODULE__}
  end

  def count(_) do
    {:error, __MODULE__}
  end
end

defimpl String.Chars, for: Sqlite.DbConnection.Stream do
  def to_string(%Sqlite.DbConnection.Stream{query: query}) do
    String.Chars.to_string(query)
  end
end
