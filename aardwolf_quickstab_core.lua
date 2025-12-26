-- aardwolf_quickstab_core.lua
-- State machine and core logic for auto-spiral after backstab

-- =============================================================================
-- State Constants
-- =============================================================================
QS_STATE = {
    IDLE = "idle",                    -- Waiting for backstab
    PENDING_SPIRAL = "pending_spiral", -- Backstab fired, waiting for result
}

-- =============================================================================
-- Variable Keys for Persistence
-- =============================================================================
VAR_ENABLED = "qs_enabled"
VAR_DEBUG = "qs_debug"

-- =============================================================================
-- State Variables (global for cross-file access)
-- =============================================================================
current_state = QS_STATE.IDLE
spiral_timer_id = "qs_spiral_timer"

-- =============================================================================
-- State Management
-- =============================================================================
function set_state(new_state)
    local old_state = current_state
    current_state = new_state
    debug_log("State: " .. old_state .. " -> " .. new_state)

    -- Enable/disable death triggers based on state
    if new_state == QS_STATE.PENDING_SPIRAL then
        EnableTriggerGroup("quickstab_death", true)
    else
        EnableTriggerGroup("quickstab_death", false)
    end
end

-- =============================================================================
-- Spiral Execution
-- =============================================================================
function execute_spiral()
    debug_log("Executing spiral")
    Send("spiral")
    set_state(QS_STATE.IDLE)
end

function cancel_spiral(reason)
    debug_log("Canceling spiral: " .. reason)

    -- Kill the timer if it exists
    DeleteTimer(spiral_timer_id)

    set_state(QS_STATE.IDLE)
end

function schedule_spiral()
    debug_log("Scheduling spiral in " .. SPIRAL_DELAY_MS .. "ms")
    set_state(QS_STATE.PENDING_SPIRAL)

    -- Create a one-shot timer
    -- Timer values are hour, min, sec - we need fractional seconds
    local delay_seconds = SPIRAL_DELAY_MS / 1000

    -- Use AddTimer with the timer_flag constants
    local result = AddTimer(
        spiral_timer_id,                                    -- name
        0, 0, delay_seconds,                                -- hour, min, sec
        "",                                                 -- response text (empty, we use script)
        timer_flag.Enabled + timer_flag.OneShot + timer_flag.Replace,  -- flags
        "timer_spiral_fire"                                 -- script function
    )

    if result ~= error_code.eOK then
        warn("Failed to create spiral timer: " .. result)
        -- Fall back to immediate spiral
        execute_spiral()
    else
        debug_log("Spiral timer created successfully, waiting for death or timeout")
    end
end

-- =============================================================================
-- Trigger Group Management
-- =============================================================================
function update_trigger_groups()
    local enable = quickstab_active and plugin_enabled
    EnableTriggerGroup("quickstab_backstab", enable)
    EnableTriggerGroup("quickstab_failures", enable)
    debug_log("Backstab triggers: " .. (enable and "enabled" or "disabled"))
end

-- =============================================================================
-- Event Handlers
-- =============================================================================

-- Quickstab buff activated
function on_quickstab_activated(duration)
    quickstab_active = true
    info("Quickstab is now ACTIVE (" .. duration .. "s)")
    update_trigger_groups()
end

-- Quickstab buff deactivated
function on_quickstab_deactivated()
    quickstab_active = false
    info("Quickstab has WORN OFF")
    update_trigger_groups()

    -- Cancel any pending spiral
    if current_state == QS_STATE.PENDING_SPIRAL then
        cancel_spiral("quickstab wore off")
    end
end

-- Backstab executed (hit or miss) - schedule spiral after delay
function on_backstab_executed()
    if current_state ~= QS_STATE.IDLE then
        debug_log("Ignoring backstab, not in IDLE state")
        return
    end

    if not quickstab_active then
        debug_log("Ignoring backstab, quickstab not active")
        return
    end

    if not plugin_enabled then
        debug_log("Ignoring backstab, plugin disabled")
        return
    end

    debug_log("Backstab executed, scheduling spiral")
    schedule_spiral()
end

-- Second backstab refused - spiral immediately (can't bs again)
function on_backstab_refused()
    if not quickstab_active or not plugin_enabled then
        debug_log("Ignoring refused backstab, plugin/quickstab not active")
        return
    end

    debug_log("Second backstab refused, spiraling immediately")

    -- Cancel any existing timer and spiral now
    DeleteTimer(spiral_timer_id)
    set_state(QS_STATE.IDLE)
    execute_spiral()
end

-- Backstab failed (target not here, too paranoid, etc.)
-- Only spiral if we're in combat
function on_backstab_failed()
    if not quickstab_active or not plugin_enabled then
        debug_log("Ignoring backstab failure, plugin/quickstab not active")
        return
    end

    local fighting = is_fighting()
    local char_state = gmcp("char.status.state")
    debug_log("Backstab failed - char.status.state=" .. tostring(char_state) .. ", is_fighting=" .. tostring(fighting))

    if fighting then
        debug_log("Backstab failed while fighting, spiraling")
        execute_spiral()
    else
        debug_log("Backstab failed, not fighting - no spiral")
    end
end

-- Mob died - cancel pending spiral
function on_mob_died()
    debug_log("Death detected, current state: " .. current_state)
    if current_state == QS_STATE.PENDING_SPIRAL then
        cancel_spiral("mob died from backstab")
    else
        debug_log("Ignoring death, not in PENDING_SPIRAL state")
    end
end

-- =============================================================================
-- Slist State Refresh
-- =============================================================================

-- Query current quickstab state from slist affected
-- Called on connect/install to detect if quickstab is already active
function refresh_quickstab_state()
    debug_log("Refreshing quickstab state via slist...")
    EnableTriggerGroup("quickstab_slist", true)
    SendNoEcho("slist affected")
end

-- Called when {spellheaders} is received
function on_slist_start()
    debug_log("slist capture started")
    -- We'll check each line for quickstab
end

-- Called for each skill line in slist output
-- Format: <sn>,<name>,<target>,<duration>,<pct>,<recovery>,<type>
function on_slist_line(sn, name, target, duration, pct, recovery, skilltype)
    -- Check if this is quickstab (skill 601)
    if sn == QUICKSTAB_SKILL_ID then
        if duration > 0 then
            -- Quickstab is active with time remaining
            debug_log("slist: Quickstab is ACTIVE (" .. duration .. "s remaining)")
            quickstab_active = true
            update_trigger_groups()
        else
            -- Quickstab is known but not active
            debug_log("slist: Quickstab is INACTIVE")
            quickstab_active = false
            update_trigger_groups()
        end
    end
end

-- Called when {/spellheaders} is received
function on_slist_end()
    debug_log("slist capture complete")
    EnableTriggerGroup("quickstab_slist", false)

    -- Report current state
    if quickstab_active then
        info("Quickstab is ACTIVE")
    else
        debug_log("Quickstab not found in slist affected (not active)")
    end
end

-- =============================================================================
-- State Persistence
-- =============================================================================
function load_state()
    plugin_enabled = GetVariable(VAR_ENABLED) ~= "false"
    debug_enabled = GetVariable(VAR_DEBUG) == "true"

    debug_log("Loaded state - enabled: " .. tostring(plugin_enabled) .. ", debug: " .. tostring(debug_enabled))

    -- Initialize trigger groups based on current state
    -- quickstab_active starts false, so backstab triggers will be disabled
    update_trigger_groups()
end

function save_state()
    SetVariable(VAR_ENABLED, tostring(plugin_enabled))
    SetVariable(VAR_DEBUG, tostring(debug_enabled))
end
