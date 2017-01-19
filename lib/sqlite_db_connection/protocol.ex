defmodule Sqlite.DbConnection.Protocol do
  @moduledoc false

  # alias Sqlite.DbConnection.Types
  alias Sqlite.DbConnection.Query
  # import Sqlite.DbConnection.Messages
  # import Sqlite.DbConnection.BinaryUtils
  require Logger

  # IMPORTANT: This is closely modeled on Postgrex's protocol.ex file.
  # We strive to avoid structural differences between that file and this one.

  # @sock_opts [packet: :raw, mode: :binary, active: false]

  defstruct [db: nil, path: nil, checked_out?: false]

  @type state :: %__MODULE__{db: Sqlitex.Connection,
                             path: String.t,
                             checked_out?: false}

  @reserved_prefix "Sqlite.DbConnection_"
  # @reserved_queries ["BEGIN", "COMMIT", "ROLLBACK"]

  @spec connect(Keyword.t) ::
    {:ok, state} | {:error, Sqlite.DbConnection.Error.t}
  def connect(opts) do
    {db_path, _opts} = Keyword.pop(opts, :database)
    with {:ok, db} <- Sqlitex.open(db_path),
         :ok <- Sqlitex.exec(db, "PRAGMA foreign_keys = ON"),
         {:ok, [[foreign_keys: 1]]} = Sqlitex.query(db, "PRAGMA foreign_keys")
    do
      s = %__MODULE__{db: db, path: db_path, checked_out?: false}
      {:ok, s}
    else
      {:error, _reason} = error -> error
    end
  end

  # @spec disconnect(Exception.t, state) :: :ok
  # def disconnect(err, %{types: ref}) when is_reference(ref) do
  #   # Don't handle the case where connection failure occurs during bootstrap
  #   # (hard to test and "unlikely" given auth just succeeded)
  #   raise err
  # end
  # def disconnect(_, s) do
  #   sock_close(s)
  #   _ = recv_buffer(s)
  #   delete_parameters(s)
  #   :ok
  # end
  #
  # @spec ping(state) ::
  #   {:ok, state} | {:disconnect, Sqlite.DbConnection.Error.t, state}
  # def ping(%{buffer: buffer} = s) do
  #   status = %{notify: notify([]), sync: :sync}
  #   sync(%{s | buffer: nil}, status, buffer)
  # end

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
    {:error, ArgumentError.t, state} |
    {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  # def handle_prepare(%Query{name: @reserved_prefix <> _} = query, _, s) do
  #   reserved_error(query, s)
  # end
  def handle_prepare(query, opts, s) do
    handle_prepare(query, :parse_describe, opts, s)
  end

  @spec handle_execute(Sqlite.DbConnection.Query.t, list, Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Result.t, state} |
    {:prepare, state} |
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

  @spec handle_execute_close(Sqlite.DbConnection.Query.t, list, Keyword.t, state) ::
    {:ok, Sqlite.DbConnection.Result.t, state} |
    {:prepare, state} |
    {:error, ArgumentError.t, state} |
    {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  # def handle_execute_close(%Query{name: @reserved_prefix <> _} = query, _, _, s) do
  #   reserved_error(query, s)
  # end
  def handle_execute_close(query, params, opts, s) do
    handle_execute(query, params, :sync_close, opts, s)
  end

  # @spec handle_close(Sqlite.DbConnection.Query.t, Keyword.t, state) ::
  #   {:ok, state} |
  #   {:error, ArgumentError.t, state} |
  #   {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  # def handle_close(%Query{name: @reserved_prefix <> _} = query, _, s) do
  #   reserved_error(query, s)
  # end
  def handle_close(_query, _opts, s) do
    # no-op: esqlite doesn't expose statement close.
    # Instead it relies on statements getting garbage collected.
    {:ok, s}
  end

  # def handle_begin(opts, s) do
  #   handle_transaction(@reserved_prefix <> "BEGIN", :transaction, opts, s)
  # end
  #
  # def handle_commit(opts, s) do
  #   handle_transaction(@reserved_prefix <> "COMMIT", :idle, opts, s)
  # end
  #
  # def handle_rollback(opts, s) do
  #   handle_transaction(@reserved_prefix <> "ROLLBACK", :idle, opts, s)
  # end
  #
  # @spec handle_simple(String.t, Keyword.t, state) ::
  #   {:ok, Sqlite.DbConnection.Result.t, state} |
  #   {:error | :disconnect, Sqlite.DbConnection.Error.t, state}
  # def handle_simple(statement, opts, %{buffer: buffer} = s) do
  #   status = %{notify: notify(opts), sync: :sync}
  #   simple_send(%{s | buffer: nil}, status, statement, buffer)
  # end
  #
  # @spec handle_info(any, Keyword.t, state) ::
  #   {:ok, state} | {:error | :disconnect, Sqlite.DbConnection.Error.t}
  # def handle_info(msg, opts \\ [], s)
  #
  # def handle_info({:tcp, sock, data}, opts, %{sock: {:gen_tcp, sock}} = s) do
  #   handle_data(s, opts, data)
  # end
  # def handle_info({:tcp_closed, sock}, _, %{sock: {:gen_tcp, sock}} = s) do
  #   err = Sqlite.DbConnection.Error.exception(tag: :tcp, action: "async recv", reason: :closed)
  #   {:disconnect, err, s}
  # end
  # def handle_info({:tcp_error, sock, reason}, _, %{sock: {:gen_tcp, sock}} = s) do
  #   err = Sqlite.DbConnection.Error.exception(tag: :tcp, action: "async recv", reason: reason)
  #   {:disconnect, err, s}
  # end
  # def handle_info({:ssl, sock, data}, opts, %{sock: {:ssl, sock}} = s) do
  #   handle_data(s, opts, data)
  # end
  # def handle_info({:ssl_closed, sock}, _, %{sock: {:ssl, sock}} = s) do
  #   err = Sqlite.DbConnection.Error.exception(tag: :ssl, action: "async recv", reason: :closed)
  #   {:disconnect, err, s}
  # end
  # def handle_info({:ssl_error, sock, reason}, _, %{sock: {:ssl, sock}} = s) do
  #   err = Sqlite.DbConnection.Error.exception(tag: :ssl, action: "async recv", reason: reason)
  #   {:disconnect, err, s}
  # end
  # def handle_info(msg, _, s) do
  #   Logger.info(fn() -> [inspect(__MODULE__), ?\s, inspect(self()),
  #     " received unexpected message: " | inspect(msg)]
  #   end)
  #   {:ok, s}
  # end

  ## prepare

  defp handle_prepare(%Query{statement: statement} = query, :parse_describe, _opts,
                      %__MODULE__{checked_out?: true, db: db} = s)
  do
    binary_stmt = :erlang.iolist_to_binary(statement)
    case Sqlitex.Statement.prepare(db, binary_stmt) do
      {:ok, prepared_stmt} ->
        updated_query = %{query | prepared: prepared_stmt}
        {:ok, updated_query, s}
      {:error, {_sqlite_errcode, _message}} = err ->
        sqlite_error(err, s)
    end
  end

  ## execute

  defp handle_execute(query, params, _sync, _opts, s) do
    case query do
      %Query{prepared: nil} ->
        query_error(s, "query #{inspect query} has not been prepared")
      %Query{prepared: stmt} ->
        case run_stmt(stmt, params, s) do
          {:ok, result} ->
            {:ok, result, s}
          other ->
            other
        end
    end
  end

  defp query_error(s, msg) do
    {:error, ArgumentError.exception(msg), s}
  end
  defp sqlite_error({:error, {sqlite_errcode, message}}, s) do
    {:error, %Sqlite.DbConnection.Error{sqlite: %{code: sqlite_errcode}, message: message}, s}
  end

  defp run_stmt(stmt, [], s) do
    case Sqlitex.Statement.fetch_all(stmt, :raw_list) do
      {:ok, rows} ->
        {:ok, result_for_rows_and_stmt(rows, stmt)}
      {:error, {_sqlite_errcode, _message}} = err ->
        sqlite_error(err, s)
    end
  end
  defp run_stmt(stmt, params, s) when is_list(params) do
    case Sqlitex.Statement.bind_values(stmt, params) do
      {:ok, stmt} ->
        run_stmt(stmt, [], s)
      {:error, :args_wrong_length} ->
        query_error(s, "parameters must match number of placeholders in query")
    end
  end

  defp result_for_rows_and_stmt(rows, %Sqlitex.Statement{} = stmt) do
    {rows, num_rows, column_names} = rows_and_column_names_from_stmt(rows, stmt)
    command = command_from_stmt(stmt)
    %Sqlite.DbConnection.Result{rows: rows,
                                num_rows: num_rows,
                                columns: column_names,
                                command: command}
  end

  defp rows_and_column_names_from_stmt([], %{column_names: []}), do:
    {nil, nil, nil}
  defp rows_and_column_names_from_stmt(rows, %{column_names: column_names}), do:
    {rows, length(rows), Enum.map(column_names, &Atom.to_string/1)}

  defp command_from_stmt(%Sqlitex.Statement{sql: sql}) do
    first_words = String.split(String.downcase(sql), " ", parts: 3)
    command_from_words(first_words)
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
end
