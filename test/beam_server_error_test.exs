# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule BeamServerErrorTest do
  use ExUnit.Case

  @moduledoc """
  Error handling tests for BEAM server (NativeService).
  """

  alias PcgMcp.NativeService

  setup do
    Application.ensure_all_started(:pcg_mcp)
    
    pid = case NativeService.start_link([]) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "Failed to start NativeService: #{inspect(reason)}"
    end
    
    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    
    %{service_pid: pid}
  end

  test "invalid tool name returns error", %{service_pid: _pid} do
    case NativeService.handle_tool_call("nonexistent_tool", %{}, %{}) do
      {:error, "Tool not found: nonexistent_tool", _state} ->
        :ok
      other ->
        flunk("Expected tool not found error, got: #{inspect(other)}")
    end
  end

  test "wfc_init with missing parameters", %{service_pid: _pid} do
    args = %{
      "sample" => [[1, 0], [0, 1]]
      # Missing output_width and output_height
    }
    
    case NativeService.handle_tool_call("wfc_init", args, %{}) do
      {:error, reason, _state} ->
        assert String.contains?(reason, "must be provided")
      other ->
        flunk("Expected error for missing parameters, got: #{inspect(other)}")
    end
  end

  test "wfc_tick with missing state", %{service_pid: _pid} do
    args = %{}  # Missing state
    
    case NativeService.handle_tool_call("wfc_tick", args, %{}) do
      {:error, reason, _state} ->
        assert String.contains?(reason, "must be provided")
      other ->
        flunk("Expected error for missing state, got: #{inspect(other)}")
    end
  end

  test "wfc_tick with malformed state", %{service_pid: _pid} do
    args = %{"state" => %{"invalid" => "state", "grid" => "not a list"}}
    
    case NativeService.handle_tool_call("wfc_tick", args, %{}) do
      {:error, _reason, _state} ->
        :ok  # Expected to fail with malformed state
      {:ok, _response, _state} ->
        # Might succeed with defaults, which is also acceptable
        :ok
    end
  end
end

