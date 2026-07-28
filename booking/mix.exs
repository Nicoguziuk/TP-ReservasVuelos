defmodule Booking.MixProject do
  use Mix.Project

  def project do
    [
      app: :booking,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Booking.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Servidor HTTP/WebSocket: comunicación en tiempo real con el frontend.
      {:cowboy, "~> 2.16"},
      # (De)serialización JSON del protocolo WebSocket.
      {:jason, "~> 1.4"}
    ]
  end

  # Atajos de tareas. `mix check` = verificación previa al commit
  # (formato correcto + compilación sin warnings). Lo usa el hook .githooks/pre-commit.
  defp aliases do
    [check: ["format --check-formatted", "compile --warnings-as-errors"]]
  end
end
