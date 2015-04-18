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
      [SQLite docs](https://sqlite.org/uri.html) for more options.

  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL, :sqlitex

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage

  ## Storage API

  @doc false
  def storage_up(opts) do
    database = get_name(opts)
    if File.exists?(database) do
      {:error, :already_up}
    else
      case Sqlitex.open(database) do
        {:error, _msg} = err -> err
        {:ok, db} ->
          Sqlitex.close(db)
          :ok
      end
    end
  end

  @doc false
  def storage_down(opts) do
    database = get_name(opts)
    case File.rm(database) do
      {:error, :enoent} -> {:error, :already_down}
      result -> result
    end
  end

  @doc false
  def get_name(opts) do
    opts |> Keyword.get(:database) |> String.to_char_list
  end

  @doc false
  def supports_ddl_transaction?, do: true
end
