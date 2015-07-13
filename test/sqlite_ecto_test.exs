defmodule Sqlite.Ecto.Test do
  use ExUnit.Case, async: true

  alias Sqlite.Ecto.Connection, as: SQL
  alias Ecto.Migration.Table

  setup do
    {:ok, sql} = SQL.connect(database: ":memory:")
    {:ok, sql: sql}
  end

  test "storage up (twice)" do
    tmp = [database: tempfilename]
    assert Sqlite.Ecto.storage_up(tmp) == :ok
    assert File.exists? tmp[:database]
    assert Sqlite.Ecto.storage_up(tmp) == {:error, :already_up}
    File.rm(tmp[:database])
  end

  test "storage down (twice)" do
    tmp = [database: tempfilename]
    assert Sqlite.Ecto.storage_up(tmp) == :ok
    assert Sqlite.Ecto.storage_down(tmp) == :ok
    assert not File.exists? tmp[:database]
    assert Sqlite.Ecto.storage_down(tmp) == {:error, :already_down}
  end

  # return a unique temporary filename
  defp tempfilename do
    1..10
    |> Enum.map(fn(_) -> :random.uniform(10) - 1 end)
    |> Enum.join
    |> (fn(name) -> "/tmp/test_" <> name <> ".db" end).()
  end

  test "insert" do
    query = SQL.insert("model", [:x, :y], [:id])
    assert query == ~s{INSERT INTO "model" ("x", "y") VALUES (?1, ?2) ;--RETURNING ON INSERT "model","id"}

    query = SQL.insert("model", [], [:id])
    assert query == ~s{INSERT INTO "model" DEFAULT VALUES ;--RETURNING ON INSERT "model","id"}

    query = SQL.insert("model", [], [])
    assert query == ~s{INSERT INTO "model" DEFAULT VALUES}
  end

  test "update" do
    query = SQL.update("model", [:x, :y], [:id], [:x, :z])
    assert query == ~s{UPDATE "model" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE "model","x","z"}

    query = SQL.update("model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "model" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3}
  end

  test "delete" do
    query = SQL.delete("model", [:x, :y], [:z])
    assert query == ~s{DELETE FROM "model" WHERE "x" = ?1 AND "y" = ?2 ;--RETURNING ON DELETE "model","z"}

    query = SQL.delete("model", [:x, :y], [])
    assert query == ~s{DELETE FROM "model" WHERE "x" = ?1 AND "y" = ?2}
  end

  test "query", context do
    sql = context[:sql]
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "CREATE TABLE model (id, x, y, z)", [], [])

    {:ok, %{num_rows: 1, rows: nil}} = SQL.query(sql, "INSERT INTO model VALUES (1, 2, 3, 4)", [], [])
    query = ~s{UPDATE "model" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE "model","x","z"}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:foo, :bar, 1], [])
    assert row == ["foo", 4]

    query = ~s{INSERT INTO "model" VALUES (?1, ?2, ?3, ?4) ;--RETURNING ON INSERT "model","id"}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:a, :b, :c, :d], [])
    assert row == ["a"]

    query = ~s{DELETE FROM "model" WHERE "id" = ?1 ;--RETURNING ON DELETE "model","id","x","y","z"}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [1], [])
    assert row == [1, "foo", "bar", 4]
  end

  test "table exists", context do
    sql = context[:sql]
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "CREATE TABLE model (id, x, y, z)", [], [])
    query = SQL.ddl_exists(%Table{name: "model"})
    assert query == "SELECT count(1) FROM sqlite_master WHERE name = 'model' AND type = 'table'"
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [], [])
    assert row == [1]
    query = SQL.ddl_exists(%Table{name: "not_model"})
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [], [])
    assert row == [0]
  end

  import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3, references: 1, references: 2]

  test "executing a string during migration" do
    assert SQL.execute_ddl("example") == "example"
  end

  test "create table" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :title, :string, []},
                {:add, :price, :decimal, [precision: 10, scale: 2]},
                {:add, :created_at, :datetime, []}]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "title" TEXT, "price" DECIMAL(10,2), "created_at" DATETIME)}
  end

  test "create table with reference" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_id, references(:categories), []} ]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "category_id" REFERENCES "categories"("id"))}
  end

  test "create table reference on delete nothing" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_id, references(:categories, on_delete: :nothing), []} ]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "category_id" REFERENCES "categories"("id"))}
  end

  test "create table reference on delete nilify_all" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_id, references(:categories, on_delete: :nilify_all), []} ]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "category_id" REFERENCES "categories"("id") ON DELETE SET NULL)}
  end

  test "create table reference on delete delete_all" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_id, references(:categories, on_delete: :delete_all), []} ]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "category_id" REFERENCES "categories"("id") ON DELETE CASCADE)}
  end

  test "create table with column options" do
    create = {:create, table(:posts),
               [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
                {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
                {:add, :on_hand, :integer, [default: 0, null: true]},
                {:add, :is_active, :boolean, [default: true]}]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("name" TEXT DEFAULT 'Untitled' NOT NULL, "price" NUMERIC DEFAULT (expr), "on_hand" INTEGER DEFAULT 0, "is_active" BOOLEAN DEFAULT 1)}
  end

  test "create table with table options" do
    create = {:create, table(:posts, options: "WITHOUT ROWID"),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :created_at, :datetime, []}]}
    assert SQL.execute_ddl(create) == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "created_at" DATETIME) WITHOUT ROWID}
  end

  test "drop table" do
    assert SQL.execute_ddl({:drop, %Table{name: "posts"}}) == ~s{DROP TABLE "posts"}
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE INDEX "posts_category_id_permalink_index" ON "posts" ("category_id", "permalink")}
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink")}
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert SQL.execute_ddl(drop) == ~s{DROP INDEX "posts$main"}
  end

  test "alter table" do
    alter = {:alter, table(:posts),
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:add, :email, :string, []}]}
    query = SQL.execute_ddl(alter)
    assert query == ~s{ALTER TABLE "posts" ADD COLUMN "title" TEXT DEFAULT 'Untitled' NOT NULL; ALTER TABLE "posts" ADD COLUMN "email" TEXT}
  end

  test "alter table query", context do
    sql = context[:sql]
    SQL.query(sql, ~s{CREATE TABLE "posts" ("author" TEXT, "price" INTEGER, "summary" TEXT, "body" TEXT)}, [], [])
    SQL.query(sql, "INSERT INTO posts VALUES ('jazzyb', 2, 'short statement', 'Longer, more detailed statement.')", [], [])

    # alter the table
    alter = {:alter, table(:posts),
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:add, :email, :string, []}]}
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, SQL.execute_ddl(alter), [], [])

    # verify the schema has been updated
    {:ok, %{num_rows: 1, rows: [[stmt]]}} = SQL.query(sql, "SELECT sql FROM sqlite_master WHERE name = 'posts' AND type = 'table'", [], [])
    assert stmt == ~s{CREATE TABLE "posts" ("author" TEXT, "price" INTEGER, "summary" TEXT, "body" TEXT, "title" TEXT DEFAULT 'Untitled' NOT NULL, "email" TEXT)}

    # verify the values have been preserved
    [row] = Sqlitex.Server.query(sql, "SELECT * FROM posts")
    assert "jazzyb" == Keyword.get(row, :author)
    assert 2 == Keyword.get(row, :price)
    assert "Longer, more detailed statement." == Keyword.get(row, :body)
    assert "Untitled" == Keyword.get(row, :title)
    assert nil == Keyword.get(row, :email)
    assert "short statement" == Keyword.get(row, :summary)
  end

  test "alter column errors" do
    alter = {:alter, table(:posts), [{:modify, :price, :numeric, [precision: 8, scale: 2]}]}
    assert_raise ArgumentError, "ALTER COLUMN not supported by SQLite", fn ->
      SQL.execute_ddl(alter)
    end
  end

  test "drop column errors" do
    alter = {:alter, table(:posts), [{:remove, :summary}]}
    assert_raise ArgumentError, "DROP COLUMN not supported by SQLite", fn ->
      SQL.execute_ddl(alter)
    end
  end

  ## Tests stolen from PostgreSQL adapter:

  import Ecto.Query

  alias Ecto.Queryable

  defmodule Model do
    use Ecto.Model

    schema "model" do
      field :x, :integer
      field :y, :integer
      field :z, :integer

      has_many :comments, Sqlite.Ecto.Test.Model2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Sqlite.Ecto.Test.Model3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Model2 do
    use Ecto.Model

    schema "model2" do
      belongs_to :post, Sqlite.Ecto.Test.Model,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Model3 do
    use Ecto.Model

    schema "model3" do
      field :list1, {:array, :string}
      field :list2, {:array, :integer}
      field :binary, :binary
    end
  end

  defp normalize(query, operation \\ :all) do
    {query, _params} = Ecto.Query.Planner.prepare(query, operation, %{})
    Ecto.Query.Planner.normalize(query, operation, %{})
  end

  test "from" do
    query = Model |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
  end

  test "from without model" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    assert_raise ArgumentError, ~r"SQLite requires a model", fn ->
      SQL.all from(p in "posts", select: p) |> normalize()
    end
  end

#  test "from with schema source" do
#    query = "public.posts" |> select([r], r.x) |> normalize
#    assert SQL.all(query) == ~s{SELECT p0."x" FROM "public"."posts" AS p0}
#  end
#
  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> select([r], [r.x, r.y]) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}
  end

  test "distinct" do
    assert_raise ArgumentError, "DISTINCT with multiple columns is not supported by SQLite", fn ->
      query = Model |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> normalize
      SQL.all(query)
    end

    query = Model |> distinct([r], true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct([r], false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct([], true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct([], false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}
  end

  test "where" do
    query = Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 WHERE (m0."y" != 43) AND (m0."x" = 42)}
  end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x"}

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x", m0."y"}

    query = Model |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x", m0."y" DESC}

    query = Model |> order_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
  end

  test "limit and offset" do
    query = Model |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM "model" AS m0 LIMIT 3}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM "model" AS m0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    assert_raise ArgumentError, "locks are not supported by SQLite", fn ->
      query = Model |> lock("FOR SHARE NOWAIT") |> select([], 0) |> normalize
      SQL.all(query)
    end
  end

  test "string escape" do
    query = Model |> select([], "'\\  ") |> normalize
    assert SQL.all(query) == ~s{SELECT '''\\  ' FROM "model" AS m0}

    query = Model |> select([], "'") |> normalize
    assert SQL.all(query) == ~s{SELECT '''' FROM "model" AS m0}
  end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" = 2 FROM "model" AS m0}

    query = Model |> select([r], r.x != 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" != 2 FROM "model" AS m0}

    query = Model |> select([r], r.x <= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" <= 2 FROM "model" AS m0}

    query = Model |> select([r], r.x >= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" >= 2 FROM "model" AS m0}

    query = Model |> select([r], r.x < 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" < 2 FROM "model" AS m0}

    query = Model |> select([r], r.x > 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" > 2 FROM "model" AS m0}
  end

  test "is_nil" do
    query = Model |> select([r], is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" IS NULL FROM "model" AS m0}

    query = Model |> select([r], not is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT NOT (m0."x" IS NULL) FROM "model" AS m0}
  end

  test "fragments" do
    query = Model |> select([r], fragment("ltrim(?)", r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT ltrim(m0."x") FROM "model" AS m0}

    value = 13
    query = Model |> select([r], fragment("ltrim(?, ?)", r.x, ^value)) |> normalize
    assert SQL.all(query) == ~s{SELECT ltrim(m0."x", ?) FROM "model" AS m0}

    query = Model |> select([], fragment(title: 2)) |> normalize
    assert_raise ArgumentError, "SQLite adapter does not support keyword or interpolated fragments", fn ->
      SQL.all(query)
    end
  end

  test "literals" do
    query = Model |> select([], nil) |> normalize
    assert SQL.all(query) == ~s{SELECT NULL FROM "model" AS m0}

    query = Model |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM "model" AS m0}

    query = Model |> select([], false) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM "model" AS m0}

    query = Model |> select([], "abc") |> normalize
    assert SQL.all(query) == ~s{SELECT 'abc' FROM "model" AS m0}

    query = Model |> select([], 123) |> normalize
    assert SQL.all(query) == ~s{SELECT 123 FROM "model" AS m0}

    query = Model |> select([], 123.0) |> normalize
    assert SQL.all(query) == ~s{SELECT 123.0 FROM "model" AS m0}
  end

  test "tagged type" do
    query = Model |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> normalize
    assert SQL.all(query) == ~s{SELECT CAST (? AS TEXT) FROM "model" AS m0}

    assert_raise ArgumentError, "Array type is not supported by SQLite", fn ->
      query = Model |> select([], type(^[1,2,3], {:array, :integer})) |> normalize
      SQL.all(query)
    end
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
    assert SQL.all(query) == ~s{SELECT ((m0."x" > 0) AND (m0."y" > ?)) OR 1 FROM "model" AS m0}
  end

  test "in expression" do
    query = Model |> select([e], 1 in []) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN () FROM "model" AS m0}

    query = Model |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1, m0."x", 3) FROM "model" AS m0}

    query = Model |> select([e], 1 in ^[]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN () FROM "model" AS m0}

    query = Model |> select([e], 1 in ^[1, 2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (?, ?, ?) FROM "model" AS m0}

    query = Model |> select([e], 1 in [1, ^2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1, ?, 3) FROM "model" AS m0}

    query = Model |> select([e], 1 in fragment("foo")) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (foo) FROM "model" AS m0}
  end

  test "group by" do
    query = Model |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x"}

    query = Model |> group_by([r], r.x) |> having([r], r.x == r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x" HAVING (m0."x" = m0."x")}

    query = Model |> group_by([r], 2) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY 2}

    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x", m0."y"}

    query = Model |> group_by([r], [r.x, r.y]) |> having([r], r.x == r.x) |> having([r], r.y == r.y) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x", m0."y" HAVING (m0."y" = m0."y") AND (m0."x" = m0."x")}

    query = Model |> group_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
  end

  test "interpolated values" do
    query = Model
            |> select([], ^0)
            |> join(:inner, [], Model2, ^true)
            |> join(:inner, [], Model2, ^false)
            |> where([], ^true)
            |> where([], ^false)
            |> group_by([], ^1)
            |> group_by([], ^2)
            |> having([], ^true)
            |> having([], ^false)
            |> order_by([], fragment("?", ^3))
            |> order_by([], ^:x)
            |> limit([], ^4)
            |> offset([], ^5)
            |> normalize

    result =
      "SELECT ? FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON ? " <>
      "INNER JOIN \"model2\" AS m2 ON ? WHERE (?) AND (?) " <>
      "GROUP BY ?, ? HAVING (?) AND (?) " <>
      "ORDER BY ?, m0.\"x\" LIMIT ? OFFSET ?"

    assert SQL.all(query) == String.rstrip(result)
  end

  ## Joins

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m0."x" = m1."z"}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
                  |> join(:inner, [], Model, true) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m0."x" = m1."z" } <>
           ~s{INNER JOIN "model" AS m2 ON 1}
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, q.z == q.z) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m1."z" = m1."z"}
  end

  test "join without model" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM "posts" AS p0 INNER JOIN "comments" AS c1 ON p0."x" = c1."z"}
  end

  ## Associations

  test "association join belongs_to" do
    query = Model2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           "SELECT 0 FROM \"model2\" AS m0 INNER JOIN \"model\" AS m1 ON m1.\"x\" = m0.\"z\""
  end

  test "association join has_many" do
    query = Model |> join(:inner, [p], c in assoc(p, :comments)) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           "SELECT 0 FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON m1.\"z\" = m0.\"x\""
  end

  test "association join has_one" do
    query = Model |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           "SELECT 0 FROM \"model\" AS m0 INNER JOIN \"model3\" AS m1 ON m1.\"id\" = m0.\"y\""
  end

  test "join produces correct bindings" do
    query = from(p in Model, join: c in Model2, on: true)
    query = from(p in query, join: c in Model2, on: true, select: {p.id, c.id})
    query = normalize(query)
    assert SQL.all(query) ==
           "SELECT m0.\"id\", m2.\"id\" FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON 1 INNER JOIN \"model2\" AS m2 ON 1"
  end

  test "update all" do
    query = from(m in Model, update: [set: [x: 0]]) |> normalize(:update_all)
    assert SQL.update_all(query) == ~s{UPDATE "model" SET "x" = 0}

    query = from(m in Model, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> normalize(:update_all)
    assert SQL.update_all(query) == ~s{UPDATE "model" SET "x" = 0, "y" = "y" + 1, "z" = "z" + -3}

    query = from(e in Model, update: [set: [x: 0, y: "123"]]) |> normalize(:update_all)
    assert SQL.update_all(query) == ~s{UPDATE "model" SET "x" = 0, "y" = 123}

    query = from(m in Model, update: [set: [x: ^0]]) |> normalize(:update_all)
    assert SQL.update_all(query) == ~s{UPDATE "model" SET "x" = ?}

    assert_raise ArgumentError, "JOINS are not supported on UPDATE statements by SQLite", fn ->
      query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
                    |> update([_], set: [x: 0]) |> normalize(:update_all)
      SQL.update_all(query)
    end
  end

  test "delete all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == ~s{DELETE FROM "model"}

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) == ~s{DELETE FROM "model" WHERE ("model"."x" = 123)}

    assert_raise ArgumentError, "JOINS are not supported on DELETE statements by SQLite", fn ->
      query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> normalize
      SQL.delete_all(query)
    end

    # NOTE:  The assertions commented out below represent how joins *could* be
    # handled in SQLite to produce the same effect.  Evenually, joins should
    # be converted to the below output.  Until then, joins should raise
    # exceptions.

#    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> normalize
#    #assert SQL.delete_all(query) == ~s{DELETE FROM "model" AS m0 USING "model2" AS m1 WHERE m0."x" = m1."z"}
#    assert SQL.delete_all(query) == ~s{DELETE FROM "model" WHERE "model"."x" IN ( SELECT m1."z" FROM "model2" AS m1 )}
#
#    query = from(e in Model, where: e.x == 123, join: q in Model2, on: e.x == q.z) |> normalize
#    #assert SQL.delete_all(query) == ~s{DELETE FROM "model" AS m0 USING "model2" AS m1 WHERE m0."x" = m1."z" AND (m0."x" = 123)}
#    assert SQL.delete_all(query) == ~s{DELETE FROM "model" WHERE "model"."x" IN ( SELECT m1."z" FROM "model2" AS m1 ) AND ( "model"."x" = 123 )}
  end
end
