# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule McpIntegrationTest do
  use ExUnit.Case

  @moduledoc """
  Integration tests for MCP tools to ensure all functionality is properly exposed.
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

  test "all MCP tools are available", %{service_pid: _pid} do
    # Test that we can call all tools without errors
    tools = ["minizinc_solve", "minizinc_validate", "wfc_init", "wfc_tick", "wfc_run", "wfc_get_output"]
    
    Enum.each(tools, fn tool_name ->
      # Just verify the tool exists by checking it doesn't return "Tool not found"
      args = %{}
      case NativeService.handle_tool_call(tool_name, args, %{}) do
        {:error, "Tool not found: " <> ^tool_name, _state} ->
          flunk("Tool #{tool_name} not found")
        _ ->
          :ok  # Tool exists (may return other errors for invalid args, which is fine)
      end
    end)
  end

  test "wfc_init via MCP", %{service_pid: _pid} do
    sample = [
      [1, 1, 1],
      [1, 0, 1],
      [1, 1, 1]
    ]
    
    args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 5,
      "output_height" => 5
    }
    
    case NativeService.handle_tool_call("wfc_init", args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        assert content["type"] == "text"
        {:ok, state_json} = Jason.decode(content["text"])
        assert Map.has_key?(state_json, "grid")
        assert Map.has_key?(state_json, "width")
        assert Map.has_key?(state_json, "height")
        assert state_json["width"] == 5
        assert state_json["height"] == 5
        
      {:error, reason, _state} ->
        flunk("WFC init failed: #{reason}")
    end
  end

  test "wfc_get_output via MCP", %{service_pid: _pid} do
    # Initialize WFC
    sample = [
      [1, 0],
      [0, 1]
    ]
    
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 3,
      "output_height" => 3
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    # Get output
    output_args = %{"state" => init_state}
    
    case NativeService.handle_tool_call("wfc_get_output", output_args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        {:ok, result} = Jason.decode(content["text"])
        assert Map.has_key?(result, "output")
        assert is_list(result["output"])
        assert result["width"] == 3
        assert result["height"] == 3
        
      {:error, reason, _state} ->
        flunk("WFC get_output failed: #{reason}")
    end
  end

  test "full WFC workflow via MCP", %{service_pid: _pid} do
    # 1. Initialize
    sample = [
      [1, 1],
      [1, 0]
    ]
    
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 4,
      "output_height" => 4
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    # 2. Run to completion
    run_args = %{
      "state" => init_state,
      "max_iterations" => 100
    }
    
    case NativeService.handle_tool_call("wfc_run", run_args, %{}) do
      {:ok, run_response, _state} ->
        run_content = List.first(run_response["content"])
        {:ok, run_result} = Jason.decode(run_content["text"])
        assert Map.has_key?(run_result, "final_state")
        assert Map.has_key?(run_result, "iterations")
        assert is_integer(run_result["iterations"])
        
        # 3. Get output
        final_state = run_result["final_state"]
        output_args = %{"state" => final_state}
        
        {:ok, output_response, _state} = NativeService.handle_tool_call("wfc_get_output", output_args, %{})
        output_content = List.first(output_response["content"])
        {:ok, output_result} = Jason.decode(output_content["text"])
        assert Map.has_key?(output_result, "output")
        assert length(output_result["output"]) == 4  # height
        assert length(hd(output_result["output"])) == 4  # width
        
      {:error, reason, _state} ->
        flunk("WFC run failed: #{reason}")
    end
  end
end

