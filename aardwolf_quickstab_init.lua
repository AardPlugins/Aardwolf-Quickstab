-- aardwolf_quickstab_init.lua
-- Bootstrap file - loaded first by XML
-- Defines shared utilities and loads modules in order

-- =============================================================================
-- Dependencies
-- =============================================================================
dofile(GetInfo(60) .. "aardwolf_colors.lua")
require "wait"

-- =============================================================================
-- Constants
-- =============================================================================
PLUGIN_VERSION = "1.0"

-- Skill configuration
QUICKSTAB_SKILL_ID = 601

-- Timing configuration (milliseconds)
-- Short delay to allow death detection before spiral fires
SPIRAL_DELAY_MS = 150

-- Character state constants (from GMCP char.status.state)
CHAR_STATE_STANDING = 3
CHAR_STATE_FIGHTING = 8
CHAR_STATE_SLEEPING = 9
CHAR_STATE_RESTING = 11

-- Valid states for sending commands (not logging in, etc.)
VALID_GAME_STATES = {
    [CHAR_STATE_STANDING] = true,
    [CHAR_STATE_FIGHTING] = true,
    [CHAR_STATE_SLEEPING] = true,
    [CHAR_STATE_RESTING] = true,
}

-- Plugin IDs for inter-plugin communication
plugin_id_gmcp_handler = "3e7dedbe37e44942dd46d264"

-- =============================================================================
-- Shared State (global for cross-file access)
-- =============================================================================
debug_enabled = false
plugin_enabled = true
quickstab_active = false

-- =============================================================================
-- GMCP Helper (used by all modules)
-- =============================================================================
function gmcp(s)
    local ret, datastring = CallPlugin(plugin_id_gmcp_handler, "gmcpdata_as_string", s)
    if ret ~= 0 or datastring == nil then
        return nil
    end
    local data = nil
    pcall(function() data = loadstring("return " .. datastring)() end)
    return data
end

-- =============================================================================
-- Logging Utilities (used by all modules)
-- =============================================================================
function Message(str)
    AnsiNote(stylesToANSI(ColoursToStyles(string.format(
        "\n@C[@GQuickStab@C]@w %s\n", str))))
end

function info(msg)
    ColourNote("lime", "", "[QuickStab] " .. msg)
end

function debug_log(msg)
    if debug_enabled then
        ColourNote("orange", "", "[QS Debug] " .. msg)
    end
end

function warn(msg)
    ColourNote("yellow", "", "[QS Warning] " .. msg)
end

-- =============================================================================
-- Helper Utilities
-- =============================================================================
function reload_plugin()
    if GetAlphaOption("script_prefix") == "" then
        SetAlphaOption("script_prefix", "\\\\\\")
    end

    Execute(
        GetAlphaOption("script_prefix") ..
        'DoAfterSpecial(0.5, "ReloadPlugin(\'' .. GetPluginID() .. '\')", sendto.script)'
    )
end

-- Check if character is currently fighting
function is_fighting()
    local char_status = gmcp("char.status")
    if char_status and char_status.state then
        return tonumber(char_status.state) == CHAR_STATE_FIGHTING
    end
    return false
end

-- =============================================================================
-- Telnet Options (called only when connected)
-- =============================================================================
-- Flag to track if we've loaded telnet_options.lua
local telnet_options_loaded = false

-- Enable spellup telnet option to receive {affon}/{affoff} tags
-- This should ONLY be called when IsConnected() is true
function enable_spellup_telnet()
    -- Load telnet_options.lua if not already loaded
    if not telnet_options_loaded then
        dofile(GetInfo(60) .. "telnet_options.lua")
        telnet_options_loaded = true
    end

    -- Enable spellup tags (silently, this is the recommended way)
    -- TELOPT_SPELLUP is defined in telnet_options.lua
    TelnetOptionOn(TELOPT_SPELLUP)
    debug_log("TELOPT_SPELLUP enabled")
end

-- =============================================================================
-- Load Modules in Order
-- =============================================================================
local plugin_dir = GetPluginInfo(GetPluginID(), 20)

dofile(plugin_dir .. "aardwolf_quickstab_core.lua")
dofile(plugin_dir .. "aardwolf_quickstab_handlers.lua")

-- Initialization message
info("QuickStab Plugin v" .. PLUGIN_VERSION .. " loaded")
