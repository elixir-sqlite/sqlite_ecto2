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

  import String, only: [to_integer: 1]

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage

  ## Custom SQLite Types

  def loaders(:boolean, type), do: [&bool_decode/1, type]
  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders(:utc_datetime, type), do: [&date_decode/1, type]
  def loaders(:naive_datetime, type), do: [&date_decode/1, type]
  def loaders({:embed, _} = type, _),
    do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders(:map, type), do: [&json_decode/1, type]
  def loaders({:map, _}, type), do: [&json_decode/1, type]
  def loaders(_primitive, type), do: [type]

  defp bool_decode(0), do: {:ok, false}
  defp bool_decode(1), do: {:ok, true}
  defp bool_decode(x), do: {:ok, x}

  defp date_decode(<<year :: binary-size(4), "-",
                     month :: binary-size(2), "-",
                     day :: binary-size(2)>>)
  do
    {:ok, {to_integer(year), to_integer(month), to_integer(day)}}
  end
  defp date_decode(<<year :: binary-size(4), "-",
                     month :: binary-size(2), "-",
                     day :: binary-size(2), " ",
                     hour :: binary-size(2), ":",
                     minute :: binary-size(2), ":",
                     second :: binary-size(2), ".",
                     microsecond :: binary-size(6)>>)
  do
    {:ok, {{to_integer(year), to_integer(month), to_integer(day)},
           {to_integer(hour), to_integer(minute), to_integer(second), to_integer(microsecond)}}}
  end
  defp date_decode(x), do: {:ok, x}

  defp json_decode(x) when is_binary(x),
    do: {:ok, Application.get_env(:ecto, :json_library).decode!(x)}
  defp json_decode(x),
    do: {:ok, x}

  def dumpers(:binary, type), do: [type, &blob_encode/1]
  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(:boolean, type), do: [type, &bool_encode/1]
  def dumpers({:embed, _} = type, _), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers(_primitive, type), do: [type]

  defp blob_encode(value), do: {:ok, {:blob, value}}

  defp bool_encode(false), do: {:ok, 0}
  defp bool_encode(true), do: {:ok, 1}

  ## Storage API

  @doc false
  def storage_up(opts) do
    database = Keyword.get(opts, :database)
    if File.exists?(database) do
      {:error, :already_up}
    else
      database |> Path.dirname |> File.mkdir_p!
      {:ok, db} = Sqlitex.open(database)
      :ok = Sqlitex.exec(db, "PRAGMA journal_mode = WAL")
      {:ok, [[journal_mode: "wal"]]} = Sqlitex.query(db, "PRAGMA journal_mode")
      Sqlitex.close(db)
      :ok
    end
  end

  @doc false
  def storage_down(opts) do
    database = Keyword.get(opts, :database)
    case File.rm(database) do
      {:error, :enoent} ->
        {:error, :already_down}
      result ->
        File.rm(database <> "-shm") # ignore results for these files
        File.rm(database <> "-wal")
        result
    end
  end

  @doc false
  def supports_ddl_transaction?, do: true
end
