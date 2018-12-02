defmodule Sqlite.Ecto2.Notifications do
  use GenServer

  @registry Sqlite.DbConnection.Registry

  def start_link(args) do
    {server_opts, args} = Keyword.split(args, [:name])
    GenServer.start_link(__MODULE__, args, server_opts)
  end

  def init(args) do
    repo = Keyword.fetch!(args, :repo)
    schemas = Keyword.fetch!(args, :schemas)
    {:ok, _} = Registry.register(@registry, "notifications", [])
    {:ok, %{repo: repo, schemas: schemas}}
  end

  def handle_info({_, "schema_migrations", _}, state) do
    {:noreply, state}
  end

  def handle_info({_, "t_" <> _, _}, state) do
    {:noreply, state}
  end

  def handle_info({:delete, _table, _rowid}, state) do
    # What to do with delete?
    # can't lookup record since it's already deleted.
    {:noreply, state}
  end

  def handle_info({action, table, rowid}, state) do
    repo = state.repo
    %{columns: c, rows: [row]} = Ecto.Adapters.SQL.query!(repo, "SELECT * FROM '#{table}' where rowid = #{rowid};", [])
    state.schemas
    |> Enum.filter(fn({s_table, _schema}) -> s_table == table end)
    |> Enum.map(fn({^table, schema}) -> repo.load(schema, {c, row}) end)
    |> dispatch(state)
    {:noreply, state}
  end

  defp dispatch(message, _state) do
    IO.inspect(message, label: "message")
  end
end