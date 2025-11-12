# Kenney Game Assets for Wave Function Collapse

This directory contains sprite assets downloaded from [kenney.nl](https://kenney.nl/) that are suitable for use with the Wave Function Collapse (WFC) algorithm.

## Assets Included

### Tiny Dungeon
- **Source**: https://kenney.nl/assets/tiny-dungeon
- **Tile Size**: 16×16 pixels
- **Theme**: Dungeon/Roguelike
- **License**: Creative Commons CC0
- **Location**: `tiny-dungeon/Tiles/`
- **Count**: 132 individual tile PNG files

Perfect for WFC as each tile is a separate file, making it easy to extract patterns.

## Usage with WFC

These assets can be used with the `wfc_init` tool by:
1. Loading individual tile images as samples
2. Using tile sheets as input patterns
3. Converting tiles to tile IDs for pattern extraction

The WFC implementation in `lib/pcg_mcp/wave_function_collapse.ex` supports loading images via `load_image/2` which uses `nx_image` for processing.

## License

All assets are provided under Creative Commons CC0 (Public Domain), allowing free use in commercial and non-commercial projects.
