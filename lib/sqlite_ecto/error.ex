defmodule Sqlite.Ecto.Error do
  defexception [:message, :sqlite]

  def message(%__MODULE__{sqlite: {type, msg}}), do: "#{type}: #{msg}"
  def message(%__MODULE__{sqlite: msg}), do: "UNKNOWN: #{inspect msg}"
  def message(%__MODULE__{message: msg}), do: msg

  # handle unique constraint failures
  def exception({:constraint, msg = 'UNIQUE constraint failed:' ++ _}) do
    msg = to_string(msg) <> "; unique_constraint/3 is unsupported by SQLite"
    %__MODULE__{sqlite: {:constraint, msg}}
  end
  # handle foreign key constraint failures
  def exception({:constraint, msg = 'FOREIGN KEY constraint failed'}) do
    msg = to_string(msg) <> "; foreign_key_constraint/3 is unsupported by SQLite"
    %__MODULE__{sqlite: {:constraint, msg}}
  end
  def exception({type, msg}), do: %__MODULE__{sqlite: {type, to_string(msg)}}
  def exception(msg), do: %__MODULE__{sqlite: msg}

  def to_constraints(_), do: []
end
