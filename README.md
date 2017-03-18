# `sqlite_ecto2` [![Build Status](https://travis-ci.org/scouten/sqlite_ecto2.svg?branch=master "Build Status")](https://travis-ci.org/scouten/sqlite_ecto2) [![Coverage Status](https://coveralls.io/repos/github/scouten/sqlite_ecto2/badge.svg?branch=master)](https://coveralls.io/github/scouten/sqlite_ecto2?branch=master)

`sqlite_ecto2` is an Ecto 2.x adapter that allows you to create and maintain SQLite3 databases.

**IMPORTANT!!!!** This is a preliminary, bleeding-edge release. It is believed to work with all 2.0.x and 2.1.x versions of Ecto, but it has not been subjected to any serious performance analysis or stress test. I recommend against deploying this into any sort of production environment at this time.

If you're able to use Ecto 1.x, please look at [sqlite_ecto](https://github.com/jazzyb/sqlite_ecto), on which this project is based.

Read [the tutorial](https://github.com/jazzyb/sqlite_ecto/wiki/Basic-Sqlite.Ecto-Tutorial) (**TODO** Port this to sqlite_ecto2 repo) for a detailed example of how to setup and use a SQLite repo with Ecto, or just check-out the CliffsNotes in the sections below if you want to get started quickly.

## Help Wanted!

If you are willing to live on the bleeding edge, I would welcome any assistance in getting `sqlite_ecto2` to a production quality 2.0.0 release. Some specific areas of concern:

**Documentation:**

* We should review the original documentation from [`sqlite_ecto` version 1](https://github.com/jazzyb/sqlite_ecto) and its wiki, update them as appropriate, and bring them over. (FWIW I'm not a fan of the GitHub wiki; I'd prefer that any content be incorporated as Markdown files directly in this repo.)
* Newcomers, especially: I'd like feedback on the getting started content. What works and what is confusing? How can we make adopting this library more intuitive?
* I'd like to have at least one public example application.

**Code quality:**

* Improve code coverage.
* Look for performance issues and address them. I'm particularly concerned about the temporary triggers used to implement value returns from `INSERT`, `UPDATE`, and `DELETE` queries. Can we avoid using those in some / most cases?
* Look for errors or other failures under stress.
* Re-review Postgres and MySQL Ecto adapters and see if there are concepts that should be applied here.
* Add automated code-quality reviews from Credo, Dogma, and/or Ebert.

This is by no means an exhaustive list. If you have other questions or concerns, please file issues or PRs. I do this in my spare time, so it may take me until I have time on an evening or weekend to reply, but I will appreciate any contribution.


## A WARNING About OTP 19.0.x

OTP 19.0.x appears to have a bug that causes it to [misinterpret certain pattern matches](https://github.com/elixir-lang/elixir/issues/5586). This causes the unit tests for sqlite_ecto to fail on some platforms when hosted on OTP 19.0.x. This bug did not appear in OTP 18.0 and appears to have been fixed for OTP 19.1. Consequently, I strongly advise you to avoid using OTP 19.0.x when running sqlite_ecto, especially if using `decimal` value types.

Note that the Travis configuration for this repo specifically excludes OTP 19.0 for this reason.

## Dependencies

This library makes use of [Sqlitex](https://github.com/mmmries/sqlitex) and [esqlite](https://github.com/mmzeeman/esqlite).  Since esqlite uses Erlang NIFs to incorporate SQLite, you will need a valid C compiler to build the library.

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

Add `sqlite_ecto2` as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:sqlite_ecto2, "~> 2.0.0-dev.0"}]
end
```

If you are using Elixir 1.3, uou should also update your applications list to include `sqlite_ecto2` and `ecto`:

```elixir
def application do
  [applications: [:logger, :sqlite_ecto2, :ecto]]
end
```

With Elixir 1.4, you can do this or rely on application inference.

To use the adapter in your repo:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Sqlite.Ecto2
end
```

## Incomplete Ecto Constraint Implementation

Several Ecto constraints are not fully implemented in `sqlite_ecto2` because SQLite does not provide enough information in its error reporting to implement changeset validation properly in all cases. Specifically, some foreign key and uniqueness constraints are reported by raising `Sqlite.Ecto2.Error` exceptions instead of returning an Ecto changeset with the error detail.

## Silently Ignored Options

There are a few Ecto options which `Sqlite.Ecto` silently ignores because SQLite does not support them and raising an error on them does not make sense:

* Most column options will ignore `size`, `precision`, and `scale` constraints on types because columns in SQLite have no types, and SQLite will not coerce any stored value. Thus, all "strings" are `TEXT` and "numerics" will have arbitrary precision regardless of the declared column constraints. The lone exception to this rule are Decimal types which accept `precision` and `scale` options because these constraints are handled in the driver software, not the SQLite database.

* If we are altering a table to add a `DATETIME` column with a `NOT NULL` constraint, SQLite will require a default value to be provided. The only default value which would make sense in this situation is `CURRENT_TIMESTAMP`; however, when adding a column to a table, defaults must be constant values. Therefore, in this situation the `NOT NULL` constraint will be ignored so that a default value does not need to be provided.

* When creating an index, `concurrently` and `using` values are silently ignored since they do not apply to SQLite.
