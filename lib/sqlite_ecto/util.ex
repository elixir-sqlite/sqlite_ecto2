defmodule Sqlite.Ecto.Util do
  "Common utilties used by many Sqlite.Ecto modules."

  # Execute a SQL query.
  def exec(pid, sql) do
    case Sqlitex.Server.exec(pid, sql) do
      # busy error means another process is writing to the database; try again
      {:error, {:busy, _}} -> exec(pid, sql)
      res -> res
    end
  end

  # Generate a random string.
  # FIXME Is there a better way to do this?
  def random_id, do: :random.uniform |> Float.to_string |> String.slice(2..10)

  # Quote the given identifier.
  def quote_id(id), do: "\"#{id}\""
end
