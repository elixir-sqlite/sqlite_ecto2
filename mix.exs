defmodule Sqlite.Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :sqlite_ecto,
     version: "0.0.1",
     name: "Sqlite.Ecto",
     elixir: "~> 1.0",
     deps: deps,
     description: description,
     package: package,
     docs: [main: Sqlite.Ecto]]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [{:earmark, "~> 0.1", only: :dev},
     {:ex_doc, "~> 0.7", only: :dev},
     {:ecto, "0.8.1"},
     {:sqlitex, git: "https://github.com/jazzyb/sqlitex.git"}]
  end

  defp description, do: "SQLite adapter for Ecto"

  defp package do
    [contributors: ["Jason M Barnes"],
      licenses: [],
      links: %{"Github" => "https://github.com/jazzyb/sqlite_ecto"}]
  end
end
