defmodule Sqlite.Ecto.Error do
  defexception [:message, :sqlite]

  def message(%__MODULE__{sqlite: {type, msg}}), do: "#{type}: #{msg}"
  def message(%__MODULE__{sqlite: msg}), do: "UNKNOWN: #{inspect msg}"
  def message(%__MODULE__{message: msg}), do: msg

  def exception({type, msg}), do: %__MODULE__{sqlite: {type, to_string(msg)}}
  def exception(msg), do: %__MODULE__{sqlite: msg}

  def to_constraints(%__MODULE__{sqlite: {:constraint, "UNIQUE constraint failed: " <> id}}) do
    [unique: id]
  end
  def to_constraints(%__MODULE__{} = error), do: (error |> inspect |> IO.puts; [])
end
