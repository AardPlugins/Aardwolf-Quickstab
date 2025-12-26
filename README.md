# Aardwolf QuickStab Plugin

MUSHclient plugin that automatically uses spiral after backstab when the quickstab skill is active.

## Problem

When quickstab (Sn: 601) is active, you can use spiral in the same round as backstab. However, if backstab kills the mob, using spiral wastes the opportunity to backstab the next mob.

## Solution

This plugin tracks backstab results and only sends spiral when appropriate:

| Scenario | Action |
|----------|--------|
| Backstab hits, mob survives | Spiral fires after short delay |
| Backstab misses | Spiral fires after short delay |
| Backstab kills mob | Spiral is canceled |
| "Refuses second backstab" | Spiral fires immediately |
| Other failures (while fighting) | Spiral fires |
| Other failures (not fighting) | No spiral |

## Installation

1. Copy the `aardwolf_quickstab` folder to your MUSHclient plugins directory
2. In MUSHclient: File → Plugins → Add
3. Select `aardwolf_quickstab.xml`

## Commands

| Command | Description |
|---------|-------------|
| `qs` | Show status |
| `qs on` | Enable plugin |
| `qs off` | Disable plugin |
| `qs refresh` | Refresh quickstab state from slist |
| `qs debug` | Toggle debug output |
| `qs reload` | Reload plugin |
| `qs help` | Show help |

## How It Works

1. Plugin enables `TELOPT_SPELLUP` to receive `{affon}` / `{affoff}` tags
2. On connect, queries `slist affected` to check if quickstab is already active
3. When `{affon}601` is received, enables backstab detection triggers
4. When backstab executes, starts a 150ms timer before sending spiral
5. If a death message is detected during that window, cancels the spiral
6. When `{affoff}601` is received, disables backstab triggers

## Files

```
aardwolf_quickstab/
├── aardwolf_quickstab.xml           # Plugin definition
├── aardwolf_quickstab_init.lua      # Bootstrap, constants, utilities
├── aardwolf_quickstab_core.lua      # State machine, event handlers
├── aardwolf_quickstab_handlers.lua  # Trigger/alias callbacks
└── README.md
```

## Requirements

- MUSHclient 5.07+
- Aardwolf GMCP handler plugin (`aard_GMCP_handler.xml`)
- Ninja subclass with quickstab skill

## Troubleshooting

**Spiral not firing:**
- Check `qs status` to verify plugin is enabled and quickstab is active
- Use `qs debug` to see detailed logging
- Use `qs refresh` to re-query quickstab state

**Spiral firing when it shouldn't:**
- Check if death message pattern is missing from triggers
- Enable debug mode to see what's being detected

**Plugin not detecting quickstab:**
- Ensure spellup tags are enabled (plugin does this automatically)
- Try `qs refresh` to manually query slist

## Debug Output

Enable with `qs debug`. Example output for a successful backstab + spiral:

```
[QS Debug] Trigger: Backstab executed - *[5] Your backstab does UNBELIEVABLE things to a mob! [1234]
[QS Debug] Backstab executed, scheduling spiral
[QS Debug] Scheduling spiral in 150ms
[QS Debug] State: idle -> pending_spiral
[QS Debug] Spiral timer created successfully, waiting for death or timeout
[QS Debug] Spiral timer fired
[QS Debug] Executing spiral
[QS Debug] State: pending_spiral -> idle
```

Example output when backstab kills the mob (spiral canceled):

```
[QS Debug] Trigger: Backstab executed - *[5] Your backstab does UNBELIEVABLE things to a mob! [5678]
[QS Debug] Backstab executed, scheduling spiral
[QS Debug] Scheduling spiral in 150ms
[QS Debug] State: idle -> pending_spiral
[QS Debug] Spiral timer created successfully, waiting for death or timeout
[QS Debug] Trigger: Death message - A mob lets out a final rasp as its vital organs are pierced. It is DEAD!
[QS Debug] Death detected, current state: pending_spiral
[QS Debug] Canceling spiral: mob died from backstab
[QS Debug] State: pending_spiral -> idle
```

Example output on connect:

```
[QS Debug] OnPluginConnect called
[QS Debug] TELOPT_SPELLUP enabled
[QS Debug] Backstab triggers: disabled
[QS Debug] Connected - spellup telnet enabled, init timer started
[QS Debug] Valid game state detected (3), querying slist
[QS Debug] Refreshing quickstab state via slist...
[QS Debug] Trigger: {spellheaders} received
[QS Debug] slist capture started
[QS Debug] Trigger: {/spellheaders} received
[QS Debug] slist capture complete
[QS Debug] Quickstab not found in slist affected (not active)
```
