# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule PcgMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :pcg_mcp,
      version: "1.0.0-dev2",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps(),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      test_coverage: [
        summary: [threshold: 70],
        ignore_modules: [
          PcgMcp.NativeService,
          Mix.Tasks.Mcp.Server,
          PcgMcp.HttpPlugWrapper,
          PcgMcp.HttpServer,
          PcgMcp.Router
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {PcgMcp.Application, []},
      applications: [:logger, :ex_mcp, :jason, :plug_cowboy, :briefly]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_mcp, git: "https://github.com/fire/ex_mcp.git", branch: "master"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      {:briefly, "~> 0.4"},
      {:nx_image, "~> 0.1.2"},
      {:dialyxir, "~> 1.4.6", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  # Release configuration
  defp releases do
    [
      pcg_mcp: [
        include_executables_for: [:unix],
        applications: [pcg_mcp: :permanent]
      ]
    ]
  end
end

