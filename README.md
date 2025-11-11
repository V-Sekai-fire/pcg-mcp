# MiniZinc MCP Server

A Model Context Protocol (MCP) server that provides MiniZinc constraint programming capabilities.

## Features

- Convert planning domains to MiniZinc format
- Convert commands, tasks, and multigoals to MiniZinc
- Solve MiniZinc models using various solvers
- List available MiniZinc solvers
- Check MiniZinc availability

## Installation

This is a standalone MCP server. To use it:

1. Navigate to the `thirdparty/minizinc-mcp/` directory
2. Install dependencies: `mix deps.get`
3. Run the server: `mix mcp.server`

## Usage

The server can run in two modes:

- **Stdio mode** (default): Communicates via stdin/stdout
- **HTTP mode**: Set `MCP_TRANSPORT=http` and `PORT=<port>` environment variables

## Tools

The server provides the following MCP tools:

- `minizinc_convert_domain` - Convert a planning domain to MiniZinc
- `minizinc_convert_command` - Convert a command to MiniZinc
- `minizinc_convert_task` - Convert a task to MiniZinc
- `minizinc_convert_multigoal` - Convert a multigoal to MiniZinc
- `minizinc_solve` - Solve a MiniZinc model
- `minizinc_list_solvers` - List available solvers
- `minizinc_check_available` - Check if MiniZinc is available

## Requirements

- Elixir 1.18+
- MiniZinc installed and available in PATH

