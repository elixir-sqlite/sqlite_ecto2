defmodule Sqlite.DbConnection.Query do
  @moduledoc """
  Query struct returned from a successfully prepared query.

  Its public fields are:

    * `name` - The name of the prepared statement;
    * `statement` - The prepared statement;
    * `columns` - The column names;
  """

  # IMPORTANT: This is closely modeled on Postgrex's query.ex file.
  # We strive to avoid structural differences between that file and this one.

  @type t :: %__MODULE__{
    name:           iodata,
    statement:      iodata,
    prepared:       reference,
    columns:        [String.t] | nil,
    result_formats: [:binary | :text] | nil,
    types:          Sqlite.DbConnection.TypeServer.table | nil}

  defstruct [:name, :statement, :prepared, :columns, :result_formats, :types]
end

defimpl DBConnection.Query, for: Sqlite.DbConnection.Query do
  def parse(%{name: name} = query, _) do
    # for query table to match names must be equal
    %{query | name: IO.iodata_to_binary(name)}
  end

  def describe(query, _), do: query

  def encode(_query, params, _opts), do: params

  def decode(_query, %Sqlite.DbConnection.Result{rows: nil} = res, _opts), do: res

  def decode(%Sqlite.DbConnection.Query{prepared: %{types: types}},
             %Sqlite.DbConnection.Result{rows: rows, columns: columns} = res,
             opts)
  do
    mapper = opts[:decode_mapper]
    decoded_rows = Enum.map(rows, &(decode_row(&1, types, columns, mapper)))
    %{res | rows: decoded_rows}
  end

  ## Helpers

  defp decode_row(row, types, column_names, nil) do
    row
    |> Enum.zip(types)
    |> Enum.map(&translate_value/1)
    |> Enum.zip(column_names)
    |> cast_any_datetimes
  end
  defp decode_row(row, types, column_names, mapper) do
    mapper.(decode_row(row, types, column_names, nil))
  end

  defp translate_value({:undefined, _type}), do: nil
  defp translate_value({{:blob, blob}, _type}), do: blob

  defp translate_value({"", "date"}), do: nil
  defp translate_value({date, "date"}) when is_binary(date), do: to_date(date)

  defp translate_value({"", "time"}), do: nil
  defp translate_value({time, "time"}) when is_binary(time), do: to_time(time)

  defp translate_value({"", "datetime"}), do: nil

  defp translate_value({0, "boolean"}), do: false
  defp translate_value({1, "boolean"}), do: true

  defp translate_value({int, type = <<"decimal", _ :: binary>>}) when is_integer(int) do
    {result, _} = int |> Integer.to_string |> Float.parse
    translate_value({result, type})
  end
  defp translate_value({float, "decimal"}), do: Decimal.new(float)
  defp translate_value({float, "decimal(" <> rest}) do
    [precision, scale] =
      rest
      |> String.trim_trailing(")")
      |> String.split(",")
      |> Enum.map(&String.to_integer/1)

    Decimal.with_context(%Decimal.Context{precision: precision, rounding: :down},
      fn ->
        float |> Float.round(scale) |> Decimal.new |> Decimal.plus
      end)
  end

  defp translate_value({value, _type}), do: value

  defp to_date(date) do
    <<yr::binary-size(4), "-", mo::binary-size(2), "-", da::binary-size(2)>> = date
    {String.to_integer(yr), String.to_integer(mo), String.to_integer(da)}
  end

  defp to_time(<<hr::binary-size(2), ":", mi::binary-size(2), ":", se::binary-size(2), ".", fr::binary>>) when byte_size(fr) <= 6 do
    fr = String.to_integer(fr <> String.duplicate("0", 6 - String.length(fr)))
    {String.to_integer(hr), String.to_integer(mi), String.to_integer(se), fr}
  end

  # We use a special conversion for when the user is trying to cast to a
  # DATETIME type. We introduce a TEXT_DATETIME psudo-type to preserve the
  # datetime string. When we get here, we look for a CAST function as a signal
  # to convert that back to Elixir date types.
  defp cast_any_datetimes(row) do
    Enum.map row, fn {value, column_name} ->
      if String.contains?(column_name, "CAST (") && String.contains?(column_name, "TEXT_DATE") do
        string_to_datetime(value)
      else
        value
      end
    end
  end

  defp string_to_datetime(<<yr::binary-size(4), "-", mo::binary-size(2), "-", da::binary-size(2)>>) do
    {String.to_integer(yr), String.to_integer(mo), String.to_integer(da)}
  end
  defp string_to_datetime(str) do
    <<yr::binary-size(4), "-", mo::binary-size(2), "-", da::binary-size(2), " ", hr::binary-size(2), ":", mi::binary-size(2), ":", se::binary-size(2), ".", fr::binary-size(6)>> = str
    {{String.to_integer(yr), String.to_integer(mo), String.to_integer(da)}, {String.to_integer(hr), String.to_integer(mi), String.to_integer(se), String.to_integer(fr)}}
  end
end

defimpl String.Chars, for: Sqlite.DbConnection.Query do
  def to_string(%Sqlite.DbConnection.Query{statement: statement}) do
    IO.iodata_to_binary(statement)
  end
end
