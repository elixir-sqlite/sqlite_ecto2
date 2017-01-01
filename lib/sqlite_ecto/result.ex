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
    columns: [String.t] | nil,
    rows: [[term]] | nil,
    num_rows: integer,
    decoder: :deferred | :done
  }

  defstruct [rows: nil, columns: nil, num_rows: nil, decoder: :done]

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

  def decode(%__MODULE__{rows: rows} = res, mapper) do
    rows = do_decode(rows, mapper)
    %__MODULE__{res | rows: rows, decoder: :done}
  end

  defp do_decode(nil, _mapper), do: nil

  defp do_decode(rows, nil), do: rows

  defp do_decode(rows, mapper) do
    rows
    |> Enum.map(fn row ->
      row
      |> cast_undefined
      # |> cast_any_datetimes
      # |> Keyword.values
      |> Enum.map(fn
        {:blob, binary} -> binary
        other -> other
      end)
    end)
    |> Enum.map(mapper)
  end

  defp cast_undefined(row) do
    row |> Enum.map(&undefined_to_nil/1)
  end

  defp undefined_to_nil(:undefined), do: nil
  defp undefined_to_nil(other), do: other

  # HACK: We have to do a special conversion if the user is trying to cast to
  # a DATETIME type.  Sqlitex cannot determine that the type of the cast is a
  # datetime value because datetime defaults to an integer type in SQLite.
  # Thus, we cast the value to a TEXT_DATETIME pseudo-type to preserve the
  # datetime string.  Then when we get here, we convert the string to an Ecto
  # datetime tuple if it looks like a cast was attempted.
  defp cast_any_datetimes(row) do
    Enum.map row, fn {key, value} ->
      str = Atom.to_string(key)
      if String.contains?(str, "CAST (") && String.contains?(str, "TEXT_DATE") do
        {key, string_to_datetime(value)}
      else
        {key, value}
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
