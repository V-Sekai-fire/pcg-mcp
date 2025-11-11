# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.NativeService do
  @moduledoc """
  Native BEAM service for MiniZinc MCP using ex_mcp library.
  Provides MiniZinc constraint programming tools via MCP protocol.
  """

  # Suppress warnings from ex_mcp DSL generated code
  @compile {:no_warn_undefined, :no_warn_pattern}

  use ExMCP.Server,
    name: "MiniZinc MCP Server",
    version: "1.0.0"

  alias MiniZincMcp.Solver
  alias MiniZincMcp.Converter

  # Define MiniZinc tools using ex_mcp DSL
  deftool "minizinc_convert_domain" do
    meta do
      name("Convert Domain to MiniZinc")
      description("Converts a planning domain to MiniZinc format")
    end

    input_schema(%{
      type: "object",
      properties: %{
        domain: %{
          type: "object",
          description: "Planning domain to convert (map with commands, tasks, multigoals, predicates, entities)"
        }
      },
      required: ["domain"]
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
    })
  end

  deftool "minizinc_convert_command" do
    meta do
      name("Convert Command to MiniZinc")
      description("Converts a command module or map to MiniZinc format")
    end

    input_schema(%{
      type: "object",
      properties: %{
        command: %{
          type: "object",
          description: "Command to convert (module name as string, or map with name, preconditions, effects)"
        }
      },
      required: ["command"]
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
    })
  end

  deftool "minizinc_convert_task" do
    meta do
      name("Convert Task to MiniZinc")
      description("Converts a task module or map to MiniZinc format")
    end

    input_schema(%{
      type: "object",
      properties: %{
        task: %{
          type: "object",
          description: "Task to convert (module name as string, or map with name, decomposition)"
        }
      },
      required: ["task"]
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
    })
  end

  deftool "minizinc_convert_multigoal" do
    meta do
      name("Convert Multigoal to MiniZinc")
      description("Converts a multigoal module or map to MiniZinc format")
    end

    input_schema(%{
      type: "object",
      properties: %{
        multigoal: %{
          type: "object",
          description: "Multigoal to convert (module name as string, or map with name, predicate)"
        }
      },
      required: ["multigoal"]
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
    })
  end

  deftool "minizinc_solve" do
    meta do
      name("Solve MiniZinc Model")
      description("Solves a MiniZinc model file or string content")
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
          description: "MiniZinc model content as string (alternative to model_path)"
        },
        data_path: %{
          type: "string",
          description: "Optional path to .dzn data file"
        },
        data_content: %{
          type: "string",
          description: "Optional .dzn data content as string"
        },
        solver: %{
          type: "string",
          description: "Solver name (default: chuffed)",
          default: "chuffed"
        },
        timeout: %{
          type: "integer",
          description: "Timeout in milliseconds (default: 60000)",
          default: 60_000
        }
      }
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: false
    })
  end

  deftool "minizinc_list_solvers" do
    meta do
      name("List Available Solvers")
      description("Lists all available MiniZinc solvers")
    end

    input_schema(%{
      type: "object",
      properties: %{}
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
    })
  end

  deftool "minizinc_check_available" do
    meta do
      name("Check MiniZinc Availability")
      description("Checks if MiniZinc is available on the system")
    end

    input_schema(%{
      type: "object",
      properties: %{}
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
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
    case tool_name do
      "minizinc_convert_domain" ->
        handle_convert_domain(args, state)

      "minizinc_convert_command" ->
        handle_convert_command(args, state)

      "minizinc_convert_task" ->
        handle_convert_task(args, state)

      "minizinc_convert_multigoal" ->
        handle_convert_multigoal(args, state)

      "minizinc_solve" ->
        handle_solve(args, state)

      "minizinc_list_solvers" ->
        handle_list_solvers(state)

      "minizinc_check_available" ->
        handle_check_available(state)

      _ ->
        {:error, "Tool not found: #{tool_name}", state}
    end
  end

  defp handle_convert_domain(args, state) do
    domain = args["domain"]

    case Converter.convert_domain(domain) do
      {:ok, minizinc_code} ->
        {:ok, %{content: [text(minizinc_code)]}, state}

      {:error, reason} ->
        {:error, "Failed to convert domain: #{reason}", state}
    end
  end

  defp handle_convert_command(args, state) do
    command = args["command"]

    case Converter.convert_command(command) do
      {:ok, minizinc_code} ->
        {:ok, %{content: [text(minizinc_code)]}, state}

      {:error, reason} ->
        {:error, "Failed to convert command: #{reason}", state}
    end
  end

  defp handle_convert_task(args, state) do
    task = args["task"]

    case Converter.convert_task(task) do
      {:ok, minizinc_code} ->
        {:ok, %{content: [text(minizinc_code)]}, state}

      {:error, reason} ->
        {:error, "Failed to convert task: #{reason}", state}
    end
  end

  defp handle_convert_multigoal(args, state) do
    multigoal = args["multigoal"]

    case Converter.convert_multigoal(multigoal) do
      {:ok, minizinc_code} ->
        {:ok, %{content: [text(minizinc_code)]}, state}

      {:error, reason} ->
        {:error, "Failed to convert multigoal: #{reason}", state}
    end
  end

  defp handle_solve(args, state) do
    model_path = args["model_path"]
    model_content = args["model_content"]
    data_path = args["data_path"]
    data_content = args["data_content"]
    solver = Map.get(args, "solver", "chuffed")
    timeout = Map.get(args, "timeout", 60_000)

    opts = [solver: solver, timeout: timeout]

    result =
      cond do
        model_content ->
          # Solve from string content
          Solver.solve_string(model_content, data_content, opts)

        model_path ->
          # Solve from file
          Solver.solve(model_path, data_path, opts)

        true ->
          {:error, "Either model_path or model_content must be provided"}
      end

    case result do
      {:ok, solution} ->
        solution_json = Jason.encode!(solution)
        {:ok, %{content: [text(solution_json)]}, state}

      {:error, reason} ->
        {:error, "Failed to solve model: #{reason}", state}
    end
  end

  defp handle_list_solvers(state) do
    case Solver.list_solvers() do
      {:ok, solvers} ->
        solvers_json = Jason.encode!(solvers)
        {:ok, %{content: [text(solvers_json)]}, state}

      {:error, reason} ->
        {:error, "Failed to list solvers: #{reason}", state}
    end
  end

  defp handle_check_available(state) do
    available = Solver.available?()
    result = %{available: available}
    result_json = Jason.encode!(result)
    {:ok, %{content: [text(result_json)]}, state}
  end
end

