defmodule Sqlite.Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :sqlite_ecto2,
     version: "2.0.0-dev.1",
     name: "Sqlite.Ecto2",
     elixir: "~> 1.2",
     elixirc_options: [warnings_as_errors: true],
     deps: deps(),

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
    [applications: [:logger, :ecto]]
  end

  # Dependencies
  defp deps do
    [{:coverex, "~> 1.4.11", only: :test},
     {:db_connection, git: "https://github.com/elixir-ecto/db_connection", ref: "625e42521e2b72f597c388daa6ecf5a90d7bd6e7", override: true}, # version 0.1.7
     {:ex_doc, "~> 0.14.5", only: :dev},
     {:ecto, git: "https://github.com/scouten/ecto.git", ref: "0a04003624aca5f2afdf15b0080d387ed36b7b72"},
     {:poison, "~> 1.0"},
     {:sqlitex, git: "https://github.com/scouten/sqlitex.git", ref: "c997c613a69ece59d8dd6b7e7ee557d4c4a1c709"}]
  end

  defp description, do: "SQLite3 adapter for Ecto2 (not yet working)"

  defp package do
    [maintainers: ["Jason M Barnes", "Eric Scouten"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/scouten/sqlite_ecto2"}]
  end

  defp test_paths(), do: ["integration/sqlite", "test"]
end
