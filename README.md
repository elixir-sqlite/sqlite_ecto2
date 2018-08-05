[![CircleCI](https://circleci.com/gh/Sqlite-Ecto/sqlite_ecto2.svg?style=svg)](https://circleci.com/gh/Sqlite-Ecto/sqlite_ecto2)
[![Coverage Status](https://coveralls.io/repos/github/Sqlite-Ecto/sqlite_ecto2/badge.svg?branch=master)](https://coveralls.io/github/Sqlite-Ecto/sqlite_ecto2?branch=master)
[![Inline docs](http://inch-ci.org/github/Sqlite-Ecto/sqlite_ecto2.svg)](http://inch-ci.org/github/Sqlite-Ecto/sqlite_ecto2)
[![Hex.pm](https://img.shields.io/hexpm/v/sqlite_ecto2.svg)](https://hex.pm/packages/sqlite_ecto2)
[![Hex.pm](https://img.shields.io/hexpm/dt/sqlite_ecto2.svg)](https://hex.pm/packages/sqlite_ecto2)

# sqlite_ecto2

`sqlite_ecto2` is an Ecto 2.2.x adapter that allows you to create and maintain SQLite3 databases.

Read [the tutorial](./docs/tutorial.md) for a detailed example of how to setup and use a SQLite repo with Ecto, or just check-out the CliffsNotes in the sections below if you want to get started quickly.


## Ecto Version Compatibility

**IMPORTANT:** This release will _only_ work with Ecto 2.2.x. If you need compatibility with older versions of Ecto, please see:

* Ecto 2.1.x -> [`sqlite_ecto2` 2.0.x series](https://github.com/Sqlite-Ecto/sqlite_ecto2/tree/v2.0)
* Ecto 1.x -> [`sqlite_ecto` v1.x series](https://github.com/jazzyb/sqlite_ecto)


## When to Use `sqlite_ecto2`

*(and when not to use it ...)*

I strongly recommend reading [Appropriate Uses for SQLite](https://sqlite.org/whentouse.html) on the SQLite site itself. All of the considerations mentioned there apply to this library as well.

I will add one more: If there is *any* potential that more than one server node will need to write directly to the database at once (as often happens when using Elixir in a clustered environment), **do not use** `sqlite_ecto2`. Remember that there is no separate database process in this configuration, so each of your cluster nodes would be writing to its **own** copy of the database without any synchronization. You probably don't want that. Look for a true client/server database (Postgres, MySQL, or similar) in that case. SQLite's sweet spot is single-machine deployments (embedded, desktop, etc.).


## Help Wanted!

I would welcome any assistance in improving `sqlite_ecto2`. Some specific areas of concern:

**Documentation:**

* Newcomers, especially: I'd like feedback on the getting started content. What works and what is confusing? How can we make adopting this library more intuitive?
* I'd like to have at least one public example application.
* Add a more formal contribution guide, similar to the one from Ecto.

**Code quality:**

* Look for performance issues and address them. I'm particularly concerned about the temporary triggers used to implement value returns from `INSERT`, `UPDATE`, and `DELETE` queries. Can we avoid using those in some / most cases?
* Look for errors or other failures under stress.

This is by no means an exhaustive list. If you have other questions or concerns, please file issues or PRs. I do this in my spare time, so it may take me until I have time on an evening or weekend to reply, but I will appreciate any contribution.

When participating in or contributing to this project, please observe the [Elixir Code of Conduct](https://github.com/elixir-lang/elixir/blob/master/CODE_OF_CONDUCT.md).


## A WARNING About OTP 19.0.x

OTP 19.0.x appears to have a bug that causes it to [misinterpret certain pattern matches](https://github.com/elixir-lang/elixir/issues/5586). This causes the unit tests for sqlite_ecto to fail on some platforms when hosted on OTP 19.0.x. This bug did not appear in OTP 18.0 and appears to have been fixed for OTP 19.1. Consequently, I strongly advise you to avoid using OTP 19.0.x when running sqlite_ecto, especially if using `decimal` value types.

Note that the Travis configuration for this repo specifically excludes OTP 19.0 for this reason.

## Dependencies

This library makes use of [sqlite3](https://github.com/Sqlite-Ecto/sqlitex)
Since esqlite uses Erlang NIFs to incorporate SQLite, you will need a valid C compiler to build the library.

## Example

Here is an example usage:

```elixir
# In your config/config.exs file
config :my_app, Repo,
  adapter: Sqlite.Ecto2,
  database: "ecto_simple.sqlite3"

# In your application code
defmodule Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Sqlite.Ecto2
end

defmodule Weather do
  use Ecto.Schema

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

Add `sqlite_ecto2` as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:sqlite_ecto2, "~> 2.2"}]
end
```

To use the adapter in your repo:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Sqlite.Ecto2
end
```

## Incorrect (Surprising?) Implementation of Boolean Operators

SQLite's implementation of the boolean operator ('AND', 'OR', and 'NOT') return a integer values (0 or 1) since there is no boolean data type in SQLite. Certain Ecto code (and, in particular, some Ecto integration tests) expect actual boolean values to be returned. When `sqlite_ecto2` is returning a value directly from a column, it is possible to determine that the expected value is boolean and that mapping will occur. Once any mapping occurs (even as simple as `NOT column_value`), this mapping is no longer possible and you will get the integer value as presented by SQLite instead.

## Incomplete Ecto Constraint Implementation

Several Ecto constraints are not fully implemented in `sqlite_ecto2` because SQLite does not provide enough information in its error reporting to implement changeset validation properly in all cases. Specifically, some foreign key and uniqueness constraints are reported by raising `Sqlite.Ecto2.Error` exceptions instead of returning an Ecto changeset with the error detail.

## Silently Ignored Options

There are a few Ecto options which `sqlite_ecto2` silently ignores because SQLite does not support them and raising an error on them does not make sense:

* Most column options will ignore `size`, `precision`, and `scale` constraints on types because columns in SQLite have no types, and SQLite will not coerce any stored value. Thus, all "strings" are `TEXT` and "numerics" will have arbitrary precision regardless of the declared column constraints. The lone exception to this rule are Decimal types which accept `precision` and `scale` options because these constraints are handled in the driver software, not the SQLite database.

* If we are altering a table to add a `DATETIME` column with a `NOT NULL` constraint, SQLite will require a default value to be provided. The only default value which would make sense in this situation is `CURRENT_TIMESTAMP`; however, when adding a column to a table, defaults must be constant values. Therefore, in this situation the `NOT NULL` constraint will be ignored so that a default value does not need to be provided.

* When creating a table or index, the `comment` attribute is silently ignored. There is no reasonable place to store comments in SQLite schema.

* When creating an index, `concurrently` and `using` values are silently ignored since they do not apply to SQLite.
