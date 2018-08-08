defmodule Sqlite.Ecto2.Mixfile do
  use Mix.Project

  def project do
    [app: :sqlite_ecto2,
     version: "2.2.4",
     name: "Sqlite.Ecto2",
     elixir: "~> 1.4",
     elixirc_options: [warnings_as_errors: true],
     deps: deps(),
     elixirc_paths: elixirc_paths(Mix.env),

     # testing
     build_per_environment: false,
     test_paths: test_paths(),
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: [
       coveralls: :test,
       "coveralls.detail": :test,
       "coveralls.html": :test,
       "coveralls.circle": :test
     ],

     # hex
     description: description(),
     package: package(),

     # docs
     docs: [main: Sqlite.Ecto2]]
  end

  # Configuration for the OTP application
  def application do
    [extra_applications: [:logger],
     mod: {Sqlite.DbConnection.App, []}]
  end

  # Dependencies
  defp deps do
    [{:connection, "~> 1.0.3"},
     {:credo, "~> 0.10", only: [:dev, :test]},
     {:db_connection, "~> 1.1.0"},
     {:decimal, "~> 1.5"},
     {:excoveralls, "~> 0.9", only: :test},
     {:ex_doc, "~> 0.18", runtime: false, only: :docs},
     {:ecto, "~> 2.2"},
     {:inch_ex, "~> 1.0", only: :test},
     {:poison, "~> 2.2 or ~> 3.0", optional: true},
     {:postgrex, "~> 0.13", optional: true},
     {:sbroker, "~> 1.0"},
     {:sqlitex, "~> 1.3.2 or ~> 1.4"}]
  end

  defp description, do: "SQLite3 adapter for Ecto2"

  defp package do
    [maintainers: ["Eric Scouten", "Jason M Barnes", "Connor Rigby"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/Sqlite-Ecto/sqlite_ecto2"}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/sqlite_db_connection/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_paths, do: ["integration/sqlite", "test"]
end
