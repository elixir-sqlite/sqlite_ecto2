defmodule Sqlite.DbConnection.Query do
  @moduledoc """
  Query struct returned from a successfully prepared query. Its fields are:

    * `name` - The name of the prepared statement;
    * `statement` - The prepared statement;
    * `param_formats` - List of formats for each parameters encoded to;
    * `encoders` - List of anonymous functions to encode each parameter;
    * `columns` - The column names;
    * `result_formats` - List of formats for each column is decoded from;
    * `decoders` - List of anonymous functions to decode each column;
    * `types` - The type serber table to fetch the type information from;
  """

  # IMPORTANT: This is closely modeled on Postgrex's query.ex file.
  # We strive to avoid structural differences between that file and this one.

  @type t :: %__MODULE__{
    name:           iodata,
    statement:      iodata,
    prepared:       reference,
    param_formats:  [:binary | :text] | nil,
    encoders:       [Sqlite.DbConnection.Types.oid] | [(term -> iodata)] | nil,
    columns:        [String.t] | nil,
    result_formats: [:binary | :text] | nil,
    decoders:       [Sqlite.DbConnection.Types.oid] | [(binary -> term)] | nil,
    types:          Sqlite.DbConnection.TypeServer.table | nil}

  defstruct [:name, :statement, :prepared, :param_formats, :encoders, :columns,
    :result_formats, :decoders, :types]
end

defimpl DBConnection.Query, for: Sqlite.DbConnection.Query do

  # import Sqlite.DbConnection.BinaryUtils

  def parse(query, _), do: query

  def describe(query, _) do
    %Sqlite.DbConnection.Query{encoders: poids, decoders: roids, types: types} = query
    {pfs, encoders} = encoders(poids, types)
    {rfs, decoders} = decoders(roids, types)
    %Sqlite.DbConnection.Query{query | param_formats: pfs, encoders: encoders,
                               result_formats: rfs, decoders: decoders}
  end

  def encode(%Sqlite.DbConnection.Query{encoders: nil}, params, opts) do
    encode_params(opts[:encode_mapper], params)
  end

  def decode(_query, %Sqlite.DbConnection.Result{rows: nil} = res, _opts), do: res

  def decode(%Sqlite.DbConnection.Query{decoders: nil, prepared: %{types: types}},
             %Sqlite.DbConnection.Result{rows: rows, columns: columns} = res,
             opts)
  do
    mapper = opts[:decode_mapper]
    decoded_rows = Enum.map(rows, &(decode_row(&1, types, columns, mapper)))
    %{res | rows: decoded_rows}
  end

  ## helpers

  defp encoders(nil, _types), do: {[], nil}
  defp decoders(nil, _), do: {[], nil}

  defp encode_params(nil, params), do: params
  defp encode_params(encode_mapper, params), do: Enum.map(params, encode_mapper)

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

  # datetime format is "YYYY-MM-DD HH:MM:SS.FFFFFF"
  defp translate_value({datetime, "datetime"}) when is_binary(datetime) do
    [date, time] = String.split(datetime)
    {to_date(date), to_time(time)}
  end

  defp translate_value({0, "boolean"}), do: false
  defp translate_value({1, "boolean"}), do: true

  defp translate_value({int, type=<<"decimal", _::binary>>}) when is_integer(int) do
    {result, _} = int |> Integer.to_string |> Float.parse
    translate_value({result, type})
  end
  defp translate_value({float, "decimal"}), do: Decimal.new(float)
  defp translate_value({float, "decimal(" <> rest}) do
    [precision, scale] =
      rest
      |> String.rstrip(?))
      |> String.split(",")
      |> Enum.map(&String.to_integer/1)

    Decimal.with_context(%Decimal.Context{precision: precision, rounding: :down},
      fn ->
        float |> Float.round(scale) |> Decimal.new |> Decimal.plus
      end)
  end

  defp translate_value({binary, :blob}), do: binary
  defp translate_value({value, _type}), do: value

  defp to_date(date) do
    <<yr::binary-size(4), "-", mo::binary-size(2), "-", da::binary-size(2)>> = date
    {String.to_integer(yr), String.to_integer(mo), String.to_integer(da)}
  end

  defp to_time(<<hr::binary-size(2), ":", mi::binary-size(2)>>) do
    {String.to_integer(hr), String.to_integer(mi), 0, 0}
  end
  defp to_time(<<hr::binary-size(2), ":", mi::binary-size(2), ":", se::binary-size(2)>>) do
    {String.to_integer(hr), String.to_integer(mi), String.to_integer(se), 0}
  end
  defp to_time(<<hr::binary-size(2), ":", mi::binary-size(2), ":", se::binary-size(2), ".", fr::binary>>) when byte_size(fr) <= 6 do
    fr = String.to_integer(fr <> String.duplicate("0", 6 - String.length(fr)))
    {String.to_integer(hr), String.to_integer(mi), String.to_integer(se), fr}
  end

  # HACK: We have to do a special conversion if the user is trying to cast to
  # a DATETIME type.  Sqlitex cannot determine that the type of the cast is a
  # datetime value because datetime defaults to an integer type in SQLite.
  # Thus, we cast the value to a TEXT_DATETIME pseudo-type to preserve the
  # datetime string.  Then when we get here, we convert the string to an Ecto
  # datetime tuple if it looks like a cast was attempted.
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
    {{String.to_integer(yr), String.to_integer(mo), String.to_integer(da)},{String.to_integer(hr), String.to_integer(mi), String.to_integer(se), String.to_integer(fr)}}
  end
end

defimpl String.Chars, for: Sqlite.DbConnection.Query do
  def to_string(%Sqlite.DbConnection.Query{statement: statement}) do
    IO.iodata_to_binary(statement)
  end
end
