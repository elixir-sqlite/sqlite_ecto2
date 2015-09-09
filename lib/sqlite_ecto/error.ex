defmodule Sqlite.Ecto.Error do
  defexception [:message, :sqlite]

  def message(%__MODULE__{sqlite: {type, msg}}), do: "#{type}: #{msg}"
  def message(%__MODULE__{sqlite: msg}), do: "UNKNOWN: #{inspect msg}"
  def message(%__MODULE__{message: msg}), do: msg

  def exception({type, msg}), do: %__MODULE__{sqlite: {type, to_string(msg)}}
  def exception(msg), do: %__MODULE__{sqlite: msg}

  require Logger

  def to_constraints(%__MODULE__{sqlite: {:constraint, "UNIQUE constraint failed: " <> _}}) do
    Logger.warn "unique_constraint/3 is unsupported by SQLite"
    []
  end
  def to_constraints(%__MODULE__{sqlite: {:constraint, "FOREIGN KEY constraint failed"}}) do
    Logger.warn "foreign_key_constraint/3 is unsupported by SQLite"
    []
  end
  def to_constraints(_), do: []
end
