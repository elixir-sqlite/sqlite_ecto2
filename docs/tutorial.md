## Introduction

`sqlite_ecto2` is an Ecto adapter which helps you to interact with SQLite databases.

This very brief tutorial will walk you through the basics of configuring and using Ecto with SQLite.  We are going to setup a very basic schema that one might need for a blog.  The following assumes you already have some familiarity with Elixir development.

**PLEASE NOTE** that the following schema, configuration, and associated tests are in no way secure or robust and should not be used for a production database.  They are only being used to demonstrate some of the features of Ecto.

## Configuring Ecto

Let's create our new Elixir code with mix:  `mix new blog`.  Change into the new directory and update the `mix.exs` file to use Ecto and SQLite:

```elixir
def application do
  [applications: [:logger, :sqlite_ecto2, :ecto]]
end

defp deps do
  [{:sqlite_ecto2, "~> 2.0.0-dev.8"}]
end
```

Now make sure you can download your dependencies, compile, and setup your Ecto repository:
```
$ mix deps.get
$ mix ecto.gen.repo -r Blog.Repo
```

Edit the Blog.Repo module in `lib/blog/repo.ex` to use the `sqlite_ecto2` adapter:
```elixir
defmodule Blog.Repo do
  use Ecto.Repo, otp_app: :blog, adapter: Sqlite.Ecto2
end
```

And change the default PostgreSQL configuration in `config/config.exs` to the following:
```elixir
config :blog, Blog.Repo,
  adapter: Sqlite.Ecto2,
  database: "blog.sqlite3"

config :blog, ecto_repos: [Blog.Repo]
```

In this example `blog.sqlite3` is the SQLite file that will store our blog's database.  The file will be created in the
top-level directory.  You can change it to any file path you like. Adding the `:ecto_repos` key with `[Blog.Repo]` tells
Ecto's `mix` tasks about the `Blog.Repo` database.

Fill in `lib/blog.ex` to start the Ecto repo when the application starts:

```elixir
defmodule Blog do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      Blog.Repo,
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Blog.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

If `Elixir < 1.5.0`:
```elixir
...
    children = [
      worker(Blog.Repo, [])
    ]
...
```

Run `mix ecto.create`.  Verify that the SQLite database has been created at `blog.sqlite3` or wherever you have configured your database to be written.

## Ecto Models

Now that we have our database configured and created, we can create tables to hold our data.  Let's start by creating a "users" database table.  Run `mix ecto.gen.migration create_users`.  This will create a file at `priv/repo/migrations/TIMESTAMP_create_users.exs` where `TIMESTAMP` is the particular date and time you ran the migration command.  Edit this file to create the new table:

```elixir
defmodule Blog.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :email, :string
      timestamps()
    end
  end
end
```

This migration will generate a `users` table with columns for the user's name and email address.  The `timestamps()` statement will create timestamps to mark when entries have been inserted or updated.

Run `mix ecto.migrate` to create the new table.  You can verify the migration with the following:
```
$ sqlite3 blog.sqlite3 .schema
CREATE TABLE "schema_migrations" ("version" BIGINT PRIMARY KEY, "inserted_at" NAIVE_DATETIME);
CREATE TABLE "users" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "name" TEXT, "email" TEXT, "inserted_at" NAIVE_DATETIME NOT NULL, "updated_at" NAIVE_DATETIME NOT NULL);
```

Before we can use the table.  We have to write an Ecto model to encapsulate it.  Edit `lib/blog/user.ex` to define the model:
```elixir
defmodule Blog.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    timestamps()
  end
end
```

Notice how it resembles the migration we just wrote.  Let's quickly make sure the model is working with iex:

```
$ iex -S mix
Erlang/OTP 19 [erts-8.3] [source] [64-bit] [smp:4:4] [async-threads:10] [hipe] [kernel-poll:false] [dtrace]

Compiling 1 file (.ex)
Generated blog app
Interactive Elixir (1.4.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> Blog.start(nil, nil)
{:ok, #PID<0.196.0>}
iex(2)> Blog.Repo.insert(%Blog.User{name: "jazzyb", email: "anonymous@example.com"})

18:05:16.119 [debug] QUERY OK db=14.7ms
INSERT INTO "users" ("email","name","inserted_at","updated_at") VALUES (?1,?2,?3,?4) ;--RETURNING ON INSERT "users","id" ["anonymous@example.com", "jazzyb", {{2017, 3, 31}, {8, 5, 16, 78423}}, {{2017, 3, 31}, {8, 5, 16, 86372}}]
{:ok,
 %Blog.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
  email: "anonymous@example.com", id: 1,
  inserted_at: ~N[2017-03-31 08:05:16.078423], name: "jazzyb",
  updated_at: ~N[2017-03-31 08:05:16.086372]}}
iex(3)> import Ecto.Query
Ecto.Query
iex(4)> Blog.Repo.all(Blog.User |> select([user], user.name))

18:07:32.472 [debug] QUERY OK source="users" db=0.8ms queue=0.1ms
SELECT u0."name" FROM "users" AS u0 []
["jazzyb"]
iex(5)>
```

In the above output, we start the Blog.Repo (1), create a new user `jazzyb` (2), and then verify that we can query that user from the database (4).

## Associations

Now that we have some basic understanding of models, let's complicate the schema a little bit.  If we want to create a blog, we have to have some posts that users can write.  Let's create a new migration to generate the posts table with `mix ecto.gen.migration create_posts`.  Edit the resulting file:

```elixir
defmodule Blog.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string
      add :body, :string
      add :user_id, references(:users)
      timestamps()
    end
  end
end
```

And run `mix ecto.migrate` to create the posts table, then write the Post model to `lib/blog/post.ex` like so:

```elixir
defmodule Blog.Post do
  use Ecto.Schema
  alias Blog.User

  schema "posts" do
    belongs_to :user, User
    field :title, :string
    field :body, :string
    timestamps()
  end
end
```

Notice that in both the migration and the model, we define an association that "posts belong to users".  We also need to define a reverse association that says "users have multiple posts".  Edit the User model at `lib/blog/user.ex` to add the association with the Post model:

```elixir
defmodule Blog.User do
  use Ecto.Schema
  alias Blog.Post

  schema "users" do
    has_many :posts, Post
    field :name, :string
    field :email, :string
    timestamps()
  end
end
```

The models are getting more complicated, so let's write a test to make sure we can add entries to our repo and make sure everything is working as it should.  Edit `test/blog_test.exs` and add the following:

```elixir
defmodule BlogTest do
  use ExUnit.Case

  alias Blog.Repo
  alias Blog.User
  alias Blog.Post

  import Ecto.Query

  setup_all do
    {:ok, pid} = Blog.start(nil, nil)
    {:ok, [pid: pid]}
  end

  setup do
    on_exit fn ->
      Repo.delete_all(Post)
      Repo.delete_all(User)
    end
  end

  test "that everything works as it should" do
    # assert we can insert and query a user
    {:ok, author} = %User{name: "ludwig_wittgenstein", email: "sharp_witt@example.de"} |> Repo.insert
    ["ludwig_wittgenstein"] = User |> select([user], user.name) |> Repo.all

    # assert we can insert posts
    Repo.insert(%Post{user_id: author.id, title: "Tractatus", body: "Nothing to say."})
    Repo.insert(%Post{user_id: author.id, title: "Tractatus", body: "Nothing else to say."})
    Repo.insert(%Post{user_id: author.id, title: "Tractatus", body: "Nothing more to say."})
    assert List.duplicate("Tractatus", 3) == Post
                                             |> select([post], post.title)
                                             |> where([post], post.user_id == ^author.id)
                                             |> Repo.all

    # ... and one more post and user for good measure
    {:ok, user} = %User{name: "john_cusack", email: "cusack66@example.com"} |> Repo.insert
    Repo.insert(%Post{user_id: user.id, title: "Trashy 80's Romance", body: "Say anything."})
    assert ["Trashy 80's Romance"] == Post
                                      |> select([post], post.title)
                                      |> where([post], post.user_id == ^user.id)
                                      |> Repo.all
  end
end
```

This test shows how to insert entries into your database and query it for information.  Run it with `mix test` to see that everything is working alright.  **NOTE**  You may need to re-migrate the database if you run into errors involving entries you've added in the past.  If this is the case, just do the following to delete the old database and create a new pristine one:

```
$ mix ecto.drop
$ mix ecto.create
$ mix ecto.migrate
```

Now that we know everything works as it should, let's see what we can do with the associations we defined between User and Post.  Write a new assertion at the end of the test which queries for all the posts of a particular user:

```elixir
    # preload user posts
    query = from u in User, where: u.id == ^author.id, preload: [:posts]
    titles = query
    |> Repo.all
    |> Enum.map(fn user -> user.posts end)
    |> List.flatten
    |> Enum.map(fn post -> post.title end)
    assert List.duplicate("Tractatus", 3) == titles
```

In the example above, the `preload` command in the query fills in the `posts` value when we query for a user.  Then the assertion does some overly complicated code to get the titles of all of user `author`'s posts.  The associations we defined earlier are what give us access to the posts through user.

## Making Changes to the Database

What if we want to add values for our users, like, requiring passwords to access the blog?  We can add columns to tables using migrations.  Create a new migration with `mix ecto.gen.migration user_passwords` and edit the result:

```elixir
defmodule Blog.Repo.Migrations.UserPasswords do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :password, :string, [default: "CHANGE_ME", null: false]
    end
  end
end
```

Run `mix ecto.migrate` and verify the new column has been added to the table.  **NOTE**  `sqlite_ecto2` can only add columns to tables -- it cannot remove or modify columns once they have been created.

Before we can use the new table we need to update our model.  The User model at `lib/blog/user.ex` should now look like the following:

```elixir
defmodule Blog.User do
  use Ecto.Schema
  alias Blog.Post

  schema "users" do
    has_many :posts, Post
    field :name, :string
    field :email, :string
    field :password, :string, [default: "CHANGE_ME", null: false]
    timestamps()
  end
end
```

Let's add a new assertion to our test case to verify we can update our users' passwords:

```elixir
    # update user password
    passwordChange = Ecto.Changeset.change(%User{id: author.id}, password: "leopoldine")
    Repo.update(passwordChange)
    assert ["leopoldine"] == User
                             |> select([user], user.password)
                             |> where([user], user.id == ^author.id)
                             |> Repo.all
```

We have another problem as our schema stands:  There is nothing preventing users from sharing the same username.  That could get very confusing.  We can fix that in Ecto by creating a unique index.  Run `mix ecto.gen.migration distinct_usernames` and edit the resulting file:

```elixir
defmodule Blog.Repo.Migrations.DistinctUsernames do
  use Ecto.Migration

  def change do
    create index(:users, [:name], unique: true)
  end
end
```

Run `mix ecto.migrate` to apply this migration. This creates a unique index on `users.name` that prevents two users from having the same username.  We can write another assertion to test this.  After `"ludwig_wittgenstein"` is defined in our test case, verify that we can't create another user with the same name:

```elixir
    # prevent usernames from overlapping
    assert_raise Sqlite.DbConnection.Error, "constraint: UNIQUE constraint failed: users.name", fn ->
      %User{name: "ludwig_wittgenstein", password: "NOT_THE_REAL_USER"} |> Repo.insert
    end
```
