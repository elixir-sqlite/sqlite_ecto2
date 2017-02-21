  defmodule Sqlite.Ecto do
  @moduledoc ~S"""
  Ecto Adapter module for SQLite.

  It uses Sqlitex and Esqlite for accessing the SQLite database.

  ## Features

  ## Options

  There are a limited number of options available because SQLite is so simple to use.

  ### Compile time options

  These options should be set in the config file and require recompilation in
  order to make an effect.

    * `:adapter` - The adapter name, in this case, `Sqlite.Ecto`
    * `:timeout` - The default timeout to use on queries, defaults to `5000`

  ### Connection options

    * `:database` - This option can take the form of a path to the SQLite
      database file or `":memory:"` for an in-memory database.  See the
      [SQLite docs](https://sqlite.org/uri.html) for more options such as
      shared memory caches.
    * `:after_connect` - A `{mod, fun, args}` to be invoked after a connection is established

  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL, :sqlitex

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage

  ## Custom SQLite Types

  def loaders(:map, type), do: [&json_decode/1, type]
  def loaders(:boolean, type), do: [&bool_decode/1, type]
  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders({:embed, _} = type, _),
    do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders(_primitive, type), do: [type]

  defp bool_decode(0), do: {:ok, false}
  defp bool_decode(1), do: {:ok, true}
  defp bool_decode(x), do: {:ok, x}

  defp json_decode(x) when is_binary(x),
    do: {:ok, Application.get_env(:ecto, :json_library).decode!(x)}
  defp json_decode(x),
    do: {:ok, x}

  ## Storage API

  @doc false
  def storage_up(opts) do
    database = Keyword.get(opts, :database)
    if File.exists?(database) do
      {:error, :already_up}
    else
      database |> Path.dirname |> File.mkdir_p!
      {:ok, db} = Sqlitex.open(database)
      Sqlitex.close(db)
      :ok
    end
  end

  @doc false
  def storage_down(opts) do
    database = Keyword.get(opts, :database)
    case File.rm(database) do
      {:error, :enoent} -> {:error, :already_down}
      result -> result
    end
  end

  @doc false
  def supports_ddl_transaction?, do: true
end
