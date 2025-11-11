# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.HttpPlugWrapper do
  @moduledoc """
  Wrapper around ExMCP.HttpPlug that fixes SSE session ID mismatch bug.
  When a session ID is provided in SSE connection but doesn't exist, ExMCP creates a new one.
  This wrapper tracks the mapping and fixes POST requests to use the correct session ID.
  """

  @behaviour Plug

  alias ExMCP.HttpPlug

  @impl Plug
  def init(opts) do
    HttpPlug.init(opts)
  end

  @impl Plug
  def call(conn, opts) do
    sse_enabled = Map.get(opts, :sse_enabled, true)

    result =
      cond do
        conn.method != "POST" || !sse_enabled ->
          HttpPlug.call(conn, opts)

        has_session_id?(conn) ->
          HttpPlug.call(conn, opts)

        true ->
          handle_missing_session_id(conn, opts)
      end

    # MCP/JSON-RPC 2.0 spec requires all responses to be valid JSON-RPC messages
    # If the response has a 500 status but empty body, send a proper JSON-RPC error response
    case result do
      %Plug.Conn{status: status} = conn_result when status == 500 ->
        require Logger
        # Check if body is empty - resp_body might not be set yet, check state
        body =
          case conn_result.resp_body do
            nil -> ""
            "" -> ""
            body when is_binary(body) -> if String.length(body) == 0, do: "", else: body
            _ -> ""
          end

        # Also check content-length header
        content_length = Plug.Conn.get_resp_header(conn_result, "content-length")
        is_empty = body == "" or (content_length != [] and List.first(content_length) == "0")

        Logger.debug(
          "HttpPlugWrapper: 500 response, body length: #{String.length(body || "")}, content-length: #{inspect(content_length)}, is_empty: #{is_empty}"
        )

        if is_empty do
          # Extract request ID from the request body if available
          request_id = extract_request_id(conn)
          # JSON-RPC 2.0 spec: -32603 = Internal error
          error_response = %{
            "jsonrpc" => "2.0",
            "error" => %{
              "code" => -32_603,
              "message" => "Internal error",
              "data" => %{"reason" => "No response from handler - empty body"}
            },
            "id" => request_id
          }

          Logger.info(
            "HttpPlugWrapper: Replacing empty 500 response with JSON-RPC error: #{inspect(error_response)}"
          )

          conn_result
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, Jason.encode!(error_response))
        else
          conn_result
        end

      %Plug.Conn{} = conn_result ->
        conn_result

      other ->
        other
    end
  end

  defp extract_request_id(conn) do
    # Try to read the body without consuming it
    case conn.body_params do
      %{"id" => id} ->
        id

      _ ->
        # Fallback: try to read raw body
        case Plug.Conn.read_body(conn, length: 4096) do
          {:ok, body, _conn} ->
            case Jason.decode(body) do
              {:ok, %{"id" => id}} -> id
              _ -> nil
            end

          _ ->
            nil
        end
    end
  rescue
    _ -> nil
  end

  defp has_session_id?(conn) do
    Plug.Conn.get_req_header(conn, "mcp-session-id") != []
  end

  defp handle_missing_session_id(conn, opts) do
    case find_any_active_sse_session() do
      {:ok, session_id} ->
        modified_conn = Plug.Conn.put_req_header(conn, "mcp-session-id", session_id)
        HttpPlug.call(modified_conn, opts)

      {:error, _} ->
        modified_opts = Map.put(opts, :sse_enabled, false)
        HttpPlug.call(conn, modified_opts)
    end
  end

  # Find any active SSE session from the ETS table
  defp find_any_active_sse_session do
    table = :http_plug_sessions

    try do
      # Get all entries from the ETS table using tab2list for debugging
      all_entries = :ets.tab2list(table)

      require Logger

      Logger.debug(
        "HttpPlugWrapper: Found #{length(all_entries)} entries in ETS table: #{inspect(all_entries)}"
      )

      # Filter to only alive handler processes
      alive_sessions =
        all_entries
        |> Enum.filter(fn
          {session_id, handler_pid} when is_pid(handler_pid) ->
            alive = Process.alive?(handler_pid)

            Logger.debug(
              "HttpPlugWrapper: Session #{inspect(session_id)} handler #{inspect(handler_pid)} alive: #{alive}"
            )

            alive

          _ ->
            false
        end)
        |> Enum.map(fn {session_id, _} -> session_id end)

      Logger.debug(
        "HttpPlugWrapper: Found #{length(alive_sessions)} alive SSE sessions: #{inspect(alive_sessions)}"
      )

      case alive_sessions do
        [session_id | _] ->
          Logger.debug("HttpPlugWrapper: Using SSE session ID: #{inspect(session_id)}")
          {:ok, to_string(session_id)}

        [] ->
          Logger.debug("HttpPlugWrapper: No alive SSE sessions found")
          {:error, :no_active_sessions}
      end
    rescue
      ArgumentError ->
        # Table doesn't exist
        require Logger
        Logger.debug("HttpPlugWrapper: ETS table :http_plug_sessions does not exist")
        {:error, :table_not_found}
    end
  end
end
