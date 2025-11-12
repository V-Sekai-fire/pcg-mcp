# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule BeamServerIntegrationTest do
  use ExUnit.Case

  @moduledoc """
  Integration tests for full workflows via BEAM server (NativeService).
  Tests complete workflows and tool interactions.
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

  test "complete WFC workflow via BEAM server", %{service_pid: _pid} do
    # 1. Initialize
    sample = [
      [1, 1, 1, 1],
      [1, 0, 0, 1],
      [1, 0, 0, 1],
      [1, 1, 1, 1]
    ]
    
    init_args = %{
      "sample" => sample,
      "pattern_size" => 3,
      "output_width" => 10,
      "output_height" => 10
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    assert init_state["width"] == 10
    assert init_state["height"] == 10
    
    # 2. Run multiple ticks manually
    current_state = init_state
    max_ticks = 20
    
    {final_state, ticks_done} = Enum.reduce_while(1..max_ticks, {current_state, 0}, fn _i, {state, count} ->
      tick_args = %{"state" => state}
      
      case NativeService.handle_tool_call("wfc_tick", tick_args, %{}) do
        {:ok, tick_response, _state} ->
          tick_content = List.first(tick_response["content"])
          {:ok, tick_result} = Jason.decode(tick_content["text"])
          
          if tick_result["complete"] do
            {:halt, {tick_result, count + 1}}
          else
            {:cont, {tick_result, count + 1}}
          end
            
        {:error, _reason, _state} ->
          # Might be complete or contradiction
          {:halt, {state, count}}
      end
    end)
    
    assert ticks_done > 0
    
    # 3. Get output
    output_args = %{"state" => final_state}
    {:ok, output_response, _state} = NativeService.handle_tool_call("wfc_get_output", output_args, %{})
    output_content = List.first(output_response["content"])
    {:ok, output_result} = Jason.decode(output_content["text"])
    
    assert is_list(output_result["output"])
    assert output_result["width"] == 10
    assert output_result["height"] == 10
  end

  test "MiniZinc + WFC can be used together", %{service_pid: _pid} do
    # Test that both tool types work in the same session
    
    # 1. Use MiniZinc
    minizinc_args = %{
      "model_content" => "var int: x; constraint x > 5; constraint x < 10; solve satisfy;"
    }
    
    {:ok, mz_response, state1} = NativeService.handle_tool_call("minizinc_solve", minizinc_args, %{})
    mz_content = List.first(mz_response["content"])
    {:ok, mz_result} = Jason.decode(mz_content["text"])
    assert is_map(mz_result)
    
    # 2. Use WFC (state should persist)
    wfc_args = %{
      "sample" => [[1, 0], [0, 1]],
      "pattern_size" => 2,
      "output_width" => 3,
      "output_height" => 3
    }
    
    {:ok, wfc_response, _state2} = NativeService.handle_tool_call("wfc_init", wfc_args, state1)
    wfc_content = List.first(wfc_response["content"])
    {:ok, wfc_result} = Jason.decode(wfc_content["text"])
    assert Map.has_key?(wfc_result, "grid")
    
    # Both should work independently
    assert is_map(mz_result)
    assert is_map(wfc_result)
  end
end

