defmodule Plato.MixProject do
  use Mix.Project

  def project do
    [
      app: :plato,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Plato room runtime — BEAM/OTP actor model for marine vessel monitoring"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Plato.Application, []}
    ]
  end

  defp deps do
    []
  end
end
