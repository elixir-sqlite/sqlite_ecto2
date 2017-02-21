Sqlite.Ecto2 [![Build Status](https://travis-ci.org/scouten/sqlite_ecto2.svg?branch=master "Build Status")](https://travis-ci.org/scouten/sqlite_ecto2) [![Coverage Status](https://coveralls.io/repos/github/scouten/sqlite_ecto2/badge.svg?branch=master)](https://coveralls.io/github/scouten/sqlite_ecto2?branch=master)
==========

`Sqlite.Ecto2` is a SQLite3 Adapter for Ecto 2.x.

**IMPORTANT!!!!** This is an experimental port and does not work yet. It's entirely
possible that I'll play with this for a while and abandon it; it's also entirely
possible that it will lead to a viable adapter for Ecto 2.x.

If you're able to use Ecto 1.x, please look at [sqlite_ecto](https://github.com/jazzyb/sqlite_ecto),
on which this project is based.

The remainder of this README is held over from the 1.x version of this project.
If this project is ultimately successful, we'll revise the documentation accordingly.
For now, consider it inaccurate. Such is life on the bleeding edge.

## CALL FOR HELP

The test runs for sqlite_ecto2 are failing 5-10% of the time. I believe this is due
to https://github.com/mmzeeman/esqlite/issues/33. If you understand NIFs and can
propose a fix, that would be deeply appreciated. Thank you!

---

Read [the tutorial](https://github.com/jazzyb/sqlite_ecto/wiki/Basic-Sqlite.Ecto-Tutorial)
for a detailed example of how to setup and use a SQLite repo with Ecto, or
just check-out the CliffsNotes in the sections below if you want to get
started quickly.

## A WARNING About OTP 19.0.x

OTP 19.0.x appears to have a bug that causes it to
[misinterpret certain pattern matches](https://github.com/elixir-lang/elixir/issues/5586).
This causes the unit tests for sqlite_ecto to fail on some platforms when hosted
on OTP 19.0.x. This bug did not appear in OTP 18.0 and appears to have been fixed
for OTP 19.1. Consequently, we strongly advise you to avoid using OTP 19.0.x when
running sqlite_ecto, especially if using `decimal` value types.

Note that the Travis configuration for this repo specifically excludes OTP 19.0
for this reason.

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
  [{:sqlite_ecto2, "~> 2.0.0"}]
end
```

You should also update your applications list to include both projects:
```elixir
def application do
  [applications: [:logger, :sqlite_ecto2, :ecto]]
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

## Unsupported Ecto Constraints

The changeset functions
[`foreign_key_constraint/3`](http://hexdocs.pm/ecto/Ecto.Changeset.html#foreign_key_constraint/3)
and
[`unique_constraint/3`](http://hexdocs.pm/ecto/Ecto.Changeset.html#unique_constraint/3)
are not supported by `Sqlite.Ecto` because the underlying SQLite database does
not provide enough information when such constraints are violated to support
the features.

Note that SQLite **does** support both unique and foreign key constraints via
[`unique_index/3`](http://hexdocs.pm/ecto/Ecto.Migration.html#unique_index/3)
and [`references/2`](http://hexdocs.pm/ecto/Ecto.Migration.html#references/2),
respectively.  When such constraints are violated, they will raise
`Sqlite.Ecto.Error` exceptions.

## Silently Ignored Options

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
