# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule BeamServerMinizincTest do
  use ExUnit.Case

  @moduledoc """
  Tests for MiniZinc tools via BEAM server (NativeService).
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

  test "minizinc_solve - simple constraint", %{service_pid: _pid} do
    args = %{
      "model_content" => """
      var int: x;
      constraint x > 0;
      constraint x < 10;
      solve satisfy;
      """
    }
    
    case NativeService.handle_tool_call("minizinc_solve", args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        assert content["type"] == "text"
        {:ok, result} = Jason.decode(content["text"])
        assert is_map(result)
        # Should have x or output_text
        assert Map.has_key?(result, "x") || Map.has_key?(result, "output_text") || Map.has_key?(result, "dzn_output")
        
      {:error, reason, _state} ->
        flunk("MiniZinc solve failed: #{reason}")
    end
  end

  test "minizinc_solve - with data", %{service_pid: _pid} do
    args = %{
      "model_content" => """
      int: n;
      array[1..n] of var int: x;
      constraint all_different(x);
      constraint forall(i in 1..n)(x[i] >= 1);
      constraint forall(i in 1..n)(x[i] <= n);
      solve satisfy;
      """,
      "data_content" => "n = 5;"
    }
    
    case NativeService.handle_tool_call("minizinc_solve", args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        {:ok, result} = Jason.decode(content["text"])
        assert is_map(result)
        assert Map.has_key?(result, "x") || Map.has_key?(result, "output_text")
        
      {:error, reason, _state} ->
        flunk("MiniZinc solve with data failed: #{reason}")
    end
  end

  test "minizinc_validate - valid model", %{service_pid: _pid} do
    args = %{
      "model_content" => """
      var int: x;
      constraint x > 0;
      solve satisfy;
      """
    }
    
    case NativeService.handle_tool_call("minizinc_validate", args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        {:ok, result} = Jason.decode(content["text"])
        assert result["valid"] == true
        assert is_list(result["errors"])
        assert is_list(result["warnings"])
        
      {:error, reason, _state} ->
        flunk("MiniZinc validate failed: #{reason}")
    end
  end

  test "minizinc_validate - invalid model", %{service_pid: _pid} do
    args = %{
      "model_content" => """
      var int: x;
      constraint x > 0 solve satisfy;
      """
    }
    
    case NativeService.handle_tool_call("minizinc_validate", args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        {:ok, result} = Jason.decode(content["text"])
        assert result["valid"] == false
        assert length(result["errors"]) > 0
        
      {:error, reason, _state} ->
        flunk("MiniZinc validate should return validation result: #{reason}")
    end
  end
end

