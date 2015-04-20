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

  test "insert" do
    query = SQL.insert("model", [:x, :y], [:id])
    assert query == ~s{INSERT INTO "model" ("x","y") VALUES (?1,?2) ;--RETURNING ON INSERT model,id}

    query = SQL.insert("model", [], [:id])
    assert query == ~s{INSERT INTO "model" DEFAULT VALUES ;--RETURNING ON INSERT model,id}

    query = SQL.insert("model", [], [])
    assert query == ~s{INSERT INTO "model" DEFAULT VALUES}
  end

  test "update" do
    query = SQL.update("model", [:x, :y], [:id], [:x, :z])
    assert query == ~s{UPDATE "model" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE model,x,z}

    query = SQL.update("model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "model" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3}
  end

  test "delete" do
    query = SQL.delete("model", [:x, :y], [:z])
    assert query == ~s{DELETE FROM "model" WHERE "x" = ?1 AND "y" = ?2 ;--RETURNING ON DELETE model,z}

    query = SQL.delete("model", [:x, :y], [])
    assert query == ~s{DELETE FROM "model" WHERE "x" = ?1 AND "y" = ?2}
  end

  test "query", context do
    sql = context[:sql]
    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "CREATE TABLE model (id, x, y, z)", [], [])

    {:ok, %{num_rows: 0, rows: []}} = SQL.query(sql, "INSERT INTO model VALUES (1, 2, 3, 4)", [], [])
    query = ~s{UPDATE "model" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE model,x,z}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:foo, :bar, 1], [])
    assert row == [x: "foo", z: 4]

    query = ~s{INSERT INTO "model" VALUES (?1, ?2, ?3, ?4) ;--RETURNING ON INSERT model,id}
    {:ok, %{num_rows: 1, rows: [row]}} = SQL.query(sql, query, [:a, :b, :c, :d], [])
    assert row == [id: "a"]

    query = ~s{DELETE FROM "model" WHERE "id" = ?1 ;--RETURNING ON DELETE model,id,x,y,z}
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

  ## Helpers

  # return a unique temporary filename
  defp tempfilename do
    :erlang.now |> :random.seed
    1..10
    |> Enum.map(fn(_) -> :random.uniform(10) - 1 end)
    |> Enum.join
    |> (fn(name) -> "/tmp/test_" <> name <> ".db" end).()
  end
end
