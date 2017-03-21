defmodule Sqlite.Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :sqlite_ecto2,
     version: "2.0.0-dev.1",
     name: "Sqlite.Ecto2",
     elixir: "~> 1.3.4 or ~> 1.4",
     elixirc_options: [warnings_as_errors: true],
     deps: deps(),
     elixirc_paths: elixirc_paths(Mix.env),

     # testing
     build_per_environment: false,
     test_paths: test_paths(),
     test_coverage: [tool: Coverex.Task, coveralls: true],

     # hex
     description: description(),
     package: package(),

     # docs
     docs: [main: Sqlite.Ecto]]
  end

  # Configuration for the OTP application
  def application do
    [applications: [:db_connection, :ecto, :logger],
     mod: {Sqlite.DbConnection.App, []}]
  end

  # Dependencies
  defp deps do
    [{:connection, "~> 1.0.3"},
     {:coverex, "~> 1.4.11", only: :test},
     {:db_connection, "~> 1.1.0", optional: true},
     {:decimal, "~> 1.2"},
     {:esqlite, "~> 0.2.3"},
     {:ex_doc, "~> 0.15", only: :dev},
     {:ecto, "~> 2.1.0"},
     {:poison, "~> 2.2", optional: true},
     {:postgrex, "~> 0.13.0", optional: true},
     {:sbroker, "~> 1.0"},
     {:sqlitex, "~> 1.3.1"}]
  end

  defp description, do: "SQLite3 adapter for Ecto2"

  defp package do
    [maintainers: ["Eric Scouten", "Jason M Barnes"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/scouten/sqlite_ecto2"}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/sqlite_db_connection/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_paths, do: ["integration/sqlite", "test"]
end
