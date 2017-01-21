defmodule Sqlite.DbConnection.Connection do
  @moduledoc """
  DBConnection implementation for SQLite.
  """

  # IMPORTANT: This is closely modeled on Postgrex's connection.ex file.
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

  ### PUBLIC API ###

  @doc """
  Start the connection process and connect to SQLite.

  ## Options

    * `:hostname` - Server hostname (default: PGHOST env variable, then localhost);
    * `:port` - Server port (default: 5432);
    * `:database` - Database (required);
    * `:username` - Username (default: PGUSER env variable, then USER env var);
    * `:password` - User password (default PGPASSWORD);
    * `:parameters` - Keyword list of connection parameters;
    * `:timeout` - Connect timeout in milliseconds (default: `#{@timeout}`);
    * `:ssl` - Set to `true` if ssl should be used (default: `false`);
    * `:ssl_opts` - A list of ssl options, see ssl docs;
    * `:socket_options` - Options to be given to the underlying socket;
    * `:sync_connect` - Block in `start_link/1` until connection is set up (default: `false`)
    * `:after_connect` - A function to run on connect, either a 1-arity fun
    called with a connection reference, `{module, function, args}` with the
    connection reference prepended to `args` or `nil`, (default: `nil`)
    * `:idle_timeout` - Idle timeout to ping SQLite to maintain a connection
    (default: `#{@idle_timeout}`)
    * `:backoff_start` - The first backoff interval when reconnecting (default:
    `200`);
    * `:backoff_max` - The maximum backoff interval when reconnecting (default:
    `15_000`);
    * `:backoff_type` - The backoff strategy when reconnecting, `:stop` for no
    backoff and to stop (see `:backoff`, default: `:jitter`)
    * `:transactions` - Set to `:strict` to error on unexpected transaction
    state, otherwise set to `naive` (default: `:naive`);
    * `:pool` - The pool module to use, see `DBConnection`, it must be
    included with all requests if not the default (default:
    `DBConnection.Connection`);
  """
  @spec start_link(Keyword.t) :: {:ok, pid} | {:error, Sqlite.DbConnection.Error.t | term}
  def start_link(opts) do
    # TODO: Not sure how to map this to SQLite opts.
    # opts = [types: true] ++ Sqlite.DbConnection.Utils.default_opts(opts)
    DBConnection.start_link(Sqlite.DbConnection.Protocol, opts)
  end

  @doc """
  Runs an (extended) query and returns the result as `{:ok, %Sqlite.DbConnection.Result{}}`
  or `{:error, %Sqlite.DbConnection.Error{}}` if there was an error. Parameters can be
  set in the query as `$1` embedded in the query string. Parameters are given as
  a list of elixir values. See the README for information on how SQLite
  encodes and decodes Elixir values by default. See `Sqlite.DbConnection.Result` for the
  result data.

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Query request timeout (default: `#{@timeout}`);
    * `:encode_mapper` - Fun to map each parameter before encoding, see
    (default: `fn x -> x end`)
    * `:decode_mapper` - Fun to map each row in the result to a term after
    decoding, (default: `fn x -> x end`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`
    * `:proxy` - The proxy module for the request, if any, see
    `DBConnection.Proxy` (default: `nil`);

  ## Examples

      Sqlite.DbConnection.Connection.query(conn, "CREATE TABLE posts (id serial, title text)", [])

      Sqlite.DbConnection.Connection.query(conn, "INSERT INTO posts (title) VALUES ('my title')", [])

      Sqlite.DbConnection.Connection.query(conn, "SELECT title FROM posts", [])

      Sqlite.DbConnection.Connection.query(conn, "SELECT id FROM posts WHERE title like $1", ["%my%"])

  """
  @spec query(conn, iodata, list, Keyword.t) :: {:ok, Sqlite.DbConnection.Result.t} | {:error, Sqlite.DbConnection.Error.t}
  def query(conn, statement, params, opts \\ []) do
    query = %Query{name: "", statement: statement}
    case DBConnection.query(conn, query, params, defaults(opts)) do
      {:error, %ArgumentError{} = err} ->
        raise err
      other ->
        other
    end
  end

  @doc """
  Runs an (extended) query and returns the result or raises `Sqlite.DbConnection.Error` if
  there was an error. See `query/3`.
  """
  @spec query!(conn, iodata, list, Keyword.t) :: Sqlite.DbConnection.Result.t
  def query!(conn, statement, params, opts \\ []) do
    query = %Query{name: "", statement: statement}
    DBConnection.query!(conn, query, params, defaults(opts))
  end

  @doc """
  Prepares an (extended) query and returns the result as
  `{:ok, %Sqlite.DbConnection.Query{}}` or `{:error, %Sqlite.DbConnection.Error{}}` if there was an
  error. Parameters can be set in the query as `$1` embedded in the query
  string. To execute the query call `execute/4`. To close the prepared query
  call `close/3`. See `Sqlite.DbConnection.Query` for the query data.

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Prepare request timeout (default: `#{@timeout}`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`
    * `:proxy` - The proxy module for the request, if any, see
    `DBConnection.Proxy` (default: `nil`);

  ## Examples

      Sqlite.DbConnection.Connection.prepare(conn, "CREATE TABLE posts (id serial, title text)")
  """
  @spec prepare(conn, iodata, iodata, Keyword.t) :: {:ok, Sqlite.DbConnection.Query.t} | {:error, Sqlite.DbConnection.Error.t}
  def prepare(conn, name, statement, opts \\ []) do
    query = %Query{name: name, statement: statement}
    case DBConnection.prepare(conn, query, defaults(opts)) do
      {:error, %ArgumentError{} = err} ->
        raise err
      other ->
        other
    end
  end

  @doc """
  Prepared an (extended) query and returns the prepared query or raises
  `Sqlite.DbConnection.Error` if there was an error. See `prepare/4`.
  """
  @spec prepare!(conn, iodata, iodata, Keyword.t) :: Sqlite.DbConnection.Query.t
  def prepare!(conn, name, statement, opts \\ []) do
    DBConnection.prepare!(conn, %Query{name: name, statement: statement}, defaults(opts))
  end

  @doc """
  Runs an (extended) prepared query and returns the result as
  `{:ok, %Sqlite.DbConnection.Result{}}` or `{:error, %Sqlite.DbConnection.Error{}}` if there was an
  error. Parameters are given as part of the prepared query, `%Sqlite.DbConnection.Query{}`.
  See the README for information on how SQLite encodes and decodes Elixir
  values by default. See `Sqlite.DbConnection.Query` for the query data and
  `Sqlite.DbConnection.Result` for the result data.

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Execute request timeout (default: `#{@timeout}`);
    * `:encode_mapper` - Fun to map each parameter before encoding, see
    (default: `fn x -> x end`)
    * `:decode_mapper` - Fun to map each row in the result to a term after
    decoding, (default: `fn x -> x end`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`
    * `:proxy` - The proxy module for the request, if any, see
    `DBConnection.Proxy` (default: `nil`);

  ## Examples

      query = Sqlite.DbConnection.Connection.prepare!(conn, "CREATE TABLE posts (id serial, title text)")
      Sqlite.DbConnection.Connection.execute(conn, query, [])

      query = Sqlite.DbConnection.Connection.prepare!(conn, "SELECT id FROM posts WHERE title like $1")
      Sqlite.DbConnection.Connection.execute(conn, query, ["%my%"])
  """
  @spec execute(conn, Sqlite.DbConnection.Query.t, list, Keyword.t) ::
    {:ok, Sqlite.DbConnection.Result.t} | {:error, Sqlite.DbConnection.Error.t}
  def execute(conn, query, params, opts \\ []) do
    case DBConnection.execute(conn, query, params, defaults(opts)) do
      {:error, %ArgumentError{} = err} ->
        raise err
      other ->
        other
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
  `{:error, %Sqlite.DbConnection.Error{}}` if there was an error. Closing a query releases
  any resources held by SQLite for a prepared query with that name. See
  `Sqlite.DbConnection.Query` for the query data.

  ## Options

    * `:pool_timeout` - Time to wait in the queue for the connection
    (default: `#{@pool_timeout}`)
    * `:queue` - Whether to wait for connection in a queue (default: `true`);
    * `:timeout` - Close request timeout (default: `#{@timeout}`);
    * `:pool` - The pool module to use, must match that set on
    `start_link/1`, see `DBConnection`
    * `:proxy` - The proxy module for the request, if any, see
    `DBConnection.Proxy` (default: `nil`);

  ## Examples

      query = Sqlite.DbConnection.Connection.prepare!(conn, "CREATE TABLE posts (id serial, title text)")
      Sqlite.DbConnection.Connection.close(conn, query)
  """
  @spec close(conn, Sqlite.DbConnection.Query.t, Keyword.t) :: :ok | {:error, Sqlite.DbConnection.Error.t}
  def close(conn, query, opts \\ []) do
    case DBConnection.close(conn, query, defaults(opts)) do
      {:error, %ArgumentError{} = err} ->
        raise err
      other ->
        other
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
  tuple: `{:ok result}`.

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
    `start_link/1`, see `DBConnection`
    * `:proxy` - The proxy module for the request, if any, see
    `DBConnection.Proxy` (default: `nil`);

  The `:timeout` is for the duration of the transaction and all nested
  transactions and requests. This timeout overrides timeouts set by internal
  transactions and requests. The `:pool` and `:proxy` will be used
  for all requests inside the transaction function.

  ## Example

      {:ok, res} = Sqlite.DbConnection.Connection.transaction(pid, fn(conn) ->
        Sqlite.DbConnection.Connection.query!(conn, "SELECT title FROM posts", [])
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

      {:error, :oops} = Sqlite.DbConnection.Connection.transaction(pid, fn(conn) ->
        DBConnection.rollback(conn, :bar)
        IO.puts "never reaches here!"
      end)
  """
  @spec rollback(DBConnection.t, any) :: no_return()
  defdelegate rollback(conn, any), to: DBConnection

  # This may not apply in the SQLite case. Let's wait to see if we need it.
  # @doc """
  # Returns a cached map of connection parameters.
  #
  # ## Options
  #
  #   * `:pool_timeout` - Call timeout (default: `#{@pool_timeout}`)
  #   * `:pool` - The pool module to use, must match that set on
  #   `start_link/1`, see `DBConnection`
  #
  # """
  # @spec parameters(conn, Keyword.t) :: %{binary => binary}
  # def parameters(conn, opts \\ []) do
  #   DBConnection.execute!(conn, %Sqlite.DbConnection.Parameters{}, nil, defaults(opts))
  # end

  ## Helpers

  defp defaults(opts) do
    Keyword.put_new(opts, :timeout, @timeout)
  end
end
