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
    if File.exists?(database) do
      {:error, :already_up}
    else
      case Sqlitex.open(database) do
        {:ok, _} -> :ok
        {:error, _msg} = err -> err
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

  def get_name(opts) do
    opts |> Keyword.get(:database) |> String.to_char_list
  end

  @doc false
  def supports_ddl_transaction?, do: true
end
