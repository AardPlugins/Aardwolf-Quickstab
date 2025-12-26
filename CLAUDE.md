# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MUSHclient plugin for Aardwolf MUD that automatically uses spiral after backstab when the quickstab skill (Sn: 601) is active. The plugin tracks backstab results and cancels spiral if the mob dies (preserving the backstab opportunity for the next mob).

Key features:
- Auto-spiral after backstab (hit or miss) when quickstab is active
- Death detection cancels spiral to preserve backstab for next mob
- "Second backstab refused" triggers spiral even without quickstab active
- 3-second cooldown prevents double-spiral
- Configurable delay (default 300ms) for death detection window
- Status miniwindow showing plugin state

## Plugin Architecture

### Load Order
```
XML → aardwolf_quickstab_init.lua → aardwolf_quickstab_core.lua → aardwolf_quickstab_handlers.lua
```

### File Responsibilities
- **aardwolf_quickstab.xml**: Plugin definition with aliases, triggers (grouped), and timers
- **aardwolf_quickstab_init.lua**: Bootstrap, constants, shared utilities (`gmcp()`, logging), telnet option setup, window config
- **aardwolf_quickstab_core.lua**: State machine, event handlers (`on_*` functions), trigger group management, window functions
- **aardwolf_quickstab_handlers.lua**: All MUSHclient callbacks - must be global functions matching XML script attributes

### State Machine
```
IDLE → (backstab executed) → PENDING_SPIRAL → (timer fires OR death detected) → IDLE
```

The configurable delay (default 300ms) between backstab and spiral allows death detection triggers to cancel the spiral if the mob died. A 3-second cooldown prevents double-spiral.

### Trigger Groups (defined in XML)
- `quickstab_slist`: Enabled temporarily during state refresh to capture `slist affected` output
- `quickstab_spellup`: Always enabled - tracks `{affon}601` / `{affoff}601` tags
- `quickstab_always`: Always enabled - handles "second backstab refused" (works without quickstab)
- `quickstab_backstab`: Enabled only when quickstab is active - detects backstab hit/miss
- `quickstab_failures`: Enabled only when quickstab is active - detects other backstab failures
- `quickstab_death`: Enabled only in `PENDING_SPIRAL` state - detects mob death messages

## Development

### Testing Changes
1. In MUSHclient: File → Plugins → right-click plugin → Reload
2. Or use: `qstab reload`
3. Enable debug output: `qstab debug`

### Key MUSHclient APIs Used
- `EnableTriggerGroup(group, bool)` - Enable/disable trigger groups
- `AddTimer()` / `DeleteTimer()` - Create/cancel one-shot timers
- `Send()` - Send command to MUD
- `SendNoEcho()` - Send without local echo (for slist query)
- `TelnetOptionOn(TELOPT_SPELLUP)` - Enable spellup tags from server
- `GetVariable()` / `SetVariable()` - Persist state across sessions

### Handler Functions Must Be Global
MUSHclient resolves XML `script="function_name"` by looking up the function in the global table:
```lua
-- CORRECT - found by MUSHclient
function trigger_backstab_executed(name, line, wildcards)

-- WRONG - won't be found
local function trigger_backstab_executed(name, line, wildcards)
```

### Adding New Death Patterns
Add triggers to the `quickstab_death` group in the XML with `script="trigger_mob_died"`. Use sequence="1" for specific patterns, sequence="10" for generic fallbacks.

## Commands
| Command | Description |
|---------|-------------|
| `qstab` | Show status |
| `qstab on/off` | Enable/disable plugin |
| `qstab window` | Toggle status miniwindow |
| `qstab delay [ms]` | Set/show spiral delay (0-1000ms) |
| `qstab reset` | Reset window position |
| `qstab debug` | Toggle debug output |
| `qstab refresh` | Re-query quickstab state from slist |
| `qstab reload` | Reload plugin |

## Dependencies
- `aard_GMCP_handler.xml` (ID: `3e7dedbe37e44942dd46d264`) - provides `gmcp()` data access
- `aardwolf_colors.lua` - color formatting
- `telnet_options.lua` - defines `TELOPT_SPELLUP`
- `constants.lua` - MUSHclient flag constants (`timer_flag`, `error_code`)
- `themed_miniwindows` - status window display
