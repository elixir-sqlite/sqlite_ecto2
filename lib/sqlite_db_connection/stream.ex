defmodule Sqlite.DbConnection.Stream do
  @moduledoc false
  defstruct [:conn, :query, :params, :options, max_rows: 500]
  @type t :: %Sqlite.DbConnection.Stream{}
end

defimpl Enumerable, for: Sqlite.DbConnection.Stream do
  alias Sqlite.DbConnection.Query

  def reduce(%Sqlite.DbConnection.Stream{query: statement,
                                         conn: conn,
                                         params: params,
                                         options: opts}, acc, fun)
  when is_binary(statement)
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

  def slice(_) do
    {:error, __MODULE__}
  end
end
