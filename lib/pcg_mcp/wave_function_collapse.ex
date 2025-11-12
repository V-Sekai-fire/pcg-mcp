# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule PcgMcp.WaveFunctionCollapse do
  @moduledoc """
  Wave Function Collapse algorithm implementation using MiniZinc for each tick.
  
  Each iteration (tick) is solved as a separate MiniZinc constraint satisfaction problem,
  where we find the cell with lowest entropy and determine which tile to collapse it to.
  
  Based on: https://github.com/mxgmn/WaveFunctionCollapse
  """

  require Logger
  alias PcgMcp.Solver
  
  # Try to require NxImage, but don't fail if not available
  try do
    Code.ensure_loaded(NxImage)
  rescue
    _ -> nil
  end

  @type cell_state :: %{
    possible_tiles: [integer()],
    collapsed: boolean(),
    tile: integer() | nil
  }

  @type wfc_state :: %{
    grid: [[cell_state()]],
    width: integer(),
    height: integer(),
    patterns: [map()],
    pattern_weights: map(),
    adjacency_rules: map(),
    pattern_size: integer()
  }

  @doc """
  Load an image and convert it to a sample pattern for WFC.
  
  ## Parameters
  - `image_path`: Path to image file
  - `tile_size`: Size of each tile in pixels (default: 1, meaning each pixel is a tile)
  
  Returns a 2D list of tile IDs (color indices).
  """
  @spec load_image(String.t(), integer()) :: {:ok, list(list(integer()))} | {:error, String.t()}
  def load_image(image_path, tile_size \\ 1) do
    try do
      if Code.ensure_loaded?(NxImage) and Code.ensure_loaded?(Nx) do
        # Load image using NxImage
        # NxImage.read/1 may return {:ok, tensor} or just tensor
        image_tensor = case NxImage.read(image_path) do
          {:ok, tensor} -> tensor
          tensor when is_struct(tensor, Nx.Tensor) -> tensor
          other -> {:error, "Unexpected return from NxImage.read: #{inspect(other)}"}
        end
        
        case image_tensor do
          {:error, reason} ->
            {:error, reason}
            
          tensor ->
            # Convert to 2D array of tile IDs
            # For simplicity, we'll use RGB values as tile IDs
            # In a full implementation, we'd quantize colors or use a color palette
            sample = image_to_sample(tensor, tile_size)
            {:ok, sample}
        end
      else
        {:error, "NxImage or Nx not available. Add {:nx_image, \"~> 0.1.2\"} and {:nx, \"~> 0.9\"} to your dependencies."}
      end
    rescue
      e ->
        {:error, "Error loading image: #{inspect(e)}"}
    end
  end

  # Convert Nx tensor to 2D sample array
  defp image_to_sample(image_tensor, tile_size) do
    # Get image dimensions
    shape = Nx.shape(image_tensor)
    {height, width, _channels} = shape
    
    # Downsample if tile_size > 1
    if tile_size > 1 do
      new_height = div(height, tile_size)
      new_width = div(width, tile_size)
      
      # Extract tiles and convert to IDs
      for y <- 0..(new_height - 1) do
        for x <- 0..(new_width - 1) do
          # Get tile region
          y_start = y * tile_size
          x_start = x * tile_size
          
          # Extract tile and compute average color
          tile_region = Nx.slice(image_tensor, [y_start, x_start, 0], [tile_size, tile_size, 3])
          avg_color = Nx.mean(tile_region, axes: [0, 1])
          
          # Convert RGB to a simple ID (hash of RGB values)
          rgb = Nx.to_flat_list(avg_color)
          color_to_id(rgb)
        end
      end
    else
      # Each pixel is a tile
      for y <- 0..(height - 1) do
        for x <- 0..(width - 1) do
          pixel = Nx.slice(image_tensor, [y, x, 0], [1, 1, 3])
          rgb = Nx.to_flat_list(pixel)
          color_to_id(rgb)
        end
      end
    end
  end

  # Convert RGB color to a simple integer ID
  # TODO: Implement proper color quantization using color palette or k-means clustering
  #       Current simple RGB hash doesn't handle similar colors well
  defp color_to_id([r, g, b]) do
    # Simple hash: combine RGB into a single integer
    # This is a simplified approach - in production, you'd want proper color quantization
    round(r * 65536 + g * 256 + b)
  end

  defp color_to_id(_), do: 0

  @doc """
  Initialize WFC from a sample pattern.
  
  ## Parameters
  - `sample`: 2D list of tile IDs representing the input sample (or image path as string)
  - `pattern_size`: Size of patterns to extract (default: 3)
  - `output_width`: Width of output grid
  - `output_height`: Height of output grid
  """
  @spec init(list(list(integer())) | String.t(), integer(), integer(), integer()) :: {:ok, wfc_state()} | {:error, String.t()}
  def init(sample, pattern_size \\ 3, output_width, output_height)
  
  def init(sample, pattern_size, output_width, output_height) when is_binary(sample) do
    # If sample is a string, treat it as an image path
    case load_image(sample) do
      {:ok, image_sample} ->
        init(image_sample, pattern_size, output_width, output_height)
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  def init(sample, pattern_size, output_width, output_height) when is_list(sample) do
    # Extract patterns from sample
    patterns = extract_patterns(sample, pattern_size)
    
    # Calculate pattern weights (frequency)
    pattern_weights = calculate_pattern_weights(patterns)
    
    # Build adjacency rules (which patterns can be neighbors)
    adjacency_rules = build_adjacency_rules(patterns, pattern_size)
    
    # Initialize grid with all cells in superposition (all patterns possible)
    all_pattern_ids = Map.keys(pattern_weights) |> Enum.sort()
    
    grid = for y <- 0..(output_height - 1) do
      for x <- 0..(output_width - 1) do
        %{
          possible_tiles: all_pattern_ids,
          collapsed: false,
          tile: nil
        }
      end
    end
    
    state = %{
      grid: grid,
      width: output_width,
      height: output_height,
      patterns: patterns,
      pattern_weights: pattern_weights,
      adjacency_rules: adjacency_rules,
      pattern_size: pattern_size
    }
    
    {:ok, state}
  end

  @doc """
  Perform one tick of WFC using MiniZinc to find and collapse the lowest entropy cell.
  
  Returns the updated state and whether the algorithm is complete.
  """
  @spec tick(wfc_state()) :: {:ok, wfc_state(), boolean()} | {:error, String.t()}
  def tick(state) do
    # Check if already complete
    if all_collapsed?(state) do
      {:ok, state, true}
    else
      # Use MiniZinc to find cell to collapse and what value to assign
      case solve_tick(state) do
        {:ok, %{cell_x: x, cell_y: y, tile: tile}} ->
          # Collapse the cell
          new_state = collapse_cell(state, x, y, tile)
          
          # Propagate constraints
          new_state = propagate_constraints(new_state, x, y)
          
          complete = all_collapsed?(new_state)
          {:ok, new_state, complete}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Run WFC until completion or contradiction.
  
  Returns the final state and list of intermediate states.
  """
  @spec run(wfc_state(), integer()) :: {:ok, wfc_state(), [wfc_state()]} | {:error, String.t()}
  def run(state, max_iterations \\ 1000) do
    run_loop(state, [], 0, max_iterations)
  end

  defp run_loop(state, history, iteration, max_iterations) when iteration >= max_iterations do
    {:error, "Max iterations reached"}
  end

  defp run_loop(state, history, iteration, max_iterations) do
    case tick(state) do
      {:ok, new_state, true} ->
        # Complete
        {:ok, new_state, Enum.reverse([new_state | history])}
        
      {:ok, new_state, false} ->
        # Continue
        run_loop(new_state, [new_state | history], iteration + 1, max_iterations)
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract all NxN patterns from sample
  defp extract_patterns(sample, n) do
    height = length(sample)
    width = if height > 0, do: length(hd(sample)), else: 0
    
    patterns = for y <- 0..(height - n) do
      for x <- 0..(width - n) do
        extract_pattern_at(sample, x, y, n)
      end
    end
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.map(fn {pattern, id} -> %{id: id, pattern: pattern} end)
  end

  defp extract_pattern_at(sample, x, y, n) do
    for dy <- 0..(n - 1) do
      row = Enum.at(sample, y + dy)
      for dx <- 0..(n - 1) do
        Enum.at(row, x + dx)
      end
    end
  end

  # Calculate frequency weights for each pattern
  # TODO: Count actual pattern occurrences in the sample to calculate frequency-based weights
  #       Currently assumes equal weight for all patterns, which doesn't reflect sample distribution
  defp calculate_pattern_weights(patterns) do
    # Count occurrences (for now, assume equal weight)
    # In a full implementation, we'd count actual occurrences
    patterns
    |> Enum.map(fn %{id: id} -> {id, 1.0} end)
    |> Map.new()
  end

  # Build adjacency rules: which patterns can be neighbors in each direction
  defp build_adjacency_rules(patterns, n) do
    # For each pattern, find compatible neighbors
    rules = for pattern <- patterns do
      compatible = find_compatible_patterns(patterns, pattern, n)
      {pattern.id, compatible}
    end
    |> Map.new()
    
    # Build directional adjacency (up, right, down, left)
    %{
      up: build_directional_rules(patterns, n, :up),
      right: build_directional_rules(patterns, n, :right),
      down: build_directional_rules(patterns, n, :down),
      left: build_directional_rules(patterns, n, :left)
    }
  end

  # TODO: Implement proper edge compatibility checking
  #       Should check if pattern edges match when placed as neighbors in each direction
  #       Currently returns all patterns, which allows invalid adjacencies
  defp find_compatible_patterns(patterns, pattern, n) do
    # Find patterns that can be neighbors
    # Simplified: return all for now
    Enum.map(patterns, & &1.id)
  end

  # TODO: Implement proper edge matching for each direction (up, right, down, left)
  #       Should extract pattern edges and check compatibility when patterns are neighbors
  #       Currently allows all patterns as neighbors, which doesn't enforce proper constraints
  defp build_directional_rules(patterns, n, direction) do
    # Build rules for which patterns can be neighbors in a given direction
    # This is a simplified version - full implementation would check edge compatibility
    rules = for pattern <- patterns do
      # For now, allow all patterns as neighbors
      compatible = Enum.map(patterns, & &1.id)
      {pattern.id, compatible}
    end
    Map.new(rules)
  end

  # Use MiniZinc to solve one tick: find cell with lowest entropy and what to collapse it to
  defp solve_tick(state) do
    # First, find cell with minimum entropy using Elixir (simpler)
    {x, y, possible_tiles} = find_min_entropy_cell(state)
    
    if x == nil do
      {:error, "No uncollapsed cells found"}
    else
      # Use MiniZinc to select which tile to collapse to (weighted by frequency)
      model = build_tile_selection_model(possible_tiles, state.pattern_weights)
      
      # Validate model first using the validation tool
      case Solver.validate_string(model) do
        {:ok, %{"valid" => true}} ->
          # Model is valid, proceed to solve
          case Solver.solve_string(model) do
        {:ok, solution} ->
          # Extract selected tile
          tile = Map.get(solution, :selected_tile) || Map.get(solution, "selected_tile")
          
          if tile != nil and tile in possible_tiles do
            {:ok, %{cell_x: x, cell_y: y, tile: tile}}
          else
            # Fallback: select first possible tile
            {:ok, %{cell_x: x, cell_y: y, tile: List.first(possible_tiles)}}
          end
          
            {:error, _reason} ->
              # Fallback: select first possible tile
              {:ok, %{cell_x: x, cell_y: y, tile: List.first(possible_tiles)}}
          end
          
        {:ok, %{"valid" => false, "errors" => errors}} ->
          # Model validation failed, use fallback
          Logger.warning("WFC MiniZinc model validation failed: #{inspect(errors)}")
          {:ok, %{cell_x: x, cell_y: y, tile: List.first(possible_tiles)}}
          
        {:error, _reason} ->
          # Validation error, use fallback
          {:ok, %{cell_x: x, cell_y: y, tile: List.first(possible_tiles)}}
      end
    end
  end

  # Find cell with minimum entropy (fewest possibilities)
  defp find_min_entropy_cell(state) do
    min_entropy = state.grid
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, y} ->
      Enum.with_index(row)
      |> Enum.map(fn {cell, x} ->
        {x, y, cell}
      end)
    end)
    |> Enum.filter(fn {_x, _y, cell} -> not cell.collapsed end)
    |> Enum.map(fn {x, y, cell} ->
      entropy = calculate_entropy(cell.possible_tiles, state.pattern_weights)
      {x, y, cell.possible_tiles, entropy}
    end)
    |> Enum.min_by(fn {_x, _y, _tiles, entropy} -> entropy end, fn -> nil end)
    
    case min_entropy do
      {x, y, tiles, _entropy} -> {x, y, tiles}
      nil -> {nil, nil, []}
    end
  end

  # Calculate Shannon entropy for a set of possible tiles
  defp calculate_entropy(possible_tiles, weights) do
    if length(possible_tiles) == 0 do
      :infinity
    else
      # Calculate sum of weights
      sum_weights = Enum.reduce(possible_tiles, 0.0, fn tile, acc ->
        weight = Map.get(weights, tile, 1.0)
        acc + weight
      end)
      
      if sum_weights == 0.0 do
        :infinity
      else
        # Shannon entropy: -sum(p * log(p))
        entropy = Enum.reduce(possible_tiles, 0.0, fn tile, acc ->
          weight = Map.get(weights, tile, 1.0)
          p = weight / sum_weights
          if p > 0.0 do
            acc - p * :math.log(p)
          else
            acc
          end
        end)
        
        entropy
      end
    end
  end

  # Build MiniZinc model to select a tile weighted by frequency
  # TODO: Implement weighted random selection using pattern weights
  #       Current model uses simple satisfy, should use weighted probability distribution
  #       Consider implementing weighted selection in Elixir if MiniZinc doesn't support it well
  defp build_tile_selection_model(possible_tiles, weights) do
    num_tiles = length(possible_tiles)
    
    if num_tiles == 0 do
      # No tiles to select
      """
      var int: selected_tile;
      constraint false;
      solve satisfy;
      """
    else
      # Build weight array for possible tiles
      tile_weights = Enum.map(possible_tiles, fn tile ->
        weight = Map.get(weights, tile, 1.0)
        Float.to_string(weight)
      end)
      
      weights_str = "[" <> Enum.join(tile_weights, ", ") <> "]"
      tiles_str = "[" <> Enum.join(possible_tiles, ", ") <> "]"
      
      # Model: select tile with probability proportional to weight
      # We'll use a simple approach: maximize weighted selection
      """
      % Wave Function Collapse - Tile Selection Model
      % Select a tile from possible tiles, weighted by frequency
      
      int: num_tiles = #{num_tiles};
      array[1..num_tiles] of int: tiles = #{tiles_str};
      array[1..num_tiles] of float: weights = #{weights_str};
      
      var 1..num_tiles: tile_index;
      var int: selected_tile;
      
      constraint selected_tile = tiles[tile_index];
      
      % For now, just satisfy (we'll use weighted random in Elixir)
      % In a full implementation, we'd model weighted selection
      solve satisfy;
      """
    end
  end

  # Get cell at position
  defp get_cell(state, x, y) do
    row = Enum.at(state.grid, y)
    if row, do: Enum.at(row, x), else: nil
  end

  # Collapse a cell to a specific tile
  defp collapse_cell(state, x, y, tile) do
    row = Enum.at(state.grid, y)
    cell = Enum.at(row, x)
    
    new_cell = %{
      cell |
      possible_tiles: [tile],
      collapsed: true,
      tile: tile
    }
    
    new_row = List.replace_at(row, x, new_cell)
    new_grid = List.replace_at(state.grid, y, new_row)
    
    %{state | grid: new_grid}
  end

  # Propagate constraints to neighbors
  defp propagate_constraints(state, x, y) do
    # Get the collapsed tile
    cell = get_cell(state, x, y)
    tile = cell.tile
    
    # Get adjacency rules for this tile
    rules = state.adjacency_rules
    
    # Update neighbors based on adjacency rules
    neighbors = [
      {x, y - 1, :up},      # Up
      {x + 1, y, :right},   # Right
      {x, y + 1, :down},    # Down
      {x - 1, y, :left}     # Left
    ]
    
    new_state = Enum.reduce(neighbors, state, fn {nx, ny, direction}, acc ->
      if nx >= 0 and nx < acc.width and ny >= 0 and ny < acc.height do
        neighbor_cell = get_cell(acc, nx, ny)
        
        if not neighbor_cell.collapsed do
          # Get compatible tiles for this direction
          direction_rules = Map.get(rules, direction, %{})
          compatible = Map.get(direction_rules, tile, [])
          
          # Intersect with current possibilities
          new_possible = Enum.filter(neighbor_cell.possible_tiles, fn t ->
            t in compatible
          end)
          
          if length(new_possible) < length(neighbor_cell.possible_tiles) do
            # Update neighbor
            new_neighbor = %{
              neighbor_cell |
              possible_tiles: new_possible
            }
            
            row = Enum.at(acc.grid, ny)
            new_row = List.replace_at(row, nx, new_neighbor)
            new_grid = List.replace_at(acc.grid, ny, new_row)
            
            %{acc | grid: new_grid}
          else
            acc
          end
        else
          acc
        end
      else
        acc
      end
    end)
    
    new_state
  end

  # Check if all cells are collapsed
  defp all_collapsed?(state) do
    Enum.all?(state.grid, fn row ->
      Enum.all?(row, & &1.collapsed)
    end)
  end

  @doc """
  Get the final output grid as a 2D list of tile IDs.
  """
  @spec get_output(wfc_state()) :: [[integer()]]
  def get_output(state) do
    Enum.map(state.grid, fn row ->
      Enum.map(row, fn cell ->
        if cell.collapsed and cell.tile != nil do
          cell.tile
        else
          nil
        end
      end)
    end)
  end
end

