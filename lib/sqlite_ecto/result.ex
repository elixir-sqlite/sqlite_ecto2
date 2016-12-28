defmodule Sqlite.Ecto.Result do
  @moduledoc """
  Result struct returned from any successful query. Its fields are:

    * `command` - An atom of the query command, for example: `:select` or
                   `:insert` (TODO: not yet implemented);
    * `columns` - The column names (TODO: not yet implemented);
    * `rows` - The result set. A list of lists, each inner list corresponding to a
                row, each element in the list corresponds to a column;
    * `num_rows` - The number of fetched or affected rows;
  """

  @type t :: %__MODULE__{
    # command: atom,
    # columns: [String.t] | nil,
    rows: [[term]] | nil,
    num_rows: integer
  }

  defstruct [:rows, :num_rows]
end
