defmodule Sqlite.DbConnection.App do
  @moduledoc false
  use Application
  
  @registry Sqlite.DbConnection.Registry

  def start(_, _) do
    children = [
      {Registry, keys: :duplicate, name: @registry, partitions: System.schedulers_online()}
    ]
    opts = [strategy: :one_for_one, name: Sqlite.DbConnection.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
