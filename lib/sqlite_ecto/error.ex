defmodule Sqlite.Ecto.Error do
  defexception [:message, :sqlite]

  def message(%__MODULE__{sqlite: {type, msg}}), do: "#{type}: #{msg}"
  def message(%__MODULE__{sqlite: msg}), do: "UNKNOWN: #{inspect msg}"
  def message(%__MODULE__{message: msg}), do: msg

  def exception(msg), do: %__MODULE__{sqlite: msg}
end
