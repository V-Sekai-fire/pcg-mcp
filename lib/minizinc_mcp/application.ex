# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Application do
  @moduledoc false

  use Application

  @spec start(:normal | :permanent | :transient, any()) :: {:ok, pid()}
  @impl true
  def start(_type, _args) do
    # Determine transport based on environment
    transport = get_transport()

    children =
      case transport do
        :http ->
          port = get_port()
          host = get_host()

          # For HTTP transport, don't start NativeService as supervisor child
          # MessageProcessor will start temporary instances per request
          # Our override ensures they start without names to avoid conflicts
          # HttpServer has :permanent restart in its child_spec
          [
            {MiniZincMcp.HttpServer, [port: port, host: host]}
          ]

        :stdio ->
          # For stdio transport, start NativeService as supervisor child
          # Both children have :permanent restart in their child_spec, so supervisor will restart them if they crash
          [
            {MiniZincMcp.NativeService, [name: MiniZincMcp.NativeService]},
            {MiniZincMcp.StdioServer, []}
          ]
      end

    # Standard Erlang/OTP supervisor configuration
    # - strategy: :one_for_one means if one child crashes, only restart that child
    # - max_restarts: maximum number of restarts in max_seconds before supervisor terminates
    # - max_seconds: time window for max_restarts
    # 
    # IMPORTANT: If max_restarts is exceeded, the supervisor terminates.
    # Since this is the Application supervisor, the entire application will stop.
    # This is standard Erlang "let it crash" behavior - if a process keeps crashing
    # repeatedly, something is fundamentally wrong and it's better to stop.
    # In production, use a process manager (systemd, Docker restart, etc.) to restart the app.
    opts = [
      strategy: :one_for_one,
      name: MiniZincMcp.Supervisor,
      max_restarts: 10,
      max_seconds: 60
    ]
    Supervisor.start_link(children, opts)
  end

  defp get_port do
    case System.get_env("PORT") do
      nil -> 8081
      port_str -> String.to_integer(port_str)
    end
  end

  defp get_host do
    # Use 0.0.0.0 for Docker/container deployments to accept external connections
    # Use localhost for local development
    case System.get_env("HOST") do
      nil ->
        # Default to 0.0.0.0 if PORT is set (container deployment), otherwise localhost
        if System.get_env("PORT"), do: "0.0.0.0", else: "localhost"

      host ->
        host
    end
  end

  defp get_transport do
    case System.get_env("MCP_TRANSPORT") do
      "http" ->
        :http

      "stdio" ->
        :stdio

      _ ->
        # Default to http if PORT is set (Smithery deployment), otherwise stdio
        if System.get_env("PORT"), do: :http, else: :stdio
    end
  end
end
