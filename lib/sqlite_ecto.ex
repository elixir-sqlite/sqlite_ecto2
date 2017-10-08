defmodule Sqlite.Ecto2 do
  @moduledoc ~S"""
  Ecto Adapter module for SQLite.

  It uses Sqlitex and Esqlite for accessing the SQLite database.

  ## Configuration Options

  When creating an `Ecto.Repo` that uses a SQLite database, you should configure
  it as follows:

  ```elixir
  # In your config/config.exs file
  config :my_app, Repo,
    adapter: Sqlite.Ecto2,
    database: "ecto_simple.sqlite3"

  # In your application code
  defmodule Repo do
    use Ecto.Repo,
      otp_app: :my_app,
      adapter: Sqlite.Ecto2
  end
  ```

  You may use other options as specified in the `Ecto.Repo` documentation.

  Note that the `:database` option is passed as the `filename` argument to
  [`sqlite3_open_v2`](http://sqlite.org/c3ref/open.html). This implies that you
  may use `:memory:` to create a private, temporary in-memory database.

  See also [SQLite's interpretation of URI "filenames"](https://sqlite.org/uri.html)
  for more options such as shared memory caches.
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
  def loaders(:float, type), do: [&float_decode/1, type]
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

  defp float_decode(x) when is_integer(x), do: {:ok, x / 1}
  defp float_decode(x), do: {:ok, x}

  def dumpers(:binary, type), do: [type, &blob_encode/1]
  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(:boolean, type), do: [type, &bool_encode/1]
  def dumpers({:embed, _} = type, _), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers(:time, type), do: [type, &time_encode/1]
  def dumpers(_primitive, type), do: [type]

  defp blob_encode(value), do: {:ok, {:blob, value}}

  defp bool_encode(false), do: {:ok, 0}
  defp bool_encode(true), do: {:ok, 1}

  defp time_encode(value) do
    {:ok, value}
  end

  ## Storage API

  @doc false
  def storage_up(opts) do
    storage_up_with_path(Keyword.get(opts, :database), opts)
  end

  defp storage_up_with_path(nil, opts) do
    raise ArgumentError,
      """
      No SQLite database path specified. Please check the configuration for your Repo.
      Your config/*.exs file should have something like this in it:

        config :my_app, MyApp.Repo,
          adapter: Sqlite.Ecto2,
          database: "/path/to/sqlite/database"

      Options provided were:

      #{inspect opts, pretty: true}

      """
  end

  defp storage_up_with_path(database, _opts) do
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
