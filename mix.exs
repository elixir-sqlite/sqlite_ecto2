defmodule Sqlite.Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :sqlite_ecto2,
     version: "2.0.0-dev.1",
     name: "Sqlite.Ecto2",
     elixir: "~> 1.2",
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
    [applications: [:db_connection, :ecto, :logger]]
  end

  # Dependencies
  defp deps do
    [{:backoff, git: "https://github.com/scouten/backoff.git", ref: "8f10cb83b5fbc2401e6a06b341417cad4c632f34", override: true},
     {:connection, "~> 1.0.2", override: true},
     {:coverex, "~> 1.4.11", only: :test},
     {:db_connection, git: "https://github.com/fishcakez/db_connection", ref: "f438a1d66f238cc3d786f7aa7719fc36eaa283f2", override: true}, # version 0.1.7
     {:esqlite, git: "https://github.com/mmzeeman/esqlite", ref: "3f1ef40b9011276eb8bdc366c5ef1e25d79befa5", override: true},
     {:ex_doc, "~> 0.14.5", only: :dev},
     {:ecto, git: "https://github.com/scouten/ecto.git", ref: "8e2a9274fc5ab6b9b973ca50f2045c5b952617bf"},
     {:poison, "~> 1.0"},
     {:postgrex, git: "https://github.com/ericmj/postgrex.git", ref: "f773f8d4b88565aea435c6651b711ebfce74c9c2", override: true},
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
