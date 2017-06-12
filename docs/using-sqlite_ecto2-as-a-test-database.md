## Introduction

SQLite isn't the best choice of a database for most production applications.  However, SQLite *can* make a great stub database for unit testing.  This short article will explain how to setup the Blog application from the [Basic `sqlite_ecto2` Tutorial](tutorial.md) with a production PostgreSQL database and a separate test SQLite database.

(**NOTE:**  Although it is not required to read the basic tutorial first, this article will assume some familiarity with the general layout of that source code.)

## Caveat

There are enough differences between how the Postgres and SQLite adapters work, even for functionality that they share, that you may want to avoid using SQLite for your development database if it is not also your production database.  Having said that, SQLite might still be useful as a mock resource for some unit tests -- in which case this article may still have merit.  See [this StackOverflow discussion](http://stackoverflow.com/questions/10859186/sqlite-in-development-postgresql-in-production-why-not) and decide for yourself.

## Background:  The Mix Environment

Before we start, let's make sure we understand the Mix environment.  Mix provides three different environments to prepare and run your application for.  They are:
* `:dev` -- the default environment
* `:test` -- the environment in which `mix test` runs
* `:prod` -- the environment and configuration with which your production application will run

By setting the value of the `MIX_ENV` environment variable, we can prepare and run our Elixir application with different configurations.  For example, while `mix test` will run our tests using the test database by default, `MIX_ENV=prod mix test` will run the same tests against a production database we have configured.

## Configuration

Let's start with the config files.  If your application is small or you've just started development, you probably have all your application configuration in the default `config/config.exs` file.  We are going to have this file import different configuration files based on the value of the `MIX_ENV` environment variable.  Edit your `config/config.exs` file like so:

```elixir
use Mix.Config

# ... general, environment-independent configuration goes here ...

import_config "#{Mix.env}.exs"
```

The `import_config` statement should go to the bottom of the file so that it will overwrite any of the generic configuration above it.  Next we create separate config files for each of the different environments.

(**NOTE:**  We are ignoring `:dev` for the remainder of this article, but you should account for it in your own configs.)

Create `config/test.exs`:
```elixir
use Mix.Config

config :blog, :ecto_adapter, Sqlite.Ecto2

config :blog, Blog.Repo,
  adapter: Application.get_env(:blog, :ecto_adapter),
  database: "test/blog.sqlite3",
  size: 1,
  max_overflow: 0
```

And create `config/prod.exs`:
```elixir
use Mix.Config

config :blog, :ecto_adapter, Ecto.Adapters.Postgres

config :blog, Blog.Repo,
  adapter: Application.get_env(:blog, :ecto_adapter),
  database: "blog",
  username: "postgres",
  password: "postgres"
```

Notice that in each of the configs we created a different application environment variable called `:ecto_adapter`.  Now wherever we had hardcoded our adapter, we can instead access different adapters based on our environment.  Edit the Repo at `lib/blog/repo.ex` to do just that:

```elixir
defmodule Blog.Repo do
  use Ecto.Repo, otp_app: :blog,
                 adapter: Application.get_env(:blog, :ecto_adapter)
end
```

Finally, all that remains is to update `mix.exs` with our new environmental configuration.  Change the `application/0` function to include different projects based on the environment:

```elixir
  def application do
    case Mix.env do
      :test -> [applications: [:logger, :sqlite_ecto2, :ecto]]
      :prod -> [applications: [:logger, :postgrex, :ecto]]
    end
  end
```

And change the `deps/0` function to set different dependencies depending on environment:

```elixir
  defp deps do
    [{:sqlite_ecto2, "~> 2.0.0-dev.8", only: :test},
     {:postgrex, ">= 0.0.0", only: :prod},
     {:ecto, "~> 2.1.0"}]
  end
```

You may need to run `MIX_ENV=prod mix deps.get` afterwards to install the Postgrex dependency.

Provided you have the PostgreSQL server properly configured, you can run the following commands in turn to run your tests against your production database:

```
$ export MIX_ENV=prod
$ mix ecto.create
$ mix ecto.migrate
$ mix test
```

The `export` line sets the environment variable without having to insert `MIX_ENV=prod ` before every command.  Replace `prod` with `test` to run against the SQLite test database.

That's all it takes to use different database adapters for testing and production!  Now if you desire, you can test or develop locally with SQLite and then use a PostgreSQL database in production without ever having to change your code.  SQLite even provides support for in-memory databases, so depending on your use-case, you may not even need the `blog.sqlite3` test file for your unit tests.
