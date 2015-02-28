defmodule Sqlite.Ecto do
  @moduledoc """
  TODO
  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL, :sqlitex

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage

  ## Storage API

  @doc false
  def storage_up(opts) do
    database = get_name(opts)
    cond do
      inmemory?(database) -> :ok
      File.exists?(database) -> {:error, :already_up}
      true ->
        case Sqlitex.open(database) do
          {:ok, _} -> :ok
          {:error, _msg} = err -> err
        end
    end
  end

  @doc false
  def storage_down(opts) do
    database = get_name(opts)
    if inmemory?(database) do
      :ok
    else
      case File.rm(database) do
        {:error, :enoent} -> {:error, :already_down}
        result -> result
      end
    end
  end

  def get_name(opts) do
    opts |> Keyword.get(:database, "") |> String.to_char_list
  end

  defp inmemory?(name) do
    name in ['', ':memory:', 'file::memory:']
  end

  @doc false
  def supports_ddl_transaction?, do: true
end
