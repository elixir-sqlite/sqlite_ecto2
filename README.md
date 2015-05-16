Sqlite.Ecto [![Build Status](https://travis-ci.org/jazzyb/sqlite_ecto.svg?branch=master "Build Status")](https://travis-ci.org/jazzyb/sqlite_ecto)
==========

`Sqlite.Ecto` is a SQLite3 Adapter for Ecto.

## Example

Here is an example usage:

```elixir
# In your config/config.exs file
config :my_app, Repo, database: "db/ecto_simple.sqlite3"

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
  [{:sqlite_ecto, "~> 0.1"}]
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
