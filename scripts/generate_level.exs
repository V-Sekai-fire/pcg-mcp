#!/usr/bin/env elixir

# Script to generate a PCG level using Wave Function Collapse
# Usage: elixir scripts/generate_level.exs [pattern_type] [width] [height]
#
# pattern_type: "simple" (default), "checkerboard", or "image"
# width: output width (default: 20)
# height: output height (default: 20)

Mix.install([])

# Ensure we're in the project directory
Code.require_file("lib/pcg_mcp/wave_function_collapse.ex")

alias PcgMcp.WaveFunctionCollapse

defmodule LevelGenerator do
  def run(args) do
    {pattern_type, width, height} = parse_args(args)
    
    IO.puts("🎲 Generating PCG Level with WFC")
    IO.puts("Pattern: #{pattern_type}, Size: #{width}x#{height}")
    IO.puts("")
    
    sample = case pattern_type do
      "simple" -> create_simple_pattern()
      "checkerboard" -> create_checkerboard_pattern()
      "image" -> load_image_sample()
      _ -> create_simple_pattern()
    end
    
    case sample do
      {:ok, sample_data} ->
        generate_level(sample_data, width, height)
      {:error, reason} ->
        IO.puts("❌ Failed to load sample: #{reason}")
        System.halt(1)
    end
  end
  
  defp parse_args(args) do
    pattern_type = Enum.at(args, 0, "simple")
    width = args |> Enum.at(1, "20") |> String.to_integer()
    height = args |> Enum.at(2, "20") |> String.to_integer()
    {pattern_type, width, height}
  end
  
  defp create_simple_pattern do
    # A simple room-like pattern
    pattern = [
      [1, 1, 1, 1, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 2, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 1, 1, 1, 1]
    ]
    {:ok, pattern}
  end
  
  defp create_checkerboard_pattern do
    # Checkerboard pattern
    pattern = [
      [0, 1, 0, 1, 0],
      [1, 0, 1, 0, 1],
      [0, 1, 0, 1, 0],
      [1, 0, 1, 0, 1],
      [0, 1, 0, 1, 0]
    ]
    {:ok, pattern}
  end
  
  defp load_image_sample do
    # Try to load a Kenney tile image
    tile_path = Path.join([__DIR__, "..", "assets", "kenney", "tiny-dungeon", "Tiles", "tile_0001.png"])
    
    if File.exists?(tile_path) do
      case WaveFunctionCollapse.load_image(tile_path) do
        {:ok, sample} -> {:ok, sample}
        error -> error
      end
    else
      {:error, "Image not found at #{tile_path}"}
    end
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
        
        case WaveFunctionCollapse.run(state, width * height * 2) do
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
    IO.puts(String.duplicate("=", 50))
    
    Enum.each(output, fn row ->
      row_str = Enum.map(row, fn
        0 -> " "
        1 -> "█"
        2 -> "░"
        3 -> "▓"
        n when is_integer(n) -> Integer.to_string(rem(n, 10))
        _ -> "?"
      end)
      |> Enum.join("")
      IO.puts(row_str)
    end)
    
    IO.puts(String.duplicate("=", 50))
  end
end

# Run if called directly
if System.argv() != [] or true do
  LevelGenerator.run(System.argv())
end

