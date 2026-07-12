defmodule Plato.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/SuperInstance/plato-engine-block-elixir"

  def project do
    [
      app: :plato,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Plato room runtime — BEAM/OTP actor model for marine vessel monitoring",
      package: package(),
      source_url: @source_url,
      docs: docs()
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

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
