# Aardwolf QuickStab Plugin

Automatically uses spiral after backstab when the quickstab skill is active.

## Why?

When quickstab (Sn: 601) is active, you can use spiral in the same round as backstab. But if backstab kills the mob, spiraling wastes the opportunity to backstab the next mob immediately.

This plugin solves that by detecting mob death and canceling spiral when appropriate.

## Behavior

| Scenario | Action |
|----------|--------|
| Backstab hits, mob survives | Spiral fires after delay |
| Backstab misses | Spiral fires after delay |
| Backstab kills mob | Spiral canceled |
| "Refuses second backstab" | Spiral fires immediately* |
| Other failures (in combat) | Spiral fires |
| Other failures (not in combat) | No spiral |

*Works even without quickstab active*

A 3-second cooldown prevents accidental double-spiral.

## Installation

1. Copy the `aardwolf_quickstab` folder to your MUSHclient plugins directory
2. In MUSHclient: File → Plugins → Add
3. Select `aardwolf_quickstab.xml`

## Commands

| Command | Description |
|---------|-------------|
| `qstab` | Show status |
| `qstab on/off` | Enable/disable plugin |
| `qstab window` | Toggle status window |
| `qstab delay [ms]` | Set/show spiral delay (0-1000ms, default 300) |
| `qstab reset` | Reset window position |
| `qstab refresh` | Re-query quickstab state from slist |
| `qstab debug` | Toggle debug output |
| `qstab reload` | Reload plugin |

## Status Window

A small status window shows whether quickstab is active. Toggle with `qstab window`.

## Requirements

- MUSHclient 5.07+
- Aardwolf GMCP handler plugin (`aard_GMCP_handler.xml`)
- Ninja subclass with quickstab skill

## Troubleshooting

**Spiral not firing:**
- Run `qstab` to check plugin status
- Use `qstab debug` for detailed logging
- Use `qstab refresh` to re-query quickstab state

**Spiral firing after mob dies:**
- Increase delay with `qstab delay 400` (or higher)
- This gives more time for death detection

**Plugin not detecting quickstab:**
- Run `qstab refresh` to manually query slist
- Check that quickstab skill is active in-game

## How It Works

1. On connect, enables `TELOPT_SPELLUP` for `{affon}/{affoff}` tags
2. Queries `slist affected` to detect if quickstab is already active
3. When `{affon}601` received, enables backstab detection
4. On backstab, waits configurable delay (default 300ms) before spiral
5. If death message detected during delay, cancels spiral
6. When `{affoff}601` received, disables backstab triggers
