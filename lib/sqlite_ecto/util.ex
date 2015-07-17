defmodule Sqlite.Ecto.Util do
  @moduledoc "Common utilties used by multiple Sqlite.Ecto modules."

  # Execute a SQL query.
  def exec(pid, sql) do
    case Sqlitex.Server.exec(pid, sql) do
      # busy error means another process is writing to the database; try again
      {:error, {:busy, _}} -> exec(pid, sql)
      res -> res
    end
  end

  # Generate a random string.
  def random_id, do: :random.uniform |> Float.to_string |> String.slice(2..10)

  # Quote the given identifier.
  def quote_id({nil, id}), do: quote_id(id)
  def quote_id({prefix, table}), do: quote_id(prefix) <> "." <> quote_id(table)
  def quote_id(id) when is_atom(id), do: id |> Atom.to_string |> quote_id
  def quote_id(id) do
    if String.contains?(id, "\"") || String.contains?(id, ",") do
      raise ArgumentError, "bad identifier #{inspect id}"
    end
    "\"#{id}\""
  end

  # Assemble a list of items into a single string.
  def assemble(list) when is_list(list) do
    list = for x <- List.flatten(list), x != nil, do: x
    Enum.reduce list, fn word, result ->
        if word == "," || word == ")" || String.ends_with?(result, "(") do
          Enum.join([result, word])
        else
          Enum.join([result, word], " ")
        end
    end
  end
  def assemble(literal), do: literal

  # Take a list of items, apply a map, then intersperse the result with
  # another item.  Most often used for generating comma-separated fields to
  # assemble.
  def map_intersperse(list, item, func) when is_function(func, 1) do
    list |> Enum.map(&func.(&1)) |> Enum.intersperse(item)
  end
end
