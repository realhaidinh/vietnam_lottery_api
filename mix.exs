defmodule LotteryApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :lottery_api,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LotteryApi.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:req, "~> 0.5.0"},
      {:floki, "~> 0.37.0"},
      {:html5ever, "~> 0.15.0"},
      {:tzdata, "~> 1.1"},
      {:bandit, "~> 1.6"}
    ]
  end
end
