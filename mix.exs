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
    [{:backoff, git: "https://github.com/scouten/backoff.git", ref: "8f10cb83b5fbc2401e6a06b341417cad4c632f34", override: true},
     {:connection, "~> 1.0.2", override: true},
     {:coverex, "~> 1.4.11", only: :test},
     {:db_connection, "0.2.5", override: true},
     {:decimal, "1.1.1", override: true},
     {:esqlite, git: "https://github.com/mmzeeman/esqlite", ref: "c1ba116de470aadc23e7ae582c961b2ced13d306", override: true},
     {:ex_doc, "~> 0.14.5", only: :dev},
     {:ecto, git: "https://github.com/scouten/ecto.git", ref: "eed7e927088ca5f024017ef2d7a5e48668cad216"},
     {:poison, "1.5.2", override: true, optional: true},
     {:postgrex, "~> 0.11.1", optional: true},
     {:sbroker, "~> 1.0", override: true},
     {:sqlitex, git: "https://github.com/scouten/sqlitex.git", ref: "8f1dcd4107cd99ca0687bf870b914e44a467722d", override: true}]
  end

  defp description, do: "SQLite3 adapter for Ecto2 (not yet working)"

  defp package do
    [maintainers: ["Jason M Barnes", "Eric Scouten"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/scouten/sqlite_ecto2"}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/sqlite_db_connection/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_paths, do: ["integration/sqlite", "test"]
end
