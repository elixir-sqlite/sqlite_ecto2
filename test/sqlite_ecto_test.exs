defmodule Sqlite.Ecto2.Test do
  use ExUnit.Case, async: true

  # IMPORTANT: This is closely modeled on Ecto's postgres_test.exs file.
  # We strive to avoid structural differences between that file and this one.

  alias Sqlite.Ecto2.Connection, as: SQL
  alias Ecto.Migration.Table

  test "storage up (twice)" do
    tmp = [database: tempfilename()]
    assert Sqlite.Ecto2.storage_up(tmp) == :ok
    assert File.exists? tmp[:database]
    assert Sqlite.Ecto2.storage_up(tmp) == {:error, :already_up}
    File.rm(tmp[:database])
  end

  test "storage down (twice)" do
    tmp = [database: tempfilename()]
    assert Sqlite.Ecto2.storage_up(tmp) == :ok
    assert Sqlite.Ecto2.storage_down(tmp) == :ok
    assert not File.exists? tmp[:database]
    assert Sqlite.Ecto2.storage_down(tmp) == {:error, :already_down}
  end

  test "storage up creates directory" do
    dir = "/tmp/my_sqlite_ecto_directory/"
    File.rm_rf! dir
    tmp = [database: dir <> tempfilename()]
    :ok = Sqlite.Ecto2.storage_up(tmp)
    assert File.exists?(dir <> "tmp/") && File.dir?(dir <> "tmp/")
  end

  # return a unique temporary filename
  defp tempfilename do
    1..10
    |> Enum.map(fn(_) -> :rand.uniform(10) - 1 end)
    |> Enum.join
    |> (fn(name) -> "/tmp/test_" <> name <> ".db" end).()
  end

  import Ecto.Query

  alias Ecto.Queryable

  defmodule Schema do
    use Ecto.Schema

    schema "schema" do
      field :x, :integer
      field :y, :integer
      field :z, :integer

      has_many :comments, Sqlite.Ecto2.Test.Schema2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Sqlite.Ecto2.Test.Schema3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Schema2 do
    use Ecto.Schema

    schema "schema2" do
      belongs_to :post, Sqlite.Ecto2.Test.Schema,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Schema3 do
    use Ecto.Schema

    schema "schema3" do
      field :list1, {:array, :string}
      field :list2, {:array, :integer}
      field :binary, :binary
    end
  end

  defp normalize(query, operation \\ :all, counter \\ 0) do
    {query, _params, _key} = Ecto.Query.Planner.prepare(query, operation, Sqlite.Ecto2, counter)
    Ecto.Query.Planner.normalize(query, operation, Sqlite.Ecto2, counter)
  end

  test "from" do
    query = Schema |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "from without schema" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    query = "posts" |> select([:x]) |> normalize
    assert SQL.all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    assert_raise Ecto.QueryError, ~r"SQLite does not support selecting all fields", fn ->
      SQL.all normalize(from(p in "posts", select: p))
    end
  end

  test "from with subquery" do
    query = subquery(select("posts", [r], %{x: r.x, y: r.y})) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM (SELECT p0."x" AS "x", p0."y" AS "y" FROM "posts" AS p0) AS s0}

    query = subquery(select("posts", [r], %{x: r.x, z: r.y})) |> select([r], r) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x", s0."z" FROM (SELECT p0."x" AS "x", p0."y" AS "z" FROM "posts" AS p0) AS s0}
  end

  test "select" do
    query = Schema |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], [r.x, r.y]) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], struct(r, [:x, :y])) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "aggregates" do
    query = Schema |> select([r], count(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT count(s0."x") FROM "schema" AS s0}

    query = Schema |> select([r], count(r.x, :distinct)) |> normalize
    assert SQL.all(query) == ~s{SELECT count(DISTINCT s0."x") FROM "schema" AS s0}
  end

  test "distinct" do
    assert_raise ArgumentError, "DISTINCT with multiple columns is not supported by SQLite", fn ->
      query = Schema |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> normalize
      SQL.all(query)
    end

    query = Schema |> distinct([r], true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "distinct with order by" do
    assert_raise ArgumentError, "DISTINCT with multiple columns is not supported by SQLite", fn ->
      query = Schema |> order_by([r], [r.y]) |> distinct([r], desc: r.x) |> select([r], r.x) |> normalize
      SQL.all(query)
    end
  end

  test "where" do
    query = Schema |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) AND (s0."y" != 43)}
  end

  test "or_where" do
    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) OR (s0."y" != 43)}

    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> where([r], r.z == 44) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE ((s0."x" = 42) OR (s0."y" != 43)) AND (s0."z" = 44)}
  end

  test "order by" do
    query = Schema |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x"}

    query = Schema |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y"}

    query = Schema |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y" DESC}

    query = Schema |> order_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "limit and offset" do
    query = Schema |> limit([r], 3) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 LIMIT 3}

    query = Schema |> offset([r], 5) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 OFFSET 5}

    query = Schema |> offset([r], 5) |> limit([r], 3) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    assert_raise ArgumentError, "locks are not supported by SQLite", fn ->
      query = Schema |> lock("FOR SHARE NOWAIT") |> select([], 0) |> normalize
      SQL.all(query)
    end
  end

  test "string escape" do
    query = "schema" |> where(foo: "'\\  ") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM \"schema\" AS s0 WHERE (s0.\"foo\" = '''\\  ')}

    query = "schema" |> where(foo: "'") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = '''')}
  end

  test "binary ops" do
    query = Schema |> select([r], r.x == 2) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" = 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x != 2) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" != 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x <= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" <= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x >= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" >= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x < 2) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" < 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x > 2) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" > 2 FROM "schema" AS s0}
  end

  test "is_nil" do
    query = Schema |> select([r], is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" IS NULL FROM "schema" AS s0}

    query = Schema |> select([r], not is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT NOT (s0."x" IS NULL) FROM "schema" AS s0}
  end

  test "fragments" do
    query = Schema |> select([r], fragment("ltrim(?)", r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT ltrim(s0."x") FROM "schema" AS s0}

    value = 13
    query = Schema |> select([r], fragment("ltrim(?, ?)", r.x, ^value)) |> normalize
    assert SQL.all(query) == ~s{SELECT ltrim(s0."x", ?) FROM "schema" AS s0}

    query = Schema |> select([], fragment(title: 2)) |> normalize
    assert_raise Ecto.QueryError, ~r"SQLite adapter does not support keyword or interpolated fragments", fn ->
      SQL.all(query)
    end
  end

  test "literals" do
    query = "schema" |> where(foo: true) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 1)}

    query = "schema" |> where(foo: false) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 0)}

    query = "schema" |> where(foo: "abc") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 'abc')}

    query = "schema" |> where(foo: <<0,?a,?b,?c>>) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = X'00616263')}

    query = "schema" |> where(foo: 123) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 123)}

    query = "schema" |> where(foo: 123.0) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 123.0)}
  end

  test "tagged type" do
    query = Schema |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> normalize
    assert SQL.all(query) == ~s{SELECT CAST (? AS TEXT) FROM "schema" AS s0}

    assert_raise ArgumentError, "Array type is not supported by SQLite", fn ->
      query = Schema |> select([], type(^[1,2,3], {:array, :integer})) |> normalize
      SQL.all(query)
    end
  end

  test "nested expressions" do
    z = 123
    query = from(r in Schema, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
    assert SQL.all(query) == ~s{SELECT ((s0."x" > 0) AND (s0."y" > ?)) OR 1 FROM "schema" AS s0}
  end

  test "in expression" do
    query = Schema |> select([e], 1 in []) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN () FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1,s0."x",3) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN () FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[1, 2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (?1,?2,?3) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1, ^2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1,?,3) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in fragment("foo")) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (foo) FROM "schema" AS s0}
  end

  test "having" do
    query = Schema |> having([p], p.x == p.x) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query = Schema |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x") AND (s0."y" = s0."y")}
  end

  test "or_having" do
    query = Schema |> or_having([p], p.x == p.x) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query = Schema |> or_having([p], p.x == p.x) |> or_having([p], p.y == p.y) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x") OR (s0."y" = s0."y")}
  end

  test "group by" do
    query = Schema |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x"}

    query = Schema |> group_by([r], 2) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY 2}

    query = Schema |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x", s0."y"}

    query = Schema |> group_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "interpolated values" do
    query = "schema"
            |> select([m], {m.id, ^true})
            |> join(:inner, [], Schema2, fragment("?", ^true))
            |> join(:inner, [], Schema2, fragment("?", ^false))
            |> where([], fragment("?", ^true))
            |> where([], fragment("?", ^false))
            |> having([], fragment("?", ^true))
            |> having([], fragment("?", ^false))
            |> group_by([], fragment("?", ^1))
            |> group_by([], fragment("?", ^2))
            |> order_by([], fragment("?", ^3))
            |> order_by([], ^:x)
            |> limit([], ^4)
            |> offset([], ^5)
            |> normalize

    result = remove_newlines """
    SELECT s0."id", ? FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON ?
    INNER JOIN "schema2" AS s2 ON ? WHERE (?) AND (?)
    GROUP BY ?, ? HAVING (?) AND (?)
    ORDER BY ?, s0."x" LIMIT ? OFFSET ?
    """

    assert SQL.all(query) == result
  end

  test "fragments allow ? to be escaped with backslash" do
    query =
      normalize from(e in "schema",
        where: fragment("? = \"query\\?\"", e.start_time),
        select: true)

    result =
      "SELECT 1 FROM \"schema\" AS s0 " <>
      "WHERE (s0.\"start_time\" = \"query?\")"

    assert SQL.all(query) == String.trim(result)
  end

  ## *_all

  test "update all" do
    query = normalize(from(m in Schema, update: [set: [x: 0]]), :update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "schema" SET "x" = 0}

    query = normalize(from(m in Schema, update: [set: [x: 0], inc: [y: 1, z: -3]]), :update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "schema" SET "x" = 0, "y" = "schema"."y" + 1, "z" = "schema"."z" + -3}

    query = normalize(from(m in Schema, update: [set: [x: ^0]]), :update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "schema" SET "x" = ?}

    assert_raise ArgumentError, "JOINS are not supported on UPDATE statements by SQLite", fn ->
      query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z)
                    |> update([_], set: [x: 0]) |> normalize(:update_all)
      SQL.update_all(query)
    end
  end

  test "delete all" do
    query = Schema |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == ~s{DELETE FROM "schema"}

    query = normalize(from(e in Schema, where: e.x == 123))
    assert SQL.delete_all(query) == ~s{DELETE FROM "schema" WHERE ("schema"."x" = 123)}

    assert_raise ArgumentError, "JOINS are not supported on DELETE statements by SQLite", fn ->
      query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> normalize
      SQL.delete_all(query)
    end

    # NOTE: The assertions commented out below represent how joins *could* be
    # handled in SQLite to produce the same effect. Evenually, joins should
    # be converted to the below output. Until then, joins should raise
    # exceptions.

    # query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> normalize
    # #assert SQL.delete_all(query) == ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1 WHERE s0."x" = s1."z"}
    # assert SQL.delete_all(query) == ~s{DELETE FROM "schema" WHERE "schema"."x" IN ( SELECT s1."z" FROM "schema2" AS s1 )}
    #
    # query = from(e in Schema, where: e.x == 123, join: q in Schema2, on: e.x == q.z) |> normalize
    # #assert SQL.delete_all(query) == ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1 WHERE s0."x" = s1."z" AND (s0."x" = 123)}
    # assert SQL.delete_all(query) == ~s{DELETE FROM "schema" WHERE "schema"."x" IN ( SELECT s1."z" FROM "schema2" AS s1 ) AND ( "schema"."x" = 123 )}
  end

  ## Joins

  test "join" do
    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 1 FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s0."x" = s1."z"}

    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z)
                  |> join(:inner, [], Schema, true) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 1 FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s0."x" = s1."z" } <>
           ~s{INNER JOIN "schema" AS s2 ON 1}
  end

  test "join with nothing bound" do
    query = Schema |> join(:inner, [], q in Schema2, q.z == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 1 FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s1."z" = s1."z"}
  end

  test "join without schema" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 1 FROM "posts" AS p0 INNER JOIN "comments" AS c1 ON p0."x" = c1."z"}
  end

  test "join with subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, y: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), true) |> select([_, p], p.x) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT s1."x" FROM "comments" AS c0 } <>
           ~s{INNER JOIN (SELECT p0."x" AS "x", p0."y" AS "y" FROM "posts" AS p0 WHERE (p0."title" = ?)) AS s1 ON 1}

    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, z: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), true) |> select([_, p], p) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT s1."x", s1."z" FROM "comments" AS c0 } <>
           ~s{INNER JOIN (SELECT p0."x" AS "x", p0."y" AS "z" FROM "posts" AS p0 WHERE (p0."title" = ?)) AS s1 ON 1}
  end

  test "join with prefix" do
    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(%{query | prefix: "prefix"}) ==
           ~s{SELECT 1 FROM "prefix"."schema" AS s0 INNER JOIN "prefix"."schema2" AS s1 ON s0."x" = s1."z"}
  end

  test "join with fragment" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p], {p.id, ^0})
            |> where([p], p.id > 0 and p.id < ^100)
            |> normalize
    assert SQL.all(query) ==
      ~s{SELECT s0."id", ? FROM "schema" AS s0 INNER JOIN } <>
      ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0."x" AND s2.field = ?) AS f1 ON 1 } <>
      ~s{WHERE ((s0."id" > 0) AND (s0."id" < ?))}
  end

  ## Associations

  test "association join belongs_to" do
    query = Schema2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT 1 FROM \"schema2\" AS s0 INNER JOIN \"schema\" AS s1 ON s1.\"x\" = s0.\"z\""
  end

  test "association join has_many" do
    query = Schema |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT 1 FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON s1.\"z\" = s0.\"x\""
  end

  test "association join has_one" do
    query = Schema |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT 1 FROM \"schema\" AS s0 INNER JOIN \"schema3\" AS s1 ON s1.\"id\" = s0.\"y\""
  end

  test "join produces correct bindings" do
    query = from(p in Schema, join: c in Schema2, on: true)
    query = from(p in query, join: c in Schema2, on: true, select: {p.id, c.id})
    query = normalize(query)
    assert SQL.all(query) ==
           "SELECT s0.\"id\", s2.\"id\" FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON 1 INNER JOIN \"schema2\" AS s2 ON 1"
  end

  # Schema based

  test "insert" do
    query = SQL.insert(nil, "schema", [:x, :y], [[:x, :y]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ;--RETURNING ON INSERT "schema","id"}

    # query = SQL.insert(nil, "schema", [:x, :y], [[:x, :y], [nil, :z]], {:raise, [], []}, [:id])
    # assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2),(DEFAULT,$3) RETURNING "id"}

    query = SQL.insert(nil, "schema", [], [[]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO "schema" DEFAULT VALUES ;--RETURNING ON INSERT "schema","id"}

    query = SQL.insert(nil, "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO "schema" DEFAULT VALUES}

    query = SQL.insert("prefix", "schema", [], [[]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO "prefix"."schema" DEFAULT VALUES ;--RETURNING ON INSERT "prefix"."schema","id"}

    query = SQL.insert("prefix", "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO "prefix"."schema" DEFAULT VALUES}
  end

  test "insert with on conflict" do
    query = SQL.insert(nil, "schema", [:x, :y], [[:x, :y]], {:nothing, [], []}, [])
    assert query == ~s{INSERT OR IGNORE INTO "schema" ("x","y") VALUES (?1,?2)}

    assert_raise ArgumentError, "Upsert in SQLite must use on_conflict: :nothing", fn ->
      SQL.insert(nil, "schema", [:x, :y], [[:x, :y]], {:nothing, [], [:x, :y]}, [])
    end

    assert_raise ArgumentError, "Upsert in SQLite must use on_conflict: :nothing", fn ->
      update = normalize(from("schema", update: [set: [z: "foo"]]), :update_all)
      SQL.insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])
    end

    assert_raise ArgumentError, "Upsert in SQLite must use on_conflict: :nothing", fn ->
      update = normalize(from("schema", update: [set: [z: ^"foo"]], where: [w: true]), :update_all, 2)
      SQL.insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])
    end
  end

  test "update" do
    query = SQL.update(nil, "schema", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3}

    query = SQL.update(nil, "schema", [:x, :y], [:id], [:x, :z])
    assert query == ~s{UPDATE "schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE "schema","x","z"}

    query = SQL.update("prefix", "schema", [:x, :y], [:id], [:x, :z])
    assert query == ~s{UPDATE "prefix"."schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE "prefix"."schema","x","z"}

    query = SQL.update("prefix", "schema", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "prefix"."schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3}
  end

  test "delete" do
    query = SQL.delete(nil, "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = ?1 AND "y" = ?2}

    query = SQL.delete(nil, "schema", [:x, :y], [:z])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = ?1 AND "y" = ?2 ;--RETURNING ON DELETE "schema","z"}

    query = SQL.delete("prefix", "schema", [:x, :y], [:z])
    assert query == ~s{DELETE FROM "prefix"."schema" WHERE "x" = ?1 AND "y" = ?2 ;--RETURNING ON DELETE "prefix"."schema","z"}

    query = SQL.delete(nil, "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = ?1 AND "y" = ?2}

    query = SQL.delete("prefix", "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "prefix"."schema" WHERE "x" = ?1 AND "y" = ?2}
  end

  # DDL

  import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3, references: 1,
                                references: 2, constraint: 2, constraint: 3]

  test "executing a string during migration" do
    assert execute_ddl("example") == ["example"]
  end

  test "create table" do
    create = {:create, table(:posts),
               [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
                {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
                {:add, :on_hand, :integer, [default: 0, null: true]},
                {:add, :is_active, :boolean, [default: true]}]}

    assert execute_ddl(create) == [remove_newlines """
    CREATE TABLE "posts" ("name" TEXT DEFAULT 'Untitled' NOT NULL,
    "price" NUMERIC DEFAULT expr,
    "on_hand" INTEGER DEFAULT 0,
    "is_active" BOOLEAN DEFAULT 1)
    """]
  end

  test "create table if not exists" do
    create = {:create_if_not_exists, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :title, :string, []},
                {:add, :price, :decimal, [precision: 10, scale: 2]},
                {:add, :created_at, :datetime, []}]}
    query = execute_ddl(create)
    assert query == [remove_newlines """
    CREATE TABLE IF NOT EXISTS "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "title" TEXT,
    "price" DECIMAL(10,2),
    "created_at" DATETIME)
    """]
  end

  test "create table with prefix" do
    create = {:create, table(:posts, prefix: :foo),
               [{:add, :category_0, references(:categories), []}]}

    assert execute_ddl(create) == [remove_newlines """
    CREATE TABLE "foo"."posts"
    ("category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"))
    """]
  end

  test "create table with references" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_0, references(:categories), []},
                {:add, :category_1, references(:categories, name: :foo_bar), []},
                {:add, :category_2, references(:categories, on_delete: :nothing), []},
                {:add, :category_3, references(:categories, on_delete: :delete_all), [null: false]},
                {:add, :category_4, references(:categories, on_delete: :nilify_all), []},
                {:add, :category_5, references(:categories, on_update: :nothing), []},
                {:add, :category_6, references(:categories, on_update: :update_all), [null: false]},
                {:add, :category_7, references(:categories, on_update: :nilify_all), []},
                {:add, :category_8, references(:categories, on_delete: :nilify_all, on_update: :update_all), [null: false]}]}

    assert execute_ddl(create) == [remove_newlines """
    CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"),
    "category_1" INTEGER CONSTRAINT "foo_bar" REFERENCES "categories"("id"),
    "category_2" INTEGER CONSTRAINT "posts_category_2_fkey" REFERENCES "categories"("id"),
    "category_3" INTEGER NOT NULL CONSTRAINT "posts_category_3_fkey" REFERENCES "categories"("id") ON DELETE CASCADE,
    "category_4" INTEGER CONSTRAINT "posts_category_4_fkey" REFERENCES "categories"("id") ON DELETE SET NULL,
    "category_5" INTEGER CONSTRAINT "posts_category_5_fkey" REFERENCES "categories"("id"),
    "category_6" INTEGER NOT NULL CONSTRAINT "posts_category_6_fkey" REFERENCES "categories"("id") ON UPDATE CASCADE,
    "category_7" INTEGER CONSTRAINT "posts_category_7_fkey" REFERENCES "categories"("id") ON UPDATE SET NULL,
    "category_8" INTEGER NOT NULL CONSTRAINT "posts_category_8_fkey" REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE)
    """]
  end

  test "create table with references including prefixes" do
    create = {:create, table(:posts, prefix: :foo),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_0, references(:categories, prefix: :foo), []},
                {:add, :category_1, references(:categories, name: :foo_bar, prefix: :foo), []},
                {:add, :category_2, references(:categories, on_delete: :nothing, prefix: :foo), []},
                {:add, :category_3, references(:categories, on_delete: :delete_all, prefix: :foo), [null: false]},
                {:add, :category_4, references(:categories, on_delete: :nilify_all, prefix: :foo), []}]}

    assert execute_ddl(create) == [remove_newlines """
    CREATE TABLE "foo"."posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"),
    "category_1" INTEGER CONSTRAINT "foo_bar" REFERENCES "foo"."categories"("id"),
    "category_2" INTEGER CONSTRAINT "posts_category_2_fkey" REFERENCES "foo"."categories"("id"),
    "category_3" INTEGER NOT NULL CONSTRAINT "posts_category_3_fkey" REFERENCES "foo"."categories"("id") ON DELETE CASCADE,
    "category_4" INTEGER CONSTRAINT "posts_category_4_fkey" REFERENCES "foo"."categories"("id") ON DELETE SET NULL)
    """]
  end

  test "create table with options" do
    create = {:create, table(:posts, options: "WITHOUT ROWID"),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :created_at, :datetime, []}]}
    assert execute_ddl(create) ==
           [~s|CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "created_at" DATETIME) WITHOUT ROWID|]
  end

  test "create table with composite key" do
    create = {:create, table(:posts),
               [{:add, :a, :integer, [primary_key: true]},
                {:add, :b, :integer, [primary_key: true]},
                {:add, :name, :string, []}]}

    assert execute_ddl(create) == [remove_newlines """
    CREATE TABLE "posts" ("a" INTEGER, "b" INTEGER, "name" TEXT, PRIMARY KEY ("a", "b"))
    """]
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert execute_ddl(drop) == [~s|DROP TABLE "posts"|]
  end

  test "drop table if exists" do
    assert execute_ddl({:drop_if_exists, %Table{name: "posts"}}) == [~s|DROP TABLE IF EXISTS "posts"|]
  end

  test "drop table with prefix" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP TABLE "foo"."posts"|]
  end

  test "alter table" do
    alter = {:alter, table(:posts),
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:add, :author_id, references(:author), []}]}
    assert execute_ddl(alter) == [
      remove_newlines(~s|ALTER TABLE "posts" ADD COLUMN "title" TEXT DEFAULT 'Untitled' NOT NULL|),
      remove_newlines(~s|ALTER TABLE "posts" ADD COLUMN "author_id" INTEGER CONSTRAINT "posts_author_id_fkey" REFERENCES "author"("id")|)]
  end

  test "alter table with prefix" do
    alter = {:alter, table(:posts, prefix: :foo),
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:add, :author_id, references(:author, prefix: :foo), []}]}

    assert execute_ddl(alter) == [
      remove_newlines(~s|ALTER TABLE "foo"."posts" ADD COLUMN "title" TEXT DEFAULT 'Untitled' NOT NULL|),
      remove_newlines(~s|ALTER TABLE "foo"."posts" ADD COLUMN "author_id" INTEGER CONSTRAINT "posts_author_id_fkey" REFERENCES "foo"."author"("id")|)]
  end

  test "alter column errors for :modify column" do
    alter = {:alter, table(:posts), [{:modify, :price, :numeric, [precision: 8, scale: 2]}]}
    assert_raise ArgumentError, "ALTER COLUMN not supported by SQLite", fn ->
      SQL.execute_ddl(alter)
    end
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX "posts_category_id_permalink_index" ON "posts" ("category_id", "permalink")|]

    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main")}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX "posts$main" ON "posts" (lower(permalink))|]
  end

  test "create index if not exists" do
    create = {:create_if_not_exists, index(:posts, [:category_id, :permalink])}
    query = execute_ddl(create)
    assert query == [~s|CREATE INDEX IF NOT EXISTS "posts_category_id_permalink_index" ON "posts" ("category_id", "permalink")|]
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX "posts_category_id_permalink_index" ON "foo"."posts" ("category_id", "permalink")|]

    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main", prefix: :foo)}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX "posts$main" ON "foo"."posts" (lower(permalink))|]
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}
    assert execute_ddl(create) ==
           [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create unique index if not exists" do
    create = {:create_if_not_exists, index(:posts, [:permalink], unique: true)}
    query = execute_ddl(create)
    assert query == [~s|CREATE UNIQUE INDEX IF NOT EXISTS "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create unique index with condition" do
    create = {:create, index(:posts, [:permalink], unique: true, where: "public IS 1")}
    assert execute_ddl(create) ==
           [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public IS 1|]

    create = {:create, index(:posts, [:permalink], unique: true, where: :public)}
    assert execute_ddl(create) ==
           [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public|]
  end

  test "create index concurrently" do
    # NOTE: SQLite doesn't support CONCURRENTLY, so this isn't included in generated SQL.
    create = {:create, index(:posts, [:permalink], concurrently: true)}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create unique index concurrently" do
    # NOTE: SQLite doesn't support CONCURRENTLY, so this isn't included in generated SQL.
    create = {:create, index(:posts, [:permalink], concurrently: true, unique: true)}
    assert execute_ddl(create) ==
           [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create an index using a different type" do
    # NOTE: SQLite doesn't support USING, so this isn't included in generated SQL.
    create = {:create, index(:posts, [:permalink], using: :hash)}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert execute_ddl(drop) == [~s|DROP INDEX "posts$main"|]
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP INDEX "foo"."posts$main"|]
  end

  test "drop index if exists" do
    drop = {:drop_if_exists, index(:posts, [:id], name: "posts$main")}
    assert execute_ddl(drop) == [~s|DROP INDEX IF EXISTS "posts$main"|]
  end

  test "drop index concurrently" do
    # NOTE: SQLite doesn't support CONCURRENTLY, so this isn't included in generated SQL.
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true)}
    assert execute_ddl(drop) == [~s|DROP INDEX "posts$main"|]
  end

  test "create check constraint" do
    create = {:create, constraint(:products, "price_must_be_positive", check: "price > 0")}
    assert_raise ArgumentError, "ALTER TABLE with constraints not supported by SQLite", fn ->
      SQL.execute_ddl(create)
    end

    create = {:create, constraint(:products, "price_must_be_positive", check: "price > 0", prefix: "foo")}
    assert_raise ArgumentError, "ALTER TABLE with constraints not supported by SQLite", fn ->
      SQL.execute_ddl(create)
    end
  end

  test "create exclusion constraint" do
    create = {:create, constraint(:products, "price_must_be_positive", exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|)}
    assert_raise ArgumentError, "ALTER TABLE with constraints not supported by SQLite", fn ->
      SQL.execute_ddl(create)
    end
  end

  test "drop constraint" do
    drop = {:drop, constraint(:products, "price_must_be_positive")}
    assert_raise ArgumentError, "ALTER TABLE with constraints not supported by SQLite", fn ->
      SQL.execute_ddl(drop)
    end

    drop = {:drop, constraint(:products, "price_must_be_positive", prefix: "foo")}
    assert_raise ArgumentError, "ALTER TABLE with constraints not supported by SQLite", fn ->
      SQL.execute_ddl(drop)
    end
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert execute_ddl(rename) == [~s|ALTER TABLE "posts" RENAME TO "new_posts"|]
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert execute_ddl(rename) == [~s|ALTER TABLE "foo"."posts" RENAME TO "new_posts"|]
  end

  test "rename column errors" do
    rename = {:rename, table(:posts), :given_name, :first_name}
    assert_raise ArgumentError, "RENAME COLUMN not supported by SQLite", fn ->
      SQL.execute_ddl(rename)
    end
  end

  test "rename column in prefixed table errors" do
    rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}
    assert_raise ArgumentError, "RENAME COLUMN not supported by SQLite", fn ->
      SQL.execute_ddl(rename)
    end
  end

  test "drop column errors" do
    alter = {:alter, table(:posts), [{:remove, :summary}]}
    assert_raise ArgumentError, "DROP COLUMN not supported by SQLite", fn ->
      SQL.execute_ddl(alter)
    end
  end

  defp remove_newlines(string) do
    string |> String.trim |> String.replace("\n", " ")
  end

  defp execute_ddl(command) do
    command |> SQL.execute_ddl() |> Enum.map(&IO.iodata_to_binary/1)
  end
end
