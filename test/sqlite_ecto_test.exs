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
    assert Sqlite.Ecto.storage_up(tmp) == {:error, :already_up}
    File.rm(tmp[:database])
  end

  test "storage down (twice)" do
    tmp = [database: tempfilename]
    assert Sqlite.Ecto.storage_up(tmp) == :ok
    assert Sqlite.Ecto.storage_down(tmp) == :ok
    assert not File.exists?(tmp[:database])
    assert Sqlite.Ecto.storage_down(tmp) == {:error, :already_down}
  end

  # return a unique temporary filename
  defp tempfilename do
    :erlang.now |> :random.seed
    1..10
    |> Enum.map(fn(_) -> :random.uniform(10) - 1 end)
    |> Enum.join
    |> (fn(name) -> "/tmp/test_" <> name <> ".db" end).()
  end

  test "insert" do
    query = SQL.insert("model", [:x, :y], [:id])
    assert query == ~s{INSERT INTO "model" ("x","y") VALUES (?1,?2) ;--RETURNING ON INSERT "model","id"}

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

    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "INSERT INTO model VALUES (1, 2, 3, 4)", [], [])
    query = ~s{UPDATE "model" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE "model","x","z"}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:foo, :bar, 1], [])
    assert row == [x: "foo", z: 4]

    query = ~s{INSERT INTO "model" VALUES (?1, ?2, ?3, ?4) ;--RETURNING ON INSERT "model","id"}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:a, :b, :c, :d], [])
    assert row == [id: "a"]

    query = ~s{DELETE FROM "model" WHERE "id" = ?1 ;--RETURNING ON DELETE "model","id","x","y","z"}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [1], [])
    assert row == [id: 1, x: "foo", y: "bar", z: 4]
  end

  test "table exists", context do
    sql = context[:sql]
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "CREATE TABLE model (id, x, y, z)", [], [])
    query = SQL.ddl_exists(%Table{name: "model"})
    assert query == "SELECT count(1) FROM sqlite_master WHERE name = 'model' AND type = 'table'"
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [], [])
    assert row == ["count(1)": 1]
    query = SQL.ddl_exists(%Table{name: "not_model"})
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [], [])
    assert row == ["count(1)": 0]
  end

  import Ecto.Migration, only: [table: 1, index: 2, index: 3, references: 1]

  test "create table" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :title, :string, []},
                {:add, :created_at, :datetime, []}]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "title" TEXT, "created_at" DATETIME)}
  end

  test "create table with reference" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_id, references(:categories), []} ]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "category_id" REFERENCES "categories"("id"))}
  end

  test "create table with column options" do
    create = {:create, table(:posts),
               [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
                {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
                {:add, :on_hand, :integer, [default: 0, null: true]},
                {:add, :is_active, :boolean, [default: true]}]}
    query = SQL.execute_ddl(create)
    assert query == ~s{CREATE TABLE "posts" ("name" TEXT DEFAULT 'Untitled' NOT NULL, "price" NUMERIC DEFAULT (expr), "on_hand" INTEGER DEFAULT 0, "is_active" BOOLEAN DEFAULT true)}
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
                {:modify, :price, :numeric, [precision: 8, scale: 2]},
                {:remove, :summary}]}
    query = SQL.execute_ddl(alter)
    assert query == ~s{ALTER TABLE "posts" ADD COLUMN "title" TEXT DEFAULT 'Untitled' NOT NULL; ALTER TABLE "posts" ALTER COLUMN "price" NUMERIC; ALTER TABLE "posts" DROP COLUMN "summary"}
  end

  test "alter table query", context do
    sql = context[:sql]
    SQL.query(sql, ~s{CREATE TABLE "posts" ("author" TEXT, "price" INTEGER, "summary" TEXT, "body" TEXT)}, [], [])
    SQL.query(sql, "CREATE INDEX this_is_an_index ON posts(author)", [], [])
    SQL.query(sql, "INSERT INTO posts VALUES ('jazzyb', 2, 'short statement', 'Longer, more detailed statement.')", [], [])

    # alter the table
    alter = {:alter, table(:posts),
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:modify, :price, :numeric, [precision: 8, scale: 2]},
                {:remove, :summary}]}
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, SQL.execute_ddl(alter), [], [])

    # verify the schema has been updated
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, "SELECT sql FROM sqlite_master WHERE name = 'posts' AND type = 'table'", [], [])
    assert row[:sql] == ~s{CREATE TABLE "posts" ("author" TEXT, "price" NUMERIC, "body" TEXT, "title" TEXT DEFAULT 'Untitled' NOT NULL)}

    # verify the values have been preserved
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, "SELECT * FROM posts", [], [])
    assert "jazzyb" == Keyword.get(row, :author)
    assert 2 == Keyword.get(row, :price)
    assert "Longer, more detailed statement." == Keyword.get(row, :body)
    assert "Untitled" == Keyword.get(row, :title)
    assert not Keyword.has_key?(row, :summary)

    # verify the index has been preserved
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, "SELECT sql FROM sqlite_master WHERE tbl_name = 'posts' AND type = 'index'", [], [])
    assert row[:sql] == "CREATE INDEX this_is_an_index ON posts(author)"
  end

  ## Tests stolen from PostgreSQL adapter:

  import Ecto.Query

  alias Ecto.Queryable

  defmodule Model do
    use Ecto.Model

    schema "model" do
      field :x, :integer
      field :y, :integer

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

  defp normalize(query) do
    {query, _params} = Ecto.Query.Planner.prepare(query, [])
    Ecto.Query.Planner.normalize(query, [], [])
  end

  test "from" do
    query = Model |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
  end

  test "from without model" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}
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
      assert SQL.all(query)
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
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 WHERE ( m0."x" = 42 ) AND ( m0."y" != 43 )}
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
      assert SQL.all(query)
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
    assert SQL.all(query) == ~s{SELECT NOT ( m0."x" IS NULL ) FROM "model" AS m0}
  end

  test "fragments" do
    query = Model |> select([r], fragment("ltrim(?)", r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT ltrim(m0."x") FROM "model" AS m0}

    value = 13
    query = Model |> select([r], fragment("ltrim(?, ?)", r.x, ^value)) |> normalize
    assert SQL.all(query) == ~s{SELECT ltrim(m0."x", ?) FROM "model" AS m0}
  end

  test "literals" do
    query = Model |> select([], nil) |> normalize
    assert SQL.all(query) == ~s{SELECT NULL FROM "model" AS m0}

    query = Model |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0}

    query = Model |> select([], false) |> normalize
    assert SQL.all(query) == ~s{SELECT FALSE FROM "model" AS m0}

    query = Model |> select([], "abc") |> normalize
    assert SQL.all(query) == ~s{SELECT 'abc' FROM "model" AS m0}

    query = Model |> select([], 123) |> normalize
    assert SQL.all(query) == ~s{SELECT 123 FROM "model" AS m0}

    query = Model |> select([], 123.0) |> normalize
    assert SQL.all(query) == ~s{SELECT 123.0 FROM "model" AS m0}
  end

#  test "tagged type" do
#    query = Model |> select([], type(^<<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>, :uuid)) |> normalize
#    assert SQL.all(query) == ~s{SELECT $1::uuid FROM "model" AS m0}
#
#    query = Model |> select([], type(^1, Custom.Permalink)) |> normalize
#    assert SQL.all(query) == ~s{SELECT $1::integer FROM "model" AS m0}
#
#    query = Model |> select([], type(^[1,2,3], {:array, Custom.Permalink})) |> normalize
#    assert SQL.all(query) == ~s{SELECT $1::integer[] FROM "model" AS m0}
#  end
#
#  test "nested expressions" do
#    z = 123
#    query = from(r in Model, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
#    assert SQL.all(query) == ~s{SELECT ((m0."x" > 0) AND (m0."y" > $1)) OR TRUE FROM "model" AS m0}
#  end
#
#  test "in expression" do
#    query = Model |> select([e], 1 in []) |> normalize
#    assert SQL.all(query) == ~s{SELECT false FROM "model" AS m0}
#
#    query = Model |> select([e], 1 in [1,e.x,3]) |> normalize
#    assert SQL.all(query) == ~s{SELECT 1 IN (1,m0."x",3) FROM "model" AS m0}
#
#    query = Model |> select([e], 1 in ^[]) |> normalize
#    assert SQL.all(query) == ~s{SELECT false FROM "model" AS m0}
#
#    query = Model |> select([e], 1 in ^[1, 2, 3]) |> normalize
#    assert SQL.all(query) == ~s{SELECT 1 IN ($1,$2,$3) FROM "model" AS m0}
#
#    query = Model |> select([e], 1 in [1, ^2, 3]) |> normalize
#    assert SQL.all(query) == ~s{SELECT 1 IN (1,$1,3) FROM "model" AS m0}
#  end
#
#  test "having" do
#    query = Model |> having([p], p.x == p.x) |> select([], 0) |> normalize
#    assert SQL.all(query) == ~s{SELECT 0 FROM "model" AS m0 HAVING (m0."x" = m0."x")}
#
#    query = Model |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], 0) |> normalize
#    assert SQL.all(query) == ~s{SELECT 0 FROM "model" AS m0 HAVING (m0."x" = m0."x") AND (m0."y" = m0."y")}
#  end
#
#  test "group by" do
#    query = Model |> group_by([r], r.x) |> select([r], r.x) |> normalize
#    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x"}
#
#    query = Model |> group_by([r], 2) |> select([r], r.x) |> normalize
#    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY 2}
#
#    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
#    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x", m0."y"}
#
#    query = Model |> group_by([r], []) |> select([r], r.x) |> normalize
#    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
#  end
#
#  test "arrays and sigils" do
#    query = Model |> select([], fragment("?", [1, 2, 3])) |> normalize
#    assert SQL.all(query) == ~s{SELECT ARRAY[1,2,3] FROM "model" AS m0}
#
#    query = Model |> select([], fragment("?", ~w(abc def))) |> normalize
#    assert SQL.all(query) == ~s{SELECT ARRAY['abc','def'] FROM "model" AS m0}
#  end
#
#  test "interpolated values" do
#    query = Model
#            |> select([], ^0)
#            |> join(:inner, [], Model2, ^true)
#            |> join(:inner, [], Model2, ^false)
#            |> where([], ^true)
#            |> where([], ^false)
#            |> group_by([], ^1)
#            |> group_by([], ^2)
#            |> having([], ^true)
#            |> having([], ^false)
#            |> order_by([], fragment("?", ^3))
#            |> order_by([], ^:x)
#            |> limit([], ^4)
#            |> offset([], ^5)
#            |> normalize
#
#    result =
#      "SELECT $1 FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON $2 " <>
#      "INNER JOIN \"model2\" AS m2 ON $3 WHERE ($4) AND ($5) " <>
#      "GROUP BY $6, $7 HAVING ($8) AND ($9) " <>
#      "ORDER BY $10, m0.\"x\" LIMIT $11 OFFSET $12"
#
#    assert SQL.all(query) == String.rstrip(result)
#  end
end
