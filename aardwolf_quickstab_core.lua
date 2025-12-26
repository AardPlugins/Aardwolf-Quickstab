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

    -- Update window display
    draw_window()
end

-- =============================================================================
-- Spiral Execution
-- =============================================================================
function execute_spiral()
    -- Cooldown check to prevent double-spiral
    local now = os.clock() * 1000
    if (now - last_spiral_time) < SPIRAL_COOLDOWN_MS then
        debug_log("Spiral on cooldown (" .. math.floor(SPIRAL_COOLDOWN_MS - (now - last_spiral_time)) .. "ms remaining), skipping")
        set_state(QS_STATE.IDLE)
        return
    end

    last_spiral_time = now
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
    draw_window()
end

-- Quickstab buff deactivated
function on_quickstab_deactivated()
    quickstab_active = false
    info("Quickstab has WORN OFF")
    update_trigger_groups()
    draw_window()

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

-- Second backstab refused - works even without quickstab active
-- Only spirals if currently in combat
function on_backstab_refused_always()
    if not plugin_enabled then
        debug_log("Plugin disabled, ignoring refused backstab")
        return
    end

    -- Cancel any pending spiral timer first
    DeleteTimer(spiral_timer_id)

    -- Only spiral if we're in combat
    if is_fighting() then
        debug_log("Second backstab refused while fighting, spiraling")
        set_state(QS_STATE.IDLE)
        execute_spiral()
    else
        debug_log("Second backstab refused but not fighting, no spiral")
    end
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
    SetVariable(VAR_SHOW_WINDOW, tostring(show_window))
    SetVariable(VAR_SPIRAL_DELAY, tostring(SPIRAL_DELAY_MS))
end

-- =============================================================================
-- Status Window
-- =============================================================================
qs_window = nil

function create_window()
    if show_window == 0 then
        return
    end

    qs_window = ThemedTextWindow(
        GetPluginID(),                                    -- id
        (GetInfo(281) - WINDOW_WIDTH) / 2,               -- center horizontally
        50,                                               -- near top of screen
        WINDOW_WIDTH,                                     -- width
        WINDOW_HEIGHT,                                    -- height
        "QuickStab",                                      -- title
        "center",                                         -- title alignment
        false,                                            -- not closeable (no X button)
        true,                                             -- resizable
        false,                                            -- not scrollable
        false,                                            -- not selectable
        false,                                            -- not copyable
        false,                                            -- no URL hyperlinks
        true,                                             -- autowrap
        nil,                                              -- default title font
        6,                                                -- title font size
        GetAlphaOption("output_font_name"),              -- text font
        GetOption("output_font_height"),                 -- text font size
        3,                                                -- max lines
        nil,                                              -- default padding
        false,                                            -- show immediately
        false                                             -- not transparent
    )
    qs_window:bring_to_front()
    draw_window()
end

function draw_window()
    if show_window == 0 or qs_window == nil then
        return
    end

    qs_window:clear(false)

    local qs_color = quickstab_active and "@G" or "@R"
    local text = string.format("%sQS: %s", qs_color, quickstab_active and "Active" or "Inactive")

    qs_window:add_text(text, false)
    qs_window:show()
end

function toggle_window()
    if show_window == 1 then
        show_window = 0
        if qs_window then
            qs_window:delete()
            qs_window = nil
        end
        info("Status window DISABLED")
    else
        show_window = 1
        create_window()
        info("Status window ENABLED")
    end
    SetVariable(VAR_SHOW_WINDOW, tostring(show_window))
end

function reset_window()
    if show_window == 0 or qs_window == nil then
        info("Window is not enabled")
        return
    end
    qs_window:reset()
    qs_window:bring_to_front()
    info("Window position reset")
end
