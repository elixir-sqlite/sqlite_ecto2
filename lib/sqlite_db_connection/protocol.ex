defmodule Sqlite.DbConnection.Protocol do
  @moduledoc false

  # alias Sqlite.DbConnection.Types
  alias Sqlite.DbConnection.Query
  # import Sqlite.DbConnection.Messages
  # import Sqlite.DbConnection.BinaryUtils
  require Logger
  use DBConnection

  # IMPORTANT: This is closely modeled on Postgrex's protocol.ex file.
  # We strive to avoid structural differences between that file and this one.

  # @sock_opts [packet: :raw, mode: :binary, active: false]

  defstruct [db: nil, path: nil, checked_out?: false]

  @type state :: %__MODULE__{db: pid,
                             path: String.t,
                             checked_out?: false}

  @spec connect(Keyword.t) ::
    {:ok, state} | {:error, Sqlite.DbConnection.Error.t}
  def connect(opts) do
    {db_path, _opts} = Keyword.pop(opts, :database)
    with {:ok, db} <- Sqlitex.Server.start_link(db_path),
         :ok <- Sqlitex.Server.exec(db, "PRAGMA foreign_keys = ON"),
         {:ok, [[foreign_keys: 1]]} = Sqlitex.Server.query(db, "PRAGMA foreign_keys")
    do
      {:ok, %__MODULE__{db: db, path: db_path, checked_out?: false}}
    end
  end

  @spec disconnect(Exception.t, state) :: :ok
  def disconnect(_exc, %__MODULE__{db: db} = _state) when db != nil do
    GenServer.stop(db)
    :ok
  end
  def disconnect(_exception, _state), do: :ok

  @spec ping(state :: any) ::
    {:ok, new_state :: any} | {:disconnect, Exception.t, new_state :: any}
  def ping(state) do
    # No such thing with SQLite, so this is an intentional no-op.
    {:ok, state}
  end

  @spec checkout(state) ::
    {:ok, state} | {:disconnect, Sqlite.DbConnection.Error.t, state}
  # def checkout(%{checked_out?: true} = s), do:  # unreachable in tests; restore if hit
  #   {:disconnect, :already_checked_out, s}  # FIXME: Proper error here
  def checkout(%{checked_out?: false} = s), do:
    {:ok, %{s | checked_out?: true}}

  @spec checkin(state) ::
    {:ok, state} | {:disconnect, Sqlite.DbConnection.Error.t, state}
  # def checkin(%{checked_out?: false} = s), do:  # unreachable in tests; restore if hit
  #   {:disconnect, :not_checked_out, s}  # FIXME: Proper error here
  def checkin(%{checked_out?: true} = s), do:
    {:ok, %{s | checked_out?: false}}

  @spec handle_prepare(Sqlite.DbConnection.Query.t, Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Query.t, state} |
    {:error, ArgumentError.t, state}
  def handle_prepare(%Query{statement: statement, prepared: nil} = query, _opts,
                     %__MODULE__{checked_out?: true, db: db} = s)
  do
    binary_stmt = :erlang.iolist_to_binary(statement)
    case Sqlitex.Server.prepare(db, binary_stmt) do
      {:ok, prepared_info} ->
        updated_query = %{query | prepared: refined_info(prepared_info)}
        {:ok, updated_query, s}
      {:error, {_sqlite_errcode, _message}} = err ->
        sqlite_error(err, s)
    end
  end
  def handle_prepare(query, _opts, s) do
    query_error(s, "query #{inspect query} has already been prepared")
  end

  @spec handle_execute(Sqlite.DbConnection.Query.t, list, Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Result.t, state} |
    {:error, ArgumentError.t, state} |
    {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  def handle_execute(%Query{} = query, params, opts, s) do
    handle_execute(query, params, :sync, opts, s)
  end
  # @spec handle_execute(Sqlite.DbConnection.Parameters.t, nil, Keyword.t, state) ::
  #   {:ok, %{binary => binary}, state} |
  #   {:error, Sqlite.DbConnection.Errpr.t, state}
  # def handle_execute(%Sqlite.DbConnection.Parameters{}, nil, _, s) do
  #   %{parameters: parameters} = s
  #   case Sqlite.DbConnection.Parameters.fetch(parameters) do
  #     {:ok, parameters} ->
  #       {:ok, parameters, s}
  #     :error ->
  #       {:error, %Sqlite.DbConnection.Error{message: "parameters not available"}, s}
  #   end
  # end

  @spec handle_close(Sqlite.DbConnection.Query.t, Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Result.t, state} |
    {:error, ArgumentError.t, state} |
    {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  def handle_close(_query, _opts, s) do
    # no-op: esqlite doesn't expose statement close.
    # Instead it relies on statements getting garbage collected.
    res = %Sqlite.DbConnection.Result{command: :close}
    {:ok, res, s}
  end

  @spec handle_begin(Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Result.t, state} |
    {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  def handle_begin(opts, s) do
    sql = case Keyword.get(opts, :mode, :transaction) do
      :transaction -> "BEGIN"
      :savepoint   -> "SAVEPOINT sqlite_ecto_savepoint"
    end
    handle_transaction(sql, s)
  end

  @spec handle_commit(Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Result.t, state} |
    {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  def handle_commit(opts, s) do
    sql = case Keyword.get(opts, :mode, :transaction) do
      :transaction -> "COMMIT"
      :savepoint   -> "RELEASE SAVEPOINT sqlite_ecto_savepoint"
    end
    handle_transaction(sql, s)
  end

  @spec handle_rollback(Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Result.t, state} |
    {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  def handle_rollback(opts, s) do
    sql = case Keyword.get(opts, :mode, :transaction) do
      :transaction -> "ROLLBACK"
      :savepoint   -> "ROLLBACK TO SAVEPOINT sqlite_ecto_savepoint"
    end
    handle_transaction(sql, s)
  end

  # @spec handle_simple(String.t, Keyword.t, state) ::
  #   {:ok, Sqlite.DbConnection.Result.t, state} |
  #   {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  # def handle_simple(statement, opts, %{buffer: buffer} = s) do
  #   status = %{notify: notify(opts), sync: :sync}
  #   simple_send(%{s | buffer: nil}, status, statement, buffer)
  # end

  ## prepare

  defp refined_info(prepared_info) do
    types =
      prepared_info.types
      |> Enum.map(&maybe_atom_to_lc_string/1)
      |> Enum.to_list

    prepared_info
    |> Map.delete(:columns)
    |> Map.put(:column_names, atoms_to_strings(prepared_info.columns))
    |> Map.put(:types, types)
  end

  defp atoms_to_strings(nil), do: nil
  defp atoms_to_strings(list), do: Enum.map(list, &maybe_atom_to_string/1)

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(item), do: to_string(item)

  defp maybe_atom_to_lc_string(nil), do: nil
  defp maybe_atom_to_lc_string(item), do: item |> to_string |> String.downcase

  ## execute

  defp handle_execute(%Query{statement: sql}, params, _sync, _opts, s) do
    # Note that we rely on Sqlitex.Server to cache the prepared statement,
    # so we can simply refer to the original SQL statement here.
    case run_stmt(sql, params, s) do
      {:ok, result} ->
        {:ok, result, s}
      other ->
        other
    end
  end

  defp query_error(s, msg) do
    {:error, ArgumentError.exception(msg), s}
  end

  defp sqlite_error({:error, {sqlite_errcode, message}}, s) do
    {:error, %Sqlite.DbConnection.Error{sqlite: %{code: sqlite_errcode},
                                        message: to_string(message)}, s}
  end

  defp run_stmt(query, params, s) do
    opts = [decode: :manual, types: true, bind: params]
    command = command_from_sql(query)
    case query_rows(s.db, to_string(query), opts) do
      {:ok, %{rows: raw_rows, columns: raw_column_names}} ->
        {rows, num_rows, column_names} = case {raw_rows, raw_column_names} do
          {_, []} -> {nil, get_changes_count(s.db, command), nil}
          _ -> {raw_rows, length(raw_rows), raw_column_names}
        end
        {:ok, %Sqlite.DbConnection.Result{rows: rows,
                                          num_rows: num_rows,
                                          columns: atoms_to_strings(column_names),
                                          command: command}}
      {:error, {_sqlite_errcode, _message}} = err ->
        sqlite_error(err, s)
      {:error, :args_wrong_length} ->
        {:error,
         %ArgumentError{message: "parameters must match number of placeholders in query"},
         s}
    end
  end

  defp get_changes_count(db, command)
    when command in [:insert, :update, :delete]
  do
    # TODO: This statement should be cached.
    {:ok, %{rows: [[changes_count]]}} = Sqlitex.Server.query_rows(db, "SELECT changes()")
    changes_count
  end
  defp get_changes_count(_db, _command), do: 1

  defp command_from_sql(sql) do
    sql
    |> :erlang.iolist_to_binary
    |> String.downcase
    |> String.split(" ", parts: 3)
    |> command_from_words
  end

  defp command_from_words([verb, subject, _])
    when verb == "alter" or verb == "create" or verb == "drop",
  do: String.to_atom("#{verb}_#{subject}")

  defp command_from_words(words) when is_list(words), do:
    String.to_atom(List.first(words))

  # defp reserved_error(query, s) do
  #   err = ArgumentError.exception("query #{inspect query} uses reserved name")
  #   {:error, err, s}
  # end

  ## transaction

  defp handle_transaction(stmt, s) do
    {:ok, _rows} = query_rows(s.db, stmt, into: :raw_list)
    command = command_from_sql(stmt)
    result = %Sqlite.DbConnection.Result{rows: nil,
                                         num_rows: nil,
                                         columns: nil,
                                         command: command}
    {:ok, result, s}
  end

  defp query_rows(db, stmt, opts) do
    try do
      Sqlitex.Server.query_rows(db, stmt, opts)
    catch
      :exit, _ ->
        {:raise, %Sqlite.DbConnection.Error{message: "Disconnected"}}
    end
  end
end
