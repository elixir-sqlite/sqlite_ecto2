defmodule Sqlite.DbConnection.RegistryWorker do
  @moduledoc false

  use GenServer
  @registry Sqlite.DbConnection.Registry

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(opts) do 
    {:ok, opts}
  end
  
  def handle_info({action, table, rowid}, state) do
    Registry.dispatch(@registry, "notifications", fn entries ->
      for {pid, _} <- entries, do: send(pid, {action, to_string(table), rowid})
    end)
    {:noreply, state}
  end
end