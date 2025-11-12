# PCG MCP Server

A Model Context Protocol (MCP) server that provides Wave Function Collapse (WFC) for procedural content generation.

## Features

- Wave Function Collapse (WFC) algorithm for procedural level generation
- Pattern extraction from sample images or arrays
- Frequency-based pattern weights
- Edge-compatible adjacency rules
- Support for image-based samples (when nx_image is available)
- JSON-RPC 2.0 protocol support via STDIO or HTTP transports
- Server-Sent Events (SSE) support for streaming responses

Note: MiniZinc is used internally by WFC but is not exposed as a direct tool.

## Quick Start

### Prerequisites

- Elixir 1.18+
- MiniZinc installed and available in PATH (used internally by WFC)

> **Note**: MiniZinc is automatically installed in the Docker image.

### Installation

```bash
git clone <repository-url>
cd pcg-mcp
mix deps.get
mix compile
```

## Usage

### STDIO Transport (Default)

For local development:

```bash
mix mcp.server
```

Or using release:

```bash
./_build/prod/rel/pcg_mcp/bin/pcg_mcp start
```

### HTTP Transport

For web deployments (e.g., Smithery):

```bash
PORT=8081 MIX_ENV=prod ./_build/prod/rel/pcg_mcp/bin/pcg_mcp start
```

**Endpoints:**

- `POST /` - JSON-RPC 2.0 MCP requests
- `GET /sse` - Server-Sent Events for streaming
- `GET /health` - Health check

### Docker

```bash
docker build -t minizinc-mcp .
docker run -d -p 8081:8081 --name minizinc-mcp minizinc-mcp
```

## Tools

The server provides the following MCP tools:

### Wave Function Collapse Tools (Primary)

### MiniZinc Tools (Advanced/Utility)

#### `minizinc_solve`

Solve a MiniZinc model using the chuffed solver (fixed, not configurable).

**Parameters:**
- `model_content` (string, required): MiniZinc model content (.mzn) as string
- `data_content` (string, optional): DZN data content as string (e.g., `"n = 8;"`). Must be valid DZN format. Parsed and included in response as `input_data` field.
- `timeout` (integer, optional): Optional timeout in milliseconds (default: 30000, i.e., 30 seconds). Maximum allowed is 30000 ms (30 seconds); values exceeding this will be capped at 30 seconds.
- `auto_include_stdlib` (boolean, optional): Automatically include standard MiniZinc libraries (e.g., `alldifferent.mzn`) if not present (default: `true`)

#### `minizinc_validate`

Validate a MiniZinc model by checking syntax and type checking without solving. Useful for debugging models before attempting to solve them.

**Parameters:**
- `model_content` (string, required): MiniZinc model content (.mzn) as string
- `data_content` (string, optional): DZN data content as string (e.g., `"n = 8;"`). Must be valid DZN format.
- `auto_include_stdlib` (boolean, optional): Automatically include standard MiniZinc libraries (e.g., `alldifferent.mzn`) if not present (default: `true`)

**Response Format:**
- `valid` (boolean): Whether the model is valid
- `errors` (array): List of error messages (if any)
- `warnings` (array): List of warning messages (if any)
- `message` (string): Human-readable message (when valid)
- `raw_output` (string): Raw MiniZinc validation output (when invalid)

### Wave Function Collapse Tools

#### `wfc_init`

Initialize a Wave Function Collapse generator from a sample pattern. Extracts patterns, calculates weights, and builds adjacency rules.

**Parameters:**
- `sample` (array or string, required): Either a 2D array of tile IDs `[[1,1,1],[1,0,1],[1,1,1]]` or a path to an image file
- `pattern_size` (integer, optional): Size of patterns to extract (default: 3)
- `output_width` (integer, required): Width of output grid
- `output_height` (integer, required): Height of output grid
- `tile_size` (integer, optional): Size of each tile in pixels when loading from image (default: 1)

**Returns:** WFC state object with grid, patterns, weights, and adjacency rules

#### `wfc_tick`

Perform one iteration of Wave Function Collapse. Finds the cell with lowest entropy and collapses it to a tile.

**Parameters:**
- `state` (object, required): WFC state from `wfc_init` or previous `wfc_tick`

**Returns:** Updated WFC state and `complete` flag indicating if generation is finished

#### `wfc_run`

Run Wave Function Collapse until completion or maximum iterations reached.

**Parameters:**
- `state` (object, required): WFC state from `wfc_init`
- `max_iterations` (integer, optional): Maximum number of iterations (default: 1000)

**Returns:** Final state, history of all intermediate states, and iteration count

#### `wfc_get_output`

Extract the final output grid from a WFC state as a 2D array of tile IDs.

**Parameters:**
- `state` (object, required): WFC state (from `wfc_init`, `wfc_tick`, or `wfc_run`)

**Returns:** 2D array of tile IDs representing the generated level

<details>
<summary><strong>WFC Tool Examples</strong></summary>

**Initialize WFC from pattern:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "wfc_init",
    "arguments": {
      "sample": [[1,1,1],[1,0,1],[1,1,1]],
      "pattern_size": 2,
      "output_width": 10,
      "output_height": 10
    }
  }
}
```

**Run one tick:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "wfc_tick",
    "arguments": {
      "state": { /* state from wfc_init */ }
    }
  }
}
```

**Run to completion:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "wfc_run",
    "arguments": {
      "state": { /* state from wfc_init */ },
      "max_iterations": 500
    }
  }
}
```

**Get output:**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "wfc_get_output",
    "arguments": {
      "state": { /* state from wfc_run */ }
    }
  }
}
```

</details>

## Configuration

**Environment Variables:**

- `MCP_TRANSPORT` - Transport type (`"http"` or `"stdio"`)
- `PORT` - HTTP server port (default: 8081)
- `HOST` - HTTP server host (default: `0.0.0.0` if PORT set, else `localhost`)
- `MIX_ENV` - Environment (`prod`, `dev`, `test`)
- `ELIXIR_ERL_OPTIONS` - Erlang options (set to `"+fnu"` for UTF-8)
- `MCP_SSE_ENABLED` - Enable/disable Server-Sent Events (default: `true`, set to `"false"` to disable)

**Transport Selection:**

1. If `MCP_TRANSPORT` is set, use that transport
2. If `PORT` is set, use HTTP transport
3. Otherwise, use STDIO transport (default)

## Troubleshooting

**MiniZinc not found**: Ensure MiniZinc is installed and available in PATH (required internally by WFC). For Docker, MiniZinc is included in the image.

**Port already in use**: Change `PORT` environment variable or stop conflicting services.

**Compilation errors**: Run `mix deps.get && mix clean && mix compile`.

**Debug mode**: Use `MIX_ENV=dev mix mcp.server` for verbose logging.

## Version

Current version: **1.0.0-dev2** (see `mix.exs` for latest version)

## Requirements

- Elixir 1.18+
- Erlang/OTP 26+
- MiniZinc 2.9.3+ installed and available in PATH (or use Docker image which includes MiniZinc)

<details>
<summary><strong>Development</strong></summary>

### Building

```bash
mix deps.get
mix compile
```

### Testing

```bash
mix test
```

### Building Release

```bash
MIX_ENV=prod mix release
```

### Running Locally

For STDIO transport (default):
```bash
mix mcp.server
```

For HTTP transport:
```bash
MCP_TRANSPORT=http PORT=8081 mix run --no-halt
```

</details>

## License

MIT License - see LICENSE.md for details.

## Copyright

Copyright (c) 2025-present K. S. Ernest (iFire) Lee


