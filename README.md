# PCG MCP Server

A Model Context Protocol (MCP) server that provides Wave Function Collapse (WFC) for procedural content generation.

> **⚠️ Status: Early Development / Not Production Ready**
> 
> This project is in active development and has several known limitations:
> 
> - **Image Processing**: Image loading requires optional dependencies (`nx_image`, `nx`) and is not available by default. Color quantization is simplified and may not work well with complex images.
> - **Error Handling**: Error handling and extraction from MiniZinc output could be improved. Some edge cases in DZN parsing are not fully handled.
> - **WFC Limitations**: No backtracking support - contradictions cause errors rather than automatic recovery. State serialization validation is missing.
> - **Build Issues**: Docker build includes a workaround for `gen_state_machine` OTP 26 compatibility issues.
> - **Testing**: While all tests pass, the codebase has type warnings from dependencies and needs more comprehensive edge case testing.
> 
> **Use at your own risk.** This is experimental software suitable for development and testing purposes only.

## Features

- **Wave Function Collapse (WFC)** - Procedural level generation algorithm
  - Pattern extraction from sample images or arrays
  - Frequency-based pattern weights
  - Edge-compatible adjacency rules
  - Support for image-based samples (when nx_image is available)
- **MiniZinc Constraint Programming** - Advanced constraint solving
  - Solve MiniZinc models using chuffed solver
  - Validate MiniZinc models
  - Automatic standard library inclusion
- **MCP Protocol Support**
  - JSON-RPC 2.0 protocol via STDIO or HTTP transports
  - Server-Sent Events (SSE) support for streaming responses
- **Command Line Tools**
  - `mix pcg.generate` - Generate PCG levels from command line

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
docker build -t pcg-mcp .
docker run -d -p 8081:8081 --name pcg-mcp pcg-mcp
```

## Tools

The server provides the following MCP tools:

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

<details>
<summary><strong>MiniZinc Tool Examples</strong></summary>

**Solve a simple model:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "minizinc_solve",
    "arguments": {
      "model_content": "var int: x; constraint x > 0; constraint x < 10; solve satisfy;"
    }
  }
}
```

**Validate a model:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "minizinc_validate",
    "arguments": {
      "model_content": "var int: x; constraint x > 0; solve satisfy;"
    }
  }
}
```

</details>

### Wave Function Collapse Tools (Primary)

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
# Run all tests
mix test

# Run specific test suites
mix test test/beam_server_*.exs  # BEAM server integration tests
mix test test/wfc_test.exs       # WFC unit tests
mix test test/adhoc_test.exs     # Adhoc tests
```

**Test Structure:**
- `test/beam_server_minizinc_test.exs` - MiniZinc tool tests via BEAM server
- `test/beam_server_wfc_test.exs` - WFC tool tests via BEAM server
- `test/beam_server_integration_test.exs` - Full workflow integration tests
- `test/beam_server_error_test.exs` - Error handling tests
- `test/wfc_test.exs` - WFC unit tests with fixtures
- `test/adhoc_test.exs` - Interactive adhoc tests

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

### Generating Levels

Use the Mix task to generate PCG levels:

```bash
# Default: simple pattern, 30x20
mix pcg.generate

# Custom pattern and size
mix pcg.generate simple 25 15
mix pcg.generate checkerboard 30 20
mix pcg.generate dungeon 40 25
```

Available patterns: `simple`, `checkerboard`, `dungeon`

</details>

## License

MIT License - see LICENSE.md for details.

## Copyright

Copyright (c) 2025-present K. S. Ernest (iFire) Lee


