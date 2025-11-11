# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.NativeService do
  @moduledoc """
  Native BEAM service for MiniZinc MCP using ex_mcp library.
  Provides MiniZinc constraint programming tools via MCP protocol.

  This server provides tools for:
  - Solving MiniZinc models (using chuffed solver only)

  ## Output Format

  Supports both MZN (model) and DZN (data) content as strings.

  **Solution Output:**
  - **DZN format**: When available, variables are parsed from DZN format and returned as structured data
  - **Output text**: Explicit `output` statements are passthrough'd in the `output_text` field
  - **Both**: When both formats are available, both are included in the response

  Only DZN format is parsed for variable extraction. Output text from explicit `output` statements
  is always included when available, even if DZN format is not present.
  """

  # Suppress warnings from ex_mcp DSL generated code
  @compile {:no_warn_undefined, :no_warn_pattern}

  use ExMCP.Server,
    name: "MiniZinc MCP Server",
    version: "1.0.0"

  alias MiniZincMcp.Solver

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  # Override do_start_link to start without name when no name is provided
  # This prevents conflicts when ExMCP.MessageProcessor starts temporary instances
  # MessageProcessor now handles :already_started gracefully
  defp do_start_link(:native, opts) do
    name = Keyword.get(opts, :name)

    # Only register name if explicitly provided
    # When ExMCP.MessageProcessor calls start_link([]), no name is provided,
    # so we start without name registration to avoid conflicts
    genserver_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  # Define MiniZinc tools using ex_mcp DSL

  deftool "minizinc_solve" do
    meta do
      name("Solve MiniZinc Model")
      description("""
      Solves a MiniZinc model file or string content using chuffed solver (fixed, not configurable).
      
      Standard libraries: By default, automatically includes common MiniZinc standard libraries (e.g., alldifferent.mzn) 
      if not already present in the model. This can be controlled via the auto_include_stdlib parameter (default: true).
      This allows models to use standard functions without explicit includes.
      
      Output format:
      - DZN format: Variables are parsed from DZN format when available (models without explicit output statements)
      - Output text: Explicit output statements are passthrough'd in output_text field
      - Both formats are included when available
      """)
    end

    input_schema(%{
      type: "object",
      properties: %{
        model_path: %{
          type: "string",
          description: "Path to .mzn MiniZinc model file (or use model_content for string)"
        },
        model_content: %{
          type: "string",
          description: "MiniZinc model content (.mzn) as string (alternative to model_path)"
        },
        data_path: %{
          type: "string",
          description: "Optional path to .dzn data file (alternative to data_content)"
        },
        data_content: %{
          type: "string",
          description: "Optional .dzn data content as string. Must be valid DZN format (e.g., 'n = 8;'). Parsed and included in response."
        },
        timeout: %{
          type: "integer",
          description: "Timeout in milliseconds (default: 60000)",
          default: 60_000
        },
        auto_include_stdlib: %{
          type: "boolean",
          description: "Automatically include standard MiniZinc libraries (e.g., alldifferent.mzn) if not present (default: true)",
          default: true
        }
      }
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: false
    })
  end


  # Initialize handler
  @impl true
  def handle_initialize(params, state) do
    {:ok,
     %{
       protocolVersion: Map.get(params, "protocolVersion", "2025-06-18"),
       serverInfo: %{
         name: "MiniZinc MCP Server",
         version: "1.0.0"
       },
       capabilities: %{
         tools: %{},
         resources: %{},
         prompts: %{}
       }
     }, state}
  end

  # Tool call handlers
  @impl true
  def handle_tool_call(tool_name, args, state) do
    # Use Process.flag to catch any exit signals
    Process.flag(:trap_exit, true)
    
    result = 
      try do
        case tool_name do
          "minizinc_solve" ->
            handle_solve(args, state)

          _ ->
            {:error, "Tool not found: #{tool_name}", state}
        end
      rescue
        e ->
          error_msg = "Error in handle_tool_call: #{Exception.message(e)}"
          Logger.error("#{error_msg}\n#{Exception.format(:error, e, __STACKTRACE__)}")
          {:error, error_msg, state}
      catch
        :exit, reason ->
          error_msg = "Process exited: #{inspect(reason)}"
          Logger.error(error_msg)
          {:error, error_msg, state}
        kind, reason ->
          error_msg = "Caught #{kind}: #{inspect(reason)}"
          Logger.error(error_msg)
          {:error, error_msg, state}
      end
    
    # Always return a valid tuple, even if result is unexpected
    case result do
      {:ok, response, new_state} -> {:ok, response, new_state}
      {:error, reason, new_state} -> {:error, reason, new_state}
      {:ok, response} -> {:ok, response, state}
      {:error, reason} -> {:error, reason, state}
      other ->
        Logger.error("Unexpected return from handle_tool_call: #{inspect(other)}")
        {:error, "Internal error: unexpected return format", state}
    end
  after
    Process.flag(:trap_exit, false)
  end

  defp handle_solve(args, state) do
    # Wrap everything in a function that always returns a tuple
    fn ->
      try do
        # Ensure args is a map
        args = if is_map(args), do: args, else: %{}
        
        model_path = Map.get(args, "model_path")
        model_content = Map.get(args, "model_content")
        data_path = Map.get(args, "data_path")
        data_content = Map.get(args, "data_content")
        # Only allow chuffed solver (ignore user input)
        solver = "chuffed"
        timeout = Map.get(args, "timeout", 60_000)
        auto_include_stdlib = Map.get(args, "auto_include_stdlib", true)

        opts = [solver: solver, timeout: timeout, auto_include_stdlib: auto_include_stdlib]

        result =
          cond do
            model_content && model_content != "" ->
              # Solve from string content
              Solver.solve_string(model_content, data_content, opts)

            model_path && model_path != "" ->
              # Solve from file
              Solver.solve(model_path, data_path, opts)

            true ->
              {:error, "Either model_path or model_content must be provided"}
          end

        case result do
          {:ok, solution} ->
            try do
              # Ensure all keys are strings for JSON encoding
              solution_map = if is_map(solution), do: solution, else: %{result: solution}
              solution_json = Jason.encode!(solution_map)
              # Use ExMCP.Protocol.Content.text/1 if available, otherwise create map directly
              content_item = if function_exported?(ExMCP.Protocol.Content, :text, 1) do
                ExMCP.Protocol.Content.text(solution_json)
              else
                %{type: "text", text: solution_json}
              end
              {:ok, %{content: [content_item]}, state}
            rescue
              e ->
                error_msg = "Failed to encode solution: #{Exception.message(e)}"
                Logger.error("#{error_msg}\n#{Exception.format(:error, e, __STACKTRACE__)}")
                {:error, error_msg, state}
            end

          {:error, reason} ->
            # Preserve full error message from solver for better debugging
            error_msg = if is_binary(reason), do: reason, else: to_string(reason)
            Logger.error("MiniZinc solve failed: #{error_msg}")
            {:error, error_msg, state}
        end
      rescue
        e ->
          error_msg = "Unexpected error in handle_solve: #{Exception.message(e)}"
          Logger.error("#{error_msg}\n#{Exception.format(:error, e, __STACKTRACE__)}")
          {:error, error_msg, state}
      catch
        kind, reason ->
          error_msg = "Caught #{kind} in handle_solve: #{inspect(reason)}"
          Logger.error(error_msg)
          {:error, error_msg, state}
      end
    end.()
  end

end
