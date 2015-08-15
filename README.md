Sqlite.Ecto [![Build Status](https://travis-ci.org/jazzyb/sqlite_ecto.svg?branch=master "Build Status")](https://travis-ci.org/jazzyb/sqlite_ecto)
==========

`Sqlite.Ecto` is a SQLite3 Adapter for Ecto.

Read [the tutorial](https://github.com/jazzyb/sqlite_ecto/wiki/Basic-Sqlite.Ecto-Tutorial)
for a detailed example of how to setup and use a SQLite repo with Ecto, or
just check-out the CliffsNotes in the sections below if you want to get
started quickly.

## Dependencies

`Sqlite.Ecto` relies on [Sqlitex](https://github.com/mmmries/sqlitex) and
[esqlite](https://github.com/mmzeeman/esqlite).  Since esqlite uses
Erlang NIFs, you will need a valid C compiler to build the library.

## Example

Here is an example usage:

```elixir
# In your config/config.exs file
config :my_app, Repo,
  adapter: Sqlite.Ecto,
  database: "ecto_simple.sqlite3"

# In your application code
defmodule Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Sqlite.Ecto
end

defmodule Weather do
  use Ecto.Model

  schema "weather" do
    field :city     # Defaults to type :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end

defmodule Simple do
  import Ecto.Query

  def sample_query do
    query = from w in Weather,
          where: w.prcp > 0 or is_nil(w.prcp),
         select: w
    Repo.all(query)
  end
end
```

## Usage

Add `Sqlite.Ecto` as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:sqlite_ecto, "~> 0.5.0"}]
end
```

You should also update your applications list to include both projects:
```elixir
def application do
  [applications: [:logger, :sqlite_ecto, :ecto]]
end
```

To use the adapter in your repo:
```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Sqlite.Ecto
end
```

## Ignored Ecto Constraints

There are a few Ecto options which `Sqlite.Ecto` silently ignores because
SQLite does not support them and raising an error on them does not make sense:
* Most column options will ignore `size`, `precision`, and `scale` constraints
  on types because columns in SQLite have no types, and SQLite will not coerce
  any stored value.  Thus, all "strings" are `TEXT` and "numerics" will have
  arbitrary precision regardless of the declared column constraints.  The lone
  exception to this rule are Decimal types which accept `precision` and
  `scale` options because these constraints are handled in the driver
  software, not the SQLite database.
* If we are altering a table to add a `DATETIME` column with a `NOT NULL`
  constraint, SQLite will require a default value to be provided.  The only
  default value which would make sense in this situation is
  `CURRENT_TIMESTAMP`; however, when adding a column to a table, defaults must
  be constant values.  Therefore, in this situation the `NOT NULL` constraint
  will be ignored so that a default value does not need to be provided.
* When creating an index, `concurrently` and `using` values are silently
  ignored since they do not apply to SQLite.
