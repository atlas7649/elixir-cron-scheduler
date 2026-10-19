defmodule Cronyx.MixProject do
  use Mix.Project

  def project do
    [
      app: :cronyx,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Cronyx.CLI],
      deps: []
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end
end
