# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule Mix.Tasks.Pcg.Generate do
  @moduledoc """
  Generate a procedural level using Wave Function Collapse.

  ## Examples

      mix pcg.generate
      mix pcg.generate simple 30 20
      mix pcg.generate checkerboard 25 15
  """
  
  use Mix.Task
  
  alias PcgMcp.WaveFunctionCollapse
  
  @shortdoc "Generate a PCG level using WFC"
  
  def run(args) do
    # Ensure application is started
    Application.ensure_all_started(:pcg_mcp)
    
    {pattern_type, width, height} = parse_args(args)
    
    IO.puts("🎲 Generating PCG Level with WFC")
    IO.puts("Pattern: #{pattern_type}, Size: #{width}x#{height}")
    IO.puts("")
    
    sample = case pattern_type do
      "simple" -> create_simple_pattern()
      "checkerboard" -> create_checkerboard_pattern()
      "dungeon" -> create_dungeon_pattern()
      _ -> create_simple_pattern()
    end
    
    generate_level(sample, width, height)
  end
  
  defp parse_args(args) do
    pattern_type = Enum.at(args, 0, "simple")
    width = args |> Enum.at(1, "30") |> String.to_integer()
    height = args |> Enum.at(2, "20") |> String.to_integer()
    {pattern_type, width, height}
  end
  
  defp create_simple_pattern do
    # A simple room-like pattern
    [
      [1, 1, 1, 1, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 2, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 1, 1, 1, 1]
    ]
  end
  
  defp create_checkerboard_pattern do
    # Checkerboard pattern
    [
      [0, 1, 0, 1, 0],
      [1, 0, 1, 0, 1],
      [0, 1, 0, 1, 0],
      [1, 0, 1, 0, 1],
      [0, 1, 0, 1, 0]
    ]
  end
  
  defp create_dungeon_pattern do
    # More complex dungeon-like pattern
    [
      [1, 1, 1, 1, 1, 1, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 0, 2, 2, 2, 0, 1],
      [1, 0, 2, 3, 2, 0, 1],
      [1, 0, 2, 2, 2, 0, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 1, 1, 1, 1, 1, 1]
    ]
  end
  
  defp generate_level(sample, width, height) do
    pattern_size = 3
    
    IO.puts("Initializing WFC...")
    case WaveFunctionCollapse.init(sample, pattern_size, width, height) do
      {:ok, state} ->
        IO.puts("✅ WFC initialized")
        IO.puts("   Patterns extracted: #{length(state.patterns)}")
        IO.puts("   Pattern weights: #{map_size(state.pattern_weights)} unique patterns")
        IO.puts("")
        IO.puts("Generating level...")
        
        max_iterations = width * height * 2
        case WaveFunctionCollapse.run(state, max_iterations) do
          {:ok, final_state, history} ->
            IO.puts("✅ Generation complete!")
            IO.puts("   Iterations: #{length(history)}")
            IO.puts("")
            
            # Display the generated level
            output = WaveFunctionCollapse.get_output(final_state)
            display_level(output)
            
            # Check if complete
            all_collapsed = final_state.grid
            |> Enum.all?(fn row ->
              Enum.all?(row, & &1.collapsed)
            end)
            
            if all_collapsed do
              IO.puts("")
              IO.puts("✅ All cells collapsed successfully")
            else
              uncollapsed = final_state.grid
              |> Enum.flat_map(& &1)
              |> Enum.count(fn cell -> not cell.collapsed end)
              IO.puts("")
              IO.puts("⚠️  #{uncollapsed} cells remain uncollapsed")
            end
            
          {:error, reason} ->
            IO.puts("❌ Generation failed: #{reason}")
            System.halt(1)
        end
        
      {:error, reason} ->
        IO.puts("❌ WFC initialization failed: #{reason}")
        System.halt(1)
    end
  end
  
  defp display_level(output) do
    IO.puts("Generated Level:")
    IO.puts(String.duplicate("=", 60))
    
    Enum.each(output, fn row ->
      row_str = Enum.map(row, fn
        0 -> " "  # Empty/floor
        1 -> "█"  # Wall
        2 -> "░"  # Floor pattern
        3 -> "▓"  # Special tile
        n when is_integer(n) -> Integer.to_string(rem(n, 10))
        _ -> "?"
      end)
      |> Enum.join("")
      IO.puts(row_str)
    end)
    
    IO.puts(String.duplicate("=", 60))
  end
end

