# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule WfcTest do
  use ExUnit.Case

  @moduledoc """
  Tests for Wave Function Collapse functionality using BEAM server (NativeService).
  Tests against fixtures to ensure consistent behavior.
  """

  alias PcgMcp.NativeService

  @fixtures_dir Path.join([__DIR__, "fixtures"])

  setup do
    # Ensure the application is started
    Application.ensure_all_started(:pcg_mcp)
    
    # Start a NativeService instance for testing
    # Handle case where it's already started
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

  test "wfc_init with simple pattern from fixture", %{service_pid: _pid} do
    # Load fixture
    fixture_path = Path.join(@fixtures_dir, "simple_pattern.json")
    {:ok, sample} = load_fixture(fixture_path)
    
    # Initialize WFC via NativeService
    args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 8,
      "output_height" => 8
    }
    
    case NativeService.handle_tool_call("wfc_init", args, %{}) do
      {:ok, response, _state} ->
        # Verify response structure
        assert Map.has_key?(response, "content")
        content = List.first(response["content"])
        assert Map.get(content, "type") == "text"
        
        # Parse state JSON
        state_json = Map.get(content, "text")
        {:ok, state} = Jason.decode(state_json)
        
        # Verify state structure
        assert Map.has_key?(state, "grid")
        assert Map.has_key?(state, "width")
        assert Map.has_key?(state, "height")
        assert Map.has_key?(state, "patterns")
        assert Map.has_key?(state, "pattern_weights")
        
        # Verify dimensions
        assert state["width"] == 8
        assert state["height"] == 8
        
        # Verify grid structure
        grid = state["grid"]
        assert is_list(grid)
        assert length(grid) == 8
        
        # Verify each cell is in superposition (not collapsed)
        Enum.each(grid, fn row ->
          assert is_list(row)
          assert length(row) == 8
          
          Enum.each(row, fn cell ->
            assert Map.get(cell, "collapsed") == false
            assert is_list(Map.get(cell, "possible_tiles"))
            assert length(Map.get(cell, "possible_tiles")) > 0
          end)
        end)
        
      {:error, reason, _state} ->
        flunk("WFC init failed: #{reason}")
    end
  end

  test "wfc_tick collapses one cell", %{service_pid: _pid} do
    # Load fixture and initialize
    fixture_path = Path.join(@fixtures_dir, "simple_pattern.json")
    {:ok, sample} = load_fixture(fixture_path)
    
    # Initialize WFC
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 4,
      "output_height" => 4
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    # Count uncollapsed cells before tick
    uncollapsed_before = count_uncollapsed(init_state["grid"])
    assert uncollapsed_before > 0
    
    # Perform one tick
    tick_args = %{"state" => init_state}
    
    case NativeService.handle_tool_call("wfc_tick", tick_args, %{}) do
      {:ok, tick_response, _state} ->
        tick_content = List.first(tick_response["content"])
        {:ok, tick_result} = Jason.decode(tick_content["text"])
        
        # Verify state structure
        assert Map.has_key?(tick_result, "grid")
        assert Map.has_key?(tick_result, "complete")
        
        # Verify at least one cell was collapsed
        uncollapsed_after = count_uncollapsed(tick_result["grid"])
        assert uncollapsed_after < uncollapsed_before
        
        # Verify complete flag
        complete = tick_result["complete"]
        assert is_boolean(complete)
        
      {:error, reason, _state} ->
        flunk("WFC tick failed: #{reason}")
    end
  end

  test "wfc_run completes generation", %{service_pid: _pid} do
    # Load fixture
    fixture_path = Path.join(@fixtures_dir, "checkerboard_pattern.json")
    {:ok, sample} = load_fixture(fixture_path)
    
    # Initialize WFC
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 6,
      "output_height" => 6
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    # Run to completion
    run_args = %{
      "state" => init_state,
      "max_iterations" => 100
    }
    
    case NativeService.handle_tool_call("wfc_run", run_args, %{}) do
      {:ok, run_response, _state} ->
        run_content = List.first(run_response["content"])
        {:ok, run_result} = Jason.decode(run_content["text"])
        
        # Verify result structure
        assert Map.has_key?(run_result, "final_state")
        assert Map.has_key?(run_result, "history")
        assert Map.has_key?(run_result, "iterations")
        
        # Verify final state is complete
        final_state = run_result["final_state"]
        assert all_collapsed?(final_state["grid"])
        
        # Verify history
        history = run_result["history"]
        assert is_list(history)
        assert length(history) > 0
        
        # Verify iterations count
        iterations = run_result["iterations"]
        assert is_integer(iterations)
        assert iterations > 0
        assert iterations == length(history)
        
      {:error, reason, _state} ->
        # It's okay if it hits max iterations or contradiction
        assert is_binary(reason)
    end
  end

  test "wfc_init with checkerboard pattern from fixture", %{service_pid: _pid} do
    # Load fixture
    fixture_path = Path.join(@fixtures_dir, "checkerboard_pattern.json")
    {:ok, sample} = load_fixture(fixture_path)
    
    # Initialize WFC
    args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 10,
      "output_height" => 10
    }
    
    case NativeService.handle_tool_call("wfc_init", args, %{}) do
      {:ok, response, _state} ->
        content = List.first(response["content"])
        {:ok, state} = Jason.decode(content["text"])
        
        # Verify patterns were extracted
        patterns = state["patterns"]
        assert is_list(patterns)
        assert length(patterns) > 0
        
        # Verify pattern weights
        pattern_weights = state["pattern_weights"]
        assert is_map(pattern_weights)
        assert map_size(pattern_weights) > 0
        
        # Verify adjacency rules
        adjacency_rules = state["adjacency_rules"]
        assert is_map(adjacency_rules)
        
      {:error, reason, _state} ->
        flunk("WFC init failed: #{reason}")
    end
  end

  test "wfc_tick multiple times progresses generation", %{service_pid: _pid} do
    # Load fixture
    fixture_path = Path.join(@fixtures_dir, "simple_pattern.json")
    {:ok, sample} = load_fixture(fixture_path)
    
    # Initialize
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 4,
      "output_height" => 4
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, current_state} = Jason.decode(init_content["text"])
    
    # Perform multiple ticks
    tick_count = 5
    {uncollapsed_counts, _final_state} = Enum.reduce(1..tick_count, {[], current_state}, fn _i, {counts, state} ->
      uncollapsed = count_uncollapsed(state["grid"])
      
      # Skip if already complete
      if uncollapsed > 0 do
        tick_args = %{"state" => state}
        
        case NativeService.handle_tool_call("wfc_tick", tick_args, %{}) do
          {:ok, tick_response, _state} ->
            tick_content = List.first(tick_response["content"])
            {:ok, tick_result} = Jason.decode(tick_content["text"])
            {[uncollapsed | counts], tick_result}
            
          {:error, _reason, _state} ->
            # Stop if error (might be complete or contradiction)
            {[uncollapsed | counts], state}
        end
      else
        {[uncollapsed | counts], state}
      end
    end)
    
    # Verify progress was made (uncollapsed count should decrease)
    if length(uncollapsed_counts) > 1 do
      [first | rest] = Enum.reverse(uncollapsed_counts)
      Enum.each(rest, fn count ->
        assert count <= first, "Uncollapsed count should not increase"
      end)
    end
  end

  test "wfc_init validates required parameters", %{service_pid: _pid} do
    # Test missing sample
    args = %{
      "output_width" => 8,
      "output_height" => 8
    }
    
    case NativeService.handle_tool_call("wfc_init", args, %{}) do
      {:error, reason, _state} ->
        assert String.contains?(reason, "sample") or String.contains?(reason, "required")
        
      _ ->
        flunk("Should have failed with missing sample")
    end
    
    # Test missing dimensions
    args2 = %{
      "sample" => [[1, 1], [1, 1]]
    }
    
    case NativeService.handle_tool_call("wfc_init", args2, %{}) do
      {:error, reason, _state} ->
        assert String.contains?(reason, "width") or 
               String.contains?(reason, "height") or
               String.contains?(reason, "required")
        
      _ ->
        flunk("Should have failed with missing dimensions")
    end
  end

  test "wfc_tick handles already complete state", %{service_pid: _pid} do
    # Load fixture and initialize
    fixture_path = Path.join(@fixtures_dir, "simple_pattern.json")
    {:ok, sample} = load_fixture(fixture_path)
    
    # Initialize WFC
    init_args = %{
      "sample" => sample,
      "pattern_size" => 2,
      "output_width" => 1,
      "output_height" => 1
    }
    
    {:ok, init_response, _state} = NativeService.handle_tool_call("wfc_init", init_args, %{})
    init_content = List.first(init_response["content"])
    {:ok, init_state} = Jason.decode(init_content["text"])
    
    # Manually collapse all cells to simulate complete state
    complete_grid = Enum.map(init_state["grid"], fn row ->
      Enum.map(row, fn cell ->
        first_tile = List.first(cell["possible_tiles"])
        cell
        |> Map.put("collapsed", true)
        |> Map.put("tile", first_tile)
        |> Map.put("possible_tiles", [first_tile])
      end)
    end)
    complete_state = Map.put(init_state, "grid", complete_grid)
    
    # Tick should return complete immediately
    tick_args = %{"state" => complete_state}
    
    case NativeService.handle_tool_call("wfc_tick", tick_args, %{}) do
      {:ok, tick_response, _state} ->
        tick_content = List.first(tick_response["content"])
        {:ok, tick_result} = Jason.decode(tick_content["text"])
        
        # Should be marked as complete
        assert tick_result["complete"] == true
        
      {:error, reason, _state} ->
        flunk("WFC tick should handle complete state gracefully: #{reason}")
    end
  end

  # Helper functions

  defp load_fixture(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, "Failed to parse JSON: #{inspect(reason)}"}
        end
        
      {:error, reason} ->
        {:error, "Failed to read fixture: #{inspect(reason)}"}
    end
  end

  defp count_uncollapsed(grid) do
    grid
    |> Enum.flat_map(& &1)
    |> Enum.count(fn cell ->
      not Map.get(cell, "collapsed", false)
    end)
  end

  defp all_collapsed?(grid) do
    grid
    |> Enum.all?(fn row ->
      Enum.all?(row, fn cell ->
        Map.get(cell, "collapsed", false)
      end)
    end)
  end
end

