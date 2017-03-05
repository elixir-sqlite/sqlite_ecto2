defmodule Sqlite.DbConnection.App do
  @moduledoc false
  use Application

  def start(_, _) do
    opts = [strategy: :one_for_one, name: Sqlite.DbConnection.Supervisor]
    Supervisor.start_link([], opts)
  end
end
