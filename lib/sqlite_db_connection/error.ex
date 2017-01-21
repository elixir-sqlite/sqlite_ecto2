defmodule Sqlite.DbConnection.Error do
  defexception [:message, :sqlite, :postgres]
end
