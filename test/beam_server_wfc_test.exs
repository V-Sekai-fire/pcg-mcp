# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule BeamServerWfcTest do
  use ExUnit.Case

  @moduledoc """
  Tests for Wave Function Collapse tools via BEAM server (NativeService).
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

  test "wfc_init - from array pattern", %{service_pid: _pid} do
    sample = [
      [1, 1, 1],
      [1, 0, 1],
      [1, 1, 1]
    ]
    
    args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 8,
      "output_height" => 8
    }
    
    case NativeService.handle_tool_call("wfc_init", args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        {:ok, state} = Jason.decode(content["text"])
        assert Map.has_key?(state, "grid")
        assert Map.has_key?(state, "width")
        assert Map.has_key?(state, "height")
        assert Map.has_key?(state, "patterns")
        assert Map.has_key?(state, "pattern_weights")
        assert Map.has_key?(state, "adjacency_rules")
        assert state["width"] == 8
        assert state["height"] == 8
        assert length(state["patterns"]) > 0
        
      {:error, reason, _state} ->
        flunk("WFC init failed: #{reason}")
    end
  end

  test "wfc_tick - single iteration", %{service_pid: _pid} do
    # Initialize first
    sample = [[1, 0], [0, 1]]
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 5,
      "output_height" => 5
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    # Count uncollapsed before
    uncollapsed_before = init_state["grid"]
    |> Enum.flat_map(& &1)
    |> Enum.count(fn cell -> not cell["collapsed"] end)
    
    # Perform tick
    tick_args = %{"state" => init_state}
    
    case NativeService.handle_tool_call("wfc_tick", tick_args, %{}) do
      {:ok, tick_response, _state} ->
        tick_content = List.first(tick_response["content"])
        {:ok, tick_result} = Jason.decode(tick_content["text"])
        
        uncollapsed_after = tick_result["grid"]
        |> Enum.flat_map(& &1)
        |> Enum.count(fn cell -> not cell["collapsed"] end)
        
        assert uncollapsed_after < uncollapsed_before
        assert Map.has_key?(tick_result, "complete")
        assert is_boolean(tick_result["complete"])
        
      {:error, reason, _state} ->
        flunk("WFC tick failed: #{reason}")
    end
  end

  test "wfc_run - complete generation", %{service_pid: _pid} do
    sample = [
      [0, 1, 0],
      [1, 0, 1],
      [0, 1, 0]
    ]
    
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 6,
      "output_height" => 6
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    run_args = %{
      "state" => init_state,
      "max_iterations" => 100
    }
    
    case NativeService.handle_tool_call("wfc_run", run_args, %{}) do
      {:ok, run_response, _state} ->
        run_content = List.first(run_response["content"])
        {:ok, run_result} = Jason.decode(run_content["text"])
        
        assert Map.has_key?(run_result, "final_state")
        assert Map.has_key?(run_result, "history")
        assert Map.has_key?(run_result, "iterations")
        assert is_integer(run_result["iterations"])
        assert run_result["iterations"] > 0
        
        # Check final state
        final_state = run_result["final_state"]
        assert Map.has_key?(final_state, "grid")
        assert Map.has_key?(final_state, "width")
        assert Map.has_key?(final_state, "height")
        
      {:error, reason, _state} ->
        flunk("WFC run failed: #{reason}")
    end
  end

  test "wfc_get_output - extract grid", %{service_pid: _pid} do
    # Initialize and run
    sample = [[1, 1], [1, 0]]
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 4,
      "output_height" => 4
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    run_args = %{"state" => init_state, "max_iterations" => 50}
    {:ok, run_response, _state} = NativeService.handle_tool_call("wfc_run", run_args, %{})
    run_content = List.first(run_response["content"])
    {:ok, run_result} = Jason.decode(run_content["text"])
    final_state = run_result["final_state"]
    
    # Get output
    output_args = %{"state" => final_state}
    
    case NativeService.handle_tool_call("wfc_get_output", output_args, %{}) do
      {:ok, output_response, _state} ->
        output_content = List.first(output_response["content"])
        {:ok, output_result} = Jason.decode(output_content["text"])
        
        assert Map.has_key?(output_result, "output")
        assert Map.has_key?(output_result, "width")
        assert Map.has_key?(output_result, "height")
        assert is_list(output_result["output"])
        assert output_result["width"] == 4
        assert output_result["height"] == 4
        assert length(output_result["output"]) == 4
        assert length(hd(output_result["output"])) == 4
        
      {:error, reason, _state} ->
        flunk("WFC get_output failed: #{reason}")
    end
  end
end

