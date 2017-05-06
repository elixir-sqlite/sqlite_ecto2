defmodule Sqlite.DbConnection.Error do
  @moduledoc false
  defexception [:message, :sqlite, :connection_id]
end
