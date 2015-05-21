defmodule Sqlite.Ecto.Transaction do
  @moduledoc false

  import Sqlite.Ecto.Util, only: [exec: 2, random_id: 0]

  def begin_transaction, do: "BEGIN"

  def rollback, do: "ROLLBACK"

  def commit, do: "COMMIT"

  def savepoint(name), do: "SAVEPOINT " <> name

  def rollback_to_savepoint(name), do: "ROLLBACK TO " <> name

  def release_savepoint(name), do: "RELEASE " <> name

  # Initiate a transaction with a savepoint.  If any error occurs when we call
  # the func parameter, rollback our changes.  Returns the result of the call
  # to func.
  def with_savepoint(pid, func) do
    sp = "sp_" <> random_id
    :ok = exec(pid, savepoint(sp))
    result = safe_call(pid, func, sp)
    if is_tuple(result) and elem(result, 0) == :error do
      :ok = exec(pid, rollback_to_savepoint(sp))
    end
    :ok = exec(pid, release_savepoint(sp))
    result
  end

  ## Helpers

  # Call func.() and return the result.  If any exceptions are encountered,
  # safely rollback and release the transaction.
  defp safe_call(pid, func, sp) do
    try do
      func.()
    rescue
      e in RuntimeError ->
        :ok = exec(pid, rollback_to_savepoint(sp))
        :ok = exec(pid, release_savepoint(sp))
        raise e
    end
  end
end
