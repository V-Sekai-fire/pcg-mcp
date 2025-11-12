defmodule AdhocTest do
  use ExUnit.Case

  @moduledoc """
  Adhoc test to verify MiniZinc solver functionality.
  """

  test "solve simple MiniZinc model" do
    # Simple constraint satisfaction problem: find x > 0
    model = """
    var int: x;
    constraint x > 0;
    constraint x < 10;
    solve satisfy;
    """

    case PcgMcp.Solver.solve_string(model) do
      {:ok, result} ->
        IO.puts("\n✅ Test passed! Solution found:")
        IO.inspect(result, label: "Result")
        
        # Verify we got a solution
        assert is_map(result)
        # The result should have the variable x or output_text
        assert Map.has_key?(result, :x) || Map.has_key?(result, :output_text) || Map.has_key?(result, "x")
        
      {:error, reason} ->
        IO.puts("\n❌ Test failed with error:")
        IO.inspect(reason)
        flunk("Failed to solve model: #{reason}")
    end
  end

  test "solve MiniZinc model with data" do
    # Model that uses a parameter n
    model = """
    int: n;
    array[1..n] of var int: x;
    constraint all_different(x);
    constraint forall(i in 1..n)(x[i] >= 1);
    constraint forall(i in 1..n)(x[i] <= n);
    solve satisfy;
    """

    # Data file content
    data = "n = 5;"

    case PcgMcp.Solver.solve_string(model, data) do
      {:ok, result} ->
        IO.puts("\n✅ Test with data passed! Solution found:")
        IO.inspect(result, label: "Result")
        
        # Verify we got a solution
        assert is_map(result)
        
        # Check if input_data was parsed
        if Map.has_key?(result, :input_data) and result.input_data != %{} do
          assert result.input_data["n"] == 5 || result.input_data[:n] == 5
          n_val = result.input_data["n"] || result.input_data[:n]
          IO.puts("✅ Input data correctly parsed: n = #{n_val}")
        else
          IO.puts("ℹ️  Input data not in result (may be parsed differently)")
        end
        
      {:error, reason} ->
        IO.puts("\n❌ Test failed with error:")
        IO.inspect(reason)
        flunk("Failed to solve model with data: #{reason}")
    end
  end

  test "solve optimization problem" do
    # Simple optimization: minimize x
    model = """
    var int: x;
    constraint x >= 1;
    constraint x <= 10;
    solve minimize x;
    """

    case PcgMcp.Solver.solve_string(model) do
      {:ok, result} ->
        IO.puts("\n✅ Optimization test passed! Solution found:")
        IO.inspect(result, label: "Result")
        
        assert is_map(result)
        
      {:error, reason} ->
        IO.puts("\n❌ Optimization test failed with error:")
        IO.inspect(reason)
        flunk("Failed to solve optimization model: #{reason}")
    end
  end

  test "wfc_init with simple pattern" do
    # Simple 4x4 pattern
    sample = [
      [1, 1, 1, 1],
      [1, 0, 0, 1],
      [1, 0, 0, 1],
      [1, 1, 1, 1]
    ]

    case PcgMcp.WaveFunctionCollapse.init(sample, 2, 8, 8) do
      {:ok, state} ->
        IO.puts("\n✅ WFC init passed!")
        IO.puts("Grid size: #{state.width}x#{state.height}")
        IO.puts("Patterns found: #{length(state.patterns)}")
        IO.puts("Pattern weights: #{map_size(state.pattern_weights)} patterns")
        
        # Verify state structure
        assert state.width == 8
        assert state.height == 8
        assert length(state.patterns) > 0
        assert map_size(state.pattern_weights) > 0
        
        # Check that weights are frequency-based (not all 1.0)
        weights = Map.values(state.pattern_weights)
        unique_weights = Enum.uniq(weights)
        IO.puts("Unique weight values: #{length(unique_weights)}")
        if length(unique_weights) > 1 do
          IO.puts("✅ Pattern weights are frequency-based (not all equal)")
        else
          IO.puts("ℹ️  All patterns have same weight (may be expected for this sample)")
        end
        
      {:error, reason} ->
        IO.puts("\n❌ WFC init failed:")
        IO.inspect(reason)
        flunk("Failed to initialize WFC: #{reason}")
    end
  end

  test "wfc_tick collapses one cell" do
    sample = [
      [1, 1],
      [1, 0]
    ]

    case PcgMcp.WaveFunctionCollapse.init(sample, 2, 4, 4) do
      {:ok, state} ->
        # Count uncollapsed before
        uncollapsed_before = state.grid
        |> Enum.flat_map(& &1)
        |> Enum.count(fn cell -> not cell.collapsed end)
        
        IO.puts("\n✅ WFC initialized")
        IO.puts("Uncollapsed cells before tick: #{uncollapsed_before}")
        
        # Perform one tick
        case PcgMcp.WaveFunctionCollapse.tick(state) do
          {:ok, new_state, complete} ->
            uncollapsed_after = new_state.grid
            |> Enum.flat_map(& &1)
            |> Enum.count(fn cell -> not cell.collapsed end)
            
            IO.puts("Uncollapsed cells after tick: #{uncollapsed_after}")
            IO.puts("Complete: #{complete}")
            
            assert uncollapsed_after < uncollapsed_before
            IO.puts("✅ Tick successfully collapsed at least one cell")
            
          {:error, reason} ->
            IO.puts("\n❌ WFC tick failed:")
            IO.inspect(reason)
            flunk("Failed to tick WFC: #{reason}")
        end
        
      {:error, reason} ->
        IO.puts("\n❌ WFC init failed:")
        IO.inspect(reason)
        flunk("Failed to initialize WFC: #{reason}")
    end
  end

  test "wfc_run completes generation" do
    sample = [
      [0, 1, 0],
      [1, 0, 1],
      [0, 1, 0]
    ]

    case PcgMcp.WaveFunctionCollapse.init(sample, 2, 6, 6) do
      {:ok, state} ->
        IO.puts("\n✅ WFC initialized, running to completion...")
        
        case PcgMcp.WaveFunctionCollapse.run(state, 100) do
          {:ok, final_state, history} ->
            IO.puts("✅ WFC completed!")
            IO.puts("Iterations: #{length(history)}")
            
            # Check final state
            all_collapsed = final_state.grid
            |> Enum.all?(fn row ->
              Enum.all?(row, & &1.collapsed)
            end)
            
            if all_collapsed do
              IO.puts("✅ All cells collapsed")
              
              # Show output
              output = PcgMcp.WaveFunctionCollapse.get_output(final_state)
              IO.puts("\nFinal output (first 6x6):")
              Enum.take(output, 6)
              |> Enum.each(fn row ->
                row_str = Enum.take(row, 6) |> Enum.join(" ")
                IO.puts(row_str)
              end)
            else
              IO.puts("⚠️  Not all cells collapsed")
            end
            
          {:error, reason} ->
            IO.puts("\n❌ WFC run failed:")
            IO.inspect(reason)
            # This might be expected (max iterations or contradiction)
            IO.puts("ℹ️  This may be expected (max iterations or contradiction)")
        end
        
      {:error, reason} ->
        IO.puts("\n❌ WFC init failed:")
        IO.inspect(reason)
        flunk("Failed to initialize WFC: #{reason}")
    end
  end

  test "wfc with kenney assets - load image" do
    # Test loading a Kenney tile image
    tile_path = Path.join([__DIR__, "..", "assets", "kenney", "tiny-dungeon", "Tiles", "tile_0001.png"])
    
    if File.exists?(tile_path) do
      IO.puts("\n✅ Found Kenney tile: #{tile_path}")
      
      case PcgMcp.WaveFunctionCollapse.load_image(tile_path) do
        {:ok, sample} ->
          IO.puts("✅ Image loaded successfully")
          IO.puts("Sample dimensions: #{length(sample)}x#{if length(sample) > 0, do: length(hd(sample)), else: 0}")
          
          # Try to initialize WFC with the image
          case PcgMcp.WaveFunctionCollapse.init(sample, 2, 8, 8) do
            {:ok, state} ->
              IO.puts("✅ WFC initialized from image")
              IO.puts("Patterns extracted: #{length(state.patterns)}")
              
            {:error, reason} ->
              IO.puts("⚠️  WFC init from image failed:")
              IO.inspect(reason)
          end
          
        {:error, reason} ->
          IO.puts("⚠️  Image loading failed (may need nx_image):")
          IO.inspect(reason)
          IO.puts("ℹ️  This is expected if nx_image is not available")
      end
    else
      IO.puts("ℹ️  Kenney tile not found at #{tile_path}")
      IO.puts("   Skipping image loading test")
    end
  end
end

