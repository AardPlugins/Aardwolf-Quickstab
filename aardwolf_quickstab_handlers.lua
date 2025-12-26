-- aardwolf_quickstab_handlers.lua
-- All alias/trigger/plugin callbacks (MUST be global for MUSHclient)

-- =============================================================================
-- Plugin Lifecycle Callbacks
-- =============================================================================

-- Called when plugin is first installed
function OnPluginInstall()
    -- Load saved state first (always safe)
    load_state()

    debug_log("OnPluginInstall - IsConnected=" .. tostring(IsConnected()))

    -- If already connected, do connection-dependent init
    if IsConnected() then
        OnPluginConnect()
    end
end

-- Called when connection to MUD is established
function OnPluginConnect()
    debug_log("OnPluginConnect called")

    -- Enable spellup telnet option to receive {affon}/{affoff} tags
    -- This is safe to call multiple times
    enable_spellup_telnet()

    -- Reset quickstab state
    quickstab_active = false
    update_trigger_groups()

    -- Enable the init timer to wait for valid game state before querying slist
    EnableTimer("timer_init_plugin", true)

    debug_log("Connected - spellup telnet enabled, init timer started")
end

-- Called when plugin is re-enabled after being disabled
function OnPluginEnable()
    debug_log("OnPluginEnable - IsConnected=" .. tostring(IsConnected()))

    -- If already connected, do connection-dependent init
    if IsConnected() then
        OnPluginConnect()
    end
end

-- Called when plugin is disabled
function OnPluginDisable()
    debug_log("OnPluginDisable called")

    -- Cancel any pending spiral
    if current_state == QS_STATE.PENDING_SPIRAL then
        cancel_spiral("plugin disabled")
    end
end

function OnPluginSaveState()
    save_state()
end

function OnPluginBroadcast(msg, id, name, text)
    if id == plugin_id_gmcp_handler then
        -- We don't need to handle GMCP broadcasts for this plugin
        -- The is_fighting() check uses gmcp() directly when needed
    end
end

-- =============================================================================
-- Timer Callbacks
-- =============================================================================

-- Init timer - waits for valid game state before querying slist
function timer_init_plugin(timer_name)
    if not IsConnected() then
        return  -- Keep waiting
    end

    -- Check if we're in a valid game state (not logging in, MOTD, etc.)
    local char_state = gmcp("char.status.state")
    if char_state == nil then
        return  -- GMCP not ready yet, keep waiting
    end

    local state_num = tonumber(char_state)
    if not VALID_GAME_STATES[state_num] then
        debug_log("Waiting for valid game state (current: " .. tostring(char_state) .. ")")
        return  -- Still logging in or in invalid state, keep waiting
    end

    -- We're in a valid state - disable timer and do init
    EnableTimer("timer_init_plugin", false)

    debug_log("Valid game state detected (" .. tostring(char_state) .. "), querying slist")

    -- Query slist to check if quickstab is already active
    refresh_quickstab_state()
end

-- Spiral timer - fires spiral after delay if mob didn't die
function timer_spiral_fire(timer_name)
    debug_log("Spiral timer fired")
    execute_spiral()
end

-- =============================================================================
-- Trigger Handlers - Slist Capture
-- =============================================================================
function trigger_slist_start(name, line, wildcards)
    debug_log("Trigger: {spellheaders} received")
    on_slist_start()
end

function trigger_slist_line(name, line, wildcards)
    local sn = tonumber(wildcards[1])
    local skillname = wildcards[2]
    local target = tonumber(wildcards[3])
    local duration = tonumber(wildcards[4])
    local pct = tonumber(wildcards[5])
    local recovery = tonumber(wildcards[6])
    local skilltype = tonumber(wildcards[7])

    -- Only log if it's quickstab to avoid spam
    if sn == QUICKSTAB_SKILL_ID then
        debug_log("Trigger: slist line - sn=" .. tostring(sn) .. ", duration=" .. tostring(duration))
    end

    on_slist_line(sn, skillname, target, duration, pct, recovery, skilltype)
end

function trigger_slist_end(name, line, wildcards)
    debug_log("Trigger: {/spellheaders} received")
    on_slist_end()
end

-- =============================================================================
-- Trigger Handlers - Spellup Tags
-- =============================================================================
function trigger_quickstab_activated(name, line, wildcards)
    debug_log("Trigger: {affon}601 received")
    local duration = tonumber(wildcards[1]) or 0
    on_quickstab_activated(duration)
end

function trigger_quickstab_deactivated(name, line, wildcards)
    debug_log("Trigger: {affoff}601 received")
    on_quickstab_deactivated()
end

-- =============================================================================
-- Trigger Handlers - Backstab Execution
-- =============================================================================
function trigger_backstab_executed(name, line, wildcards)
    debug_log("Trigger: Backstab executed - " .. line)
    on_backstab_executed()
end

-- =============================================================================
-- Trigger Handlers - Backstab Failures
-- =============================================================================
function trigger_backstab_failed(name, line, wildcards)
    debug_log("Trigger: Backstab failed - " .. line)
    on_backstab_failed()
end

function trigger_backstab_refused(name, line, wildcards)
    debug_log("Trigger: Second backstab refused - " .. line)
    on_backstab_refused()
end

-- =============================================================================
-- Trigger Handlers - Death Detection
-- =============================================================================
function trigger_mob_died(name, line, wildcards)
    debug_log("Trigger: Death message - " .. line)
    on_mob_died()
end

-- =============================================================================
-- Alias Handler
-- =============================================================================
function alias_quickstab(name, line, wildcards)
    local args = wildcards[1] or ""
    local parts = {}
    for word in args:gmatch("%S+") do
        table.insert(parts, word)
    end

    local cmd = parts[1] and parts[1]:lower() or "status"

    if cmd == "help" then
        cmd_help()
    elseif cmd == "status" then
        cmd_status()
    elseif cmd == "on" then
        cmd_enable()
    elseif cmd == "off" then
        cmd_disable()
    elseif cmd == "debug" then
        cmd_debug()
    elseif cmd == "refresh" then
        cmd_refresh()
    elseif cmd == "reload" then
        cmd_reload()
    else
        info("Unknown command: " .. cmd)
        cmd_help()
    end
end

-- =============================================================================
-- Command Implementations
-- =============================================================================
function cmd_help()
    Message([[@WQuickStab Plugin v]] .. PLUGIN_VERSION .. [[

@WCommands:
  @Yqstab           @w- Show status
  @Yqstab on        @w- Enable plugin
  @Yqstab off       @w- Disable plugin
  @Yqstab status    @w- Show detailed status
  @Yqstab refresh   @w- Refresh quickstab state from slist
  @Yqstab debug     @w- Toggle debug mode
  @Yqstab reload    @w- Reload plugin
  @Yqstab help      @w- Show this help

@WBehavior:
  When quickstab is active and you backstab:
  - If mob survives (hit or miss): spiral fires after short delay
  - If mob dies: spiral is canceled (save for next mob)
  - If "second backstab refused": spiral fires immediately
  - If other failures: spiral fires only if in combat]])
end

function cmd_status()
    local plugin_status = plugin_enabled and "@GEnabled" or "@RDisabled"
    local qs_status = quickstab_active and "@GActive" or "@RInactive"
    local debug_status = debug_enabled and "@GYes" or "@RNo"

    Message(string.format([[@WQuickStab Plugin v%s

  @WPlugin:     @w(%s@w)
  @WQuickstab:  @w(%s@w)
  @WState:      @w(@Y%s@w)
  @WDebug:      @w(%s@w)]],
        PLUGIN_VERSION,
        plugin_status,
        qs_status,
        current_state,
        debug_status))
end

function cmd_enable()
    plugin_enabled = true
    save_state()
    update_trigger_groups()
    info("Plugin ENABLED")
end

function cmd_disable()
    plugin_enabled = false
    save_state()
    update_trigger_groups()

    -- Cancel any pending spiral
    if current_state == QS_STATE.PENDING_SPIRAL then
        cancel_spiral("plugin disabled")
    end

    info("Plugin DISABLED")
end

function cmd_debug()
    debug_enabled = not debug_enabled
    save_state()
    info("Debug mode: " .. (debug_enabled and "ON" or "OFF"))
end

function cmd_refresh()
    if not IsConnected() then
        info("Not connected - cannot refresh")
        return
    end

    -- Check if we're in a valid game state
    local char_state = gmcp("char.status.state")
    if char_state == nil then
        info("GMCP not ready - cannot refresh")
        return
    end

    local state_num = tonumber(char_state)
    if not VALID_GAME_STATES[state_num] then
        info("Not in valid game state - cannot refresh")
        return
    end

    info("Refreshing quickstab state...")
    refresh_quickstab_state()
end

function cmd_reload()
    info("Reloading plugin...")
    reload_plugin()
end
