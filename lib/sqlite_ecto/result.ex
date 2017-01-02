defmodule Sqlite.Ecto.Result do
  @moduledoc """
  Result struct returned from any successful query. Its fields are:

    * `command` - An atom of the query command, for example: `:select` or
                   `:insert` (TODO: not yet implemented);
    * `columns` - The column names;
    * `column_types` - The preferred type for each column;
    * `rows` - The result set. A list of lists, each inner list corresponding to a
                row, each element in the list corresponds to a column;
    * `num_rows` - The number of fetched or affected rows;
  """

  @type t :: %__MODULE__{
    # command: atom,
    columns: [String.t] | nil,
    column_types: [atom] | nil,
    rows: [[term]] | nil,
    num_rows: integer,
    decoder: :deferred | :done
  }

  defstruct [rows: nil,
             num_rows: nil,
             columns: nil,
             column_types: nil,
             decoder: :done]

  @doc """
  Decodes a result set.

  It is a no-op if the result was already decoded.

  A mapper function can be given to further process
  each row, in no specific order.
  """
  @spec decode(t, ([term] -> term)) :: t
  def decode(result_set, mapper \\ fn x -> x end)

  def decode({:ok, %__MODULE__{} = res}, mapper), do: {:ok, decode(res, mapper)}

  def decode(%__MODULE__{decoder: :done} = res, _mapper), do: res

  def decode(%__MODULE__{rows: rows, columns: columns, column_types: types} = res, mapper) do
    rows = do_decode(rows, columns, types, mapper)
    %__MODULE__{res | rows: rows, decoder: :done}
  end

  defp do_decode(nil, _column_names, _column_types, _mapper), do: nil

  defp do_decode(rows, column_names, column_types, mapper) do
    column_types = Enum.map(column_types, &downcase_atom/1)

    rows
    |> Enum.map(fn row ->
      row
      |> translate_row_values(column_names, column_types)
      |> Enum.map(fn
        {:blob, binary} -> binary
        other -> other
      end)
    end)
    |> do_rows_mapper(mapper)
  end

  defp downcase_atom(atom) do
    atom |> Atom.to_string |> String.downcase
  end

  defp translate_row_values(row, column_names, column_types) do
    row
    |> Enum.zip(column_types)
    |> Enum.map(&translate_value/1)
    |> Enum.zip(column_names)
    |> cast_any_datetimes
  end

  defp translate_value({:undefined, _type}), do: nil

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

  defp do_rows_mapper(rows, nil), do: rows
  defp do_rows_mapper(rows, mapper), do: Enum.map(rows, mapper)

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
      str = Atom.to_string(column_name)
      if String.contains?(str, "CAST (") && String.contains?(str, "TEXT_DATE") do
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
