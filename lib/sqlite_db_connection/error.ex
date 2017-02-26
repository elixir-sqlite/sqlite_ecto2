defmodule Sqlite.DbConnection.Error do
  defexception [:message, :sqlite, :connection_id]
end
