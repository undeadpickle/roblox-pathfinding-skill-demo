# RobloxPathfindingSkillDemo

A Roblox project built with Rojo.

## About

- **Game type:** General / undecided
- **Session format:** Undecided
- **Platform:** Cross-platform
- **Architecture:** Layered structure
- **Authority model:** Client-trusted (prototype)
- **Persistence:** None

## Setup

### Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) — Toolchain manager
- [Roblox Studio](https://create.roblox.com/) — With Rojo plugin installed
- [VS Code](https://code.visualstudio.com/) — Recommended editor

### Installation

```bash
# Clone the repo
git clone <repo-url>
cd RobloxPathfindingSkillDemo

# Install tools (via Rokit)
rokit install

# Install Wally packages
wally install
```

### Development

```bash
# Start Rojo sync server
rojo serve
```

Then in Roblox Studio:
1. Open an empty baseplate or existing place
2. Rojo plugin > Connect

### Building

```bash
# Build .rbxl file
rojo build -o build.rbxl
```

## Project Structure

```
RobloxPathfindingSkillDemo/
├── src/
│   ├── client/          # Client-side scripts
│   ├── server/          # Server-side scripts
│   ├── shared/          # Shared modules
│   └── replicatedFirst/ # Early client code (loading screens)
├── Packages/            # Wally dependencies
├── default.project.json # Rojo project config
├── wally.toml           # Package manifest
└── game.rbxl            # Place file (optional)
```

## Scripts

| Command | Description |
|---------|-------------|
| `rojo serve` | Start sync server |
| `rojo build -o build.rbxl` | Build place file |
| `wally install` | Install dependencies |
| `selene src/` | Lint code |
| `stylua src/` | Format code |

## License

<!-- Add your license here -->
