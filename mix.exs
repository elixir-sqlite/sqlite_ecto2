defmodule Sqlite.Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :sqlite_ecto2,
     version: "2.0.0-dev.1",
     name: "Sqlite.Ecto2",
     elixir: "~> 1.2",
     deps: deps,

     # testing
     build_per_environment: false,
     test_paths: test_paths(Mix.env),
     aliases: ["test.all": &test_all/1,
               "test.integration": &test_integration/1],
     preferred_cli_env: ["test.all": :test],
     test_coverage: [tool: Coverex.Task, coveralls: true],

     # hex
     description: description,
     package: package,

     # docs
     docs: [main: Sqlite.Ecto]]
  end

  # Configuration for the OTP application
  def application do
    [applications: [:logger, :ecto]]
  end

  # Dependencies
  defp deps do
    [{:coverex, "~> 1.4.11", only: :coverage},
     {:ex_doc, "~> 0.14.5", only: :dev},
     {:ecto, git: "https://github.com/scouten/ecto.git", ref: "79506d286d7edd11e3acff75da2904fc9b9259a1"},
     {:poison, "~> 1.0"},
     {:sqlitex, git: "https://github.com/scouten/sqlitex.git", ref: "c997c613a69ece59d8dd6b7e7ee557d4c4a1c709"}]
  end

  defp description, do: "SQLite3 adapter for Ecto2 (not yet working)"

  defp package do
    [maintainers: ["Jason M Barnes", "Eric Scouten"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/scouten/sqlite_ecto2"}]
  end

  defp test_paths(:coverage), do: ["integration/sqlite", "test"]
  defp test_paths(:integration), do: ["integration/sqlite"]
  defp test_paths(_), do: ["test"]

  defp test_integration(args) do
    args = if IO.ANSI.enabled?, do: ["--color" | args], else: ["--no-color" | args]
    System.cmd "mix", ["test" | args], into: IO.binstream(:stdio, :line),
                                       env: [{"MIX_ENV", "integration"}]
  end

  defp test_all(args) do
    Mix.Task.run "test", args
    {_, res} = test_integration(args)
    if res != 0, do: exit {:shutdown, 1}
  end
end
