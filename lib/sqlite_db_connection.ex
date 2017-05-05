defmodule Sqlite.DbConnection do
  @moduledoc """
  DBConnection implementation for SQLite.
  """

  # IMPORTANT: This is closely modeled on Postgrex's postgrex.ex file.
  # We strive to avoid structural differences between that file and this one.

  alias Sqlite.DbConnection.Query

  @typedoc """
  A connection process name, pid or reference.

  A connection reference is used when making multiple requests to the same
  connection, see `transaction/3` and `:after_connect` in `start_link/1`.
  """
  @type conn :: DBConnection.conn

  @pool_timeout 5000
  @timeout 5000
  @idle_timeout 5000
  @max_rows 500

  ### PUBLIC API ###

  @doc """
  Start the connection process and connect to SQLite.

  ## Options

    * `:database` - Database (required);
    * `:parameters` - Keyword list of connection parameters;
    * `:after_connect` - A function to run on connect, either a 1-arity fun
    called with a connection reference, `{module, function, args}` with the
    connection reference prepended to `args` or `nil`, (default: `nil`)
    * `:transactions` - Set to `:strict` to error on unexpected transaction
    state, otherwise set to `naive` (default: `:naive`);
    * `:pool` - The pool module to use, see `DBConnection`, it must be
    included with all requests if not the default (default:
    `DBConnection.Connection`);

    `Sqlite.DbConnection` uses the `DBConnection` framework and supports all
    `DBConnection` options like `:idle`, `:after_connect` etc.

    See `DBConnection.start_link/2` for more information.
  """
  @spec start_link(Keyword.t) :: {:ok, pid} | {:error, Sqlite.DbConnection.Error.t | term}
  def start_link(opts) do
    DBConnection.start_link(Sqlite.DbConnection.Protocol, opts)
  end

  @doc """
  Runs an (extended) query and returns the result as `{:ok, %Sqlite.DbConnection.Result{}}`
  or `{:error, %Sqlite.DbConnection.Error{}}` if there was a database error.
  Parameters can be set in the query as `?1` embedded in the query string.
  Parameters are given as a list of Elixir values. See the README for information
  on how SQLite encodes and decodes Elixir values by default. See
  `Sqlite.DbConnection.Result` for the result data.

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Query request timeout (default: `#{@timeout}`);
    * `:decode_mapper` - Fun to map each row in the result to a term after
    decoding, (default: `fn x -> x end`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`

  ## Examples

      Sqlite.DbConnection.query(conn, "CREATE TABLE posts (id serial, title text)", [])

      Sqlite.DbConnection.query(conn, "INSERT INTO posts (title) VALUES ('my title')", [])

      Sqlite.DbConnection.query(conn, "SELECT title FROM posts", [])

      Sqlite.DbConnection.query(conn, "SELECT id FROM posts WHERE title like $1", ["%my%"])

  """
  @spec query(conn, iodata, list, Keyword.t) :: {:ok, Sqlite.DbConnection.Result.t} | {:error, Sqlite.DbConnection.Error.t}
  def query(conn, statement, params, opts \\ []) do
    query = %Query{name: "", statement: statement}
    case DBConnection.prepare_execute(conn, query, params, defaults(opts)) do
      {:ok, _, result} ->
        {:ok, result}
      {:error, %Sqlite.DbConnection.Error{}} = error ->
        error
      {:error, %ArgumentError{} = err} ->
        raise err
    end
  end

  @doc """
  Prepares an (extended) query and returns the result as
  `{:ok, %Sqlite.DbConnection.Query{}}` or `{:error, %Sqlite.DbConnection.Error{}}`
  if there was an error. Parameters can be set in the query as `?1` embedded in
  the query string. To execute the query call `execute/4`. To close the prepared
  query call `close/3`. See `Sqlite.DbConnection.Query` for the query data.

  This function may still raise an exception if there is an issue with types
  (`ArgumentError`), connection (`DBConnection.ConnectionError`), ownership
  (`DBConnection.OwnershipError`) or other error (`RuntimeError`).

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Prepare request timeout (default: `#{@timeout}`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`

  ## Examples

      Sqlite.DbConnection.prepare(conn, "", "CREATE TABLE posts (id serial, title text)")
  """
  @spec prepare(conn, iodata, iodata, Keyword.t) ::
    {:ok, Sqlite.DbConnection.Query.t} | {:error, Sqlite.DbConnection.Error.t}
  def prepare(conn, name, statement, opts \\ []) do
    query = %Query{name: name, statement: statement}
    case DBConnection.prepare(conn, query, defaults(opts)) do
      {:ok, _} = ok ->
        ok
      {:error, %Sqlite.DbConnection.Error{}} = error ->
        error
      {:error, err} ->
        raise err
    end
  end

  @doc """
  Prepares an (extended) query and returns the prepared query or raises
  `Sqlite.DbConnection.Error` if there was an error. See `prepare/4`.
  """
  @spec prepare!(conn, iodata, iodata, Keyword.t) :: Sqlite.DbConnection.Query.t
  def prepare!(conn, name, statement, opts \\ []) do
    DBConnection.prepare!(conn, %Query{name: name, statement: statement}, defaults(opts))
  end

  @doc """
  Runs an (extended) prepared query and returns the result as
  `{:ok, %Sqlite.DbConnection.Result{}}` or `{:error, %Sqlite.DbConnection.Error{}}`
  if there was an error. Parameters are given as part of the prepared query,
  `%Sqlite.DbConnection.Query{}`. See the README for information on how SQLite
  encodes and decodes Elixir values by default. See `Sqlite.DbConnection.Query`
  for the query data and `Sqlite.DbConnection.Result` for the result data.

  This function may still raise an exception if there is an issue with types
  (`ArgumentError`), connection (`DBConnection.ConnectionError`), ownership
  (`DBConnection.OwnershipError`) or other error (`RuntimeError`).

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Execute request timeout (default: `#{@timeout}`);
    * `:decode_mapper` - Fun to map each row in the result to a term after
    decoding, (default: `fn x -> x end`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`

  ## Examples

      query = Sqlite.DbConnection.prepare!(conn, "", "CREATE TABLE posts (id serial, title text)")
      Sqlite.DbConnection.execute(conn, query, [])

      query = Sqlite.DbConnection.prepare!(conn, "", "SELECT id FROM posts WHERE title like $1")
      Sqlite.DbConnection.execute(conn, query, ["%my%"])
  """
  @spec execute(conn, Sqlite.DbConnection.Query.t, list, Keyword.t) ::
    {:ok, Sqlite.DbConnection.Result.t} | {:error, Sqlite.DbConnection.Error.t}
  def execute(conn, query, params, opts \\ []) do
    case DBConnection.execute(conn, query, params, defaults(opts)) do
      {:ok, _} = ok ->
        ok
      {:error, %Sqlite.DbConnection.Error{}} = error ->
        error
      {:error, err} ->
        raise err
    end
  end

  @doc """
  Runs an (extended) prepared query and returns the result or raises
  `Sqlite.DbConnection.Error` if there was an error. See `execute/4`.
  """
  @spec execute!(conn, Sqlite.DbConnection.Query.t, list, Keyword.t) :: Sqlite.DbConnection.Result.t
  def execute!(conn, query, params, opts \\ []) do
    DBConnection.execute!(conn, query, params, defaults(opts))
  end

  @doc """
  Closes an (extended) prepared query and returns `:ok` or
  `{:error, %Sqlite.DbConnection.Error{}}` if there was an error. Closing a query
  releases any resources held by SQLite for a prepared query with that name. See
  `Sqlite.DbConnection.Query` for the query data.

  This function may still raise an exception if there is an issue with types
  (`ArgumentError`), connection (`DBConnection.ConnectionError`), ownership
  (`DBConnection.OwnershipError`) or other error (`RuntimeError`).

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Close request timeout (default: `#{@timeout}`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`

  ## Examples

      query = Sqlite.DbConnection.prepare!(conn, "", "CREATE TABLE posts (id serial, title text)")
      Sqlite.DbConnection.close(conn, query)
  """
  @spec close(conn, Sqlite.DbConnection.Query.t, Keyword.t) :: :ok | {:error, Sqlite.DbConnection.Error.t}
  def close(conn, query, opts \\ []) do
    case DBConnection.close(conn, query, defaults(opts)) do
      {:ok, _} ->
        :ok
      {:error, %Sqlite.DbConnection.Error{}} = error ->
        error
      {:error, err} ->
        raise err
    end
  end

  @doc """
  Closes an (extended) prepared query and returns `:ok` or raises
  `Sqlite.DbConnection.Error` if there was an error. See `close/3`.
  """
  @spec close!(conn, Sqlite.DbConnection.Query.t, Keyword.t) :: :ok
  def close!(conn, query, opts \\ []) do
    DBConnection.close!(conn, query, defaults(opts))
  end

  @doc """
  Acquire a lock on a connection and run a series of requests inside a
  transaction. The result of the transaction fun is return inside an `:ok`
  tuple: `{:ok, result}`.

  To use the locked connection call the request with the connection
  reference passed as the single argument to the `fun`. If the
  connection disconnects all future calls using that connection
  reference will fail.

  `rollback/2` rolls back the transaction and causes the function to
  return `{:error, reason}`.

  `transaction/3` can be nested multiple times if the connection
  reference is used to start a nested transaction. The top level
  transaction function is the actual transaction.

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Transaction timeout (default: `#{@timeout}`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`;
    * `:mode` - Set to `:savepoint` to use savepoints instead of an SQL
    transaction, otherwise set to `:transaction` (default: `:transaction`);

  The `:timeout` is for the duration of the transaction and all nested
  transactions and requests. This timeout overrides timeouts set by internal
  transactions and requests. The `:pool` and `:mode` will be used for all
  requests inside the transaction function.

  ## Example

      {:ok, res} = Sqlite.DbConnection.transaction(pid, fn(conn) ->
        Sqlite.DbConnection.query!(conn, "SELECT title FROM posts", [])
      end)
  """
  @spec transaction(conn, ((DBConnection.t) -> result), Keyword.t) ::
    {:ok, result} | {:error, any} when result: var
  def transaction(conn, fun, opts \\ []) do
    DBConnection.transaction(conn, fun, defaults(opts))
  end

  @doc """
  Rollback a transaction, does not return.

  Aborts the current transaction fun. If inside multiple `transaction/3`
  functions, bubbles up to the top level.

  ## Example

      {:error, :oops} = Sqlite.DbConnection.transaction(pid, fn(conn) ->
        DBConnection.rollback(conn, :bar)
        IO.puts "never reaches here!"
      end)
  """
  @spec rollback(DBConnection.t, any) :: no_return()
  defdelegate rollback(conn, any), to: DBConnection

  @doc """
  Returns a supervisor child specification for a DBConnection pool.
  """
  @spec child_spec(Keyword.t) :: Supervisor.Spec.spec
  def child_spec(opts) do
    DBConnection.child_spec(Sqlite.DbConnection.Protocol, defaults(opts))
  end

  @doc """
  Returns a stream for a query on a connection.

  Except that it doesn't. The implementation currently reads the entire query
  into memory and returns it as one "stream" result. A future version may
  implement this more fully.
  """
  @spec stream(DBConnection.t, iodata | Sqlite.DbConnection.Query.t, list, Keyword.t) ::
    Sqlite.DbConnection.Stream.t
  def stream(%DBConnection{} = conn, query, params, options \\ []) do
    options =
      options
      |> defaults()
      |> Keyword.put_new(:max_rows, @max_rows)
    %Sqlite.DbConnection.Stream{conn: conn, query: query, params: params, options: options}
  end

  ## Helpers

  defp defaults(opts) do
    Keyword.put_new(opts, :timeout, @timeout)
  end
end
