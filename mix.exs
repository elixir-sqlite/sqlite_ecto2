defmodule Sqlite.Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :sqlite_ecto,
     version: "0.0.2",
     name: "Sqlite.Ecto",
     elixir: "~> 1.0",
     deps: deps,

     # testing
     test_paths: test_paths(Mix.env),
     aliases: ["test.all": &test_all/1,
               "test.integration": &test_integration/1],
     preferred_cli_env: ["test.integration": :test,
                         "test.all": :test],

     # hex
     description: description,
     package: package,

     # docs
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
     {:ecto, "~> 0.11"},
     #{:sqlitex, "~> 0.3"}]
     {:sqlitex, path: "/home/jazzyb/share/sqlitex"}]
  end

  defp description, do: "SQLite3 adapter for Ecto"

  defp package do
    [contributors: ["Jason M Barnes"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/jazzyb/sqlite_ecto"}]
  end

  defp test_paths(:integration), do: ["integration"]
  defp test_paths(_), do: ["test"]

  defp test_integration(args) do
    args = if IO.ANSI.enabled?, do: ["--color" | args], else: ["--no-color" | args]
    System.cmd "mix", ["test" | args], into: IO.binstream(:stdio, :line),
                                       env: [{"MIX_ENV", "integration"}]
  end

  defp test_all(args) do
    Mix.Task.run "test", args
    test_integration(args)
  end
end
