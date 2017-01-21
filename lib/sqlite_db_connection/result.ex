defmodule Sqlite.DbConnection.Result do
  @moduledoc """
  Result struct returned from any successful query. Its fields are:

    * `command` - An atom of the query command, for example: `:select` or
                  `:insert`;
    * `columns` - The column names;
    * `rows` - The result set. A list of tuples, each tuple corresponding to a
               row, each element in the tuple corresponds to a column;
    * `num_rows` - The number of fetched or affected rows;
  """

  # IMPORTANT: This is closely modeled on Postgrex's result.ex file.
  # We strive to avoid structural differences between that file and this one.

  @type t :: %__MODULE__{
    command:  atom,
    columns:  [String.t] | nil,
    rows:     [[term] | term] | nil,
    num_rows: integer}

  defstruct [command: nil, columns: nil, rows: nil, num_rows: nil]
end
