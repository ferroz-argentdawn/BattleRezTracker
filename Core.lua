local addonName, ns = ...
---Libraries
local lib = LibStub("FerrozEditModeLib-1.0")
-- Constants
local FRAME_SIZE = 42                    -- Standard action button size
local REBIRTH_SPELL_ID = 20484           -- SpellID for Rebirth spell icon
local TEXCOORD_LEFT = 0.08               -- Texture coordinate crop (WeakAura style)
local TEXCOORD_RIGHT = 0.92
local COUNT_FONT_SIZE = 12               -- Font size for charge count
local TIMER_FONT_SIZE = 16               -- Font size for timer text
local PREVIEW_TIMER = 599                -- Realistic preview timer (10-minute cooldown)
local PREVIEW_CHARGES = 3              -- Preview charge count for Edit Mode
local FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")
local log = lib.Log

-- Test mode variables
local testMode = false
local testCount = PREVIEW_CHARGES
local testExpirationTime = PREVIEW_TIMER  -- 0 = no timer, > 0 = recharging

-- Cache globals for peak performance
local GetTime = GetTime
local math_floor = math.floor
local math_max = math.max
local C_Timer = C_Timer

---------------------------------------------------------
-- MIXINS 
---------------------------------------------------------
BattleRezTracker_Mixin = {}

-- boolean whether tracker should be visible
function BattleRezTracker_Mixin:ShouldShowTracker()
    -- Always show in Edit Mode or Test Mode
    if testMode or (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
        return true
    end

    -- Check if we are in a Raid or Mythic+
    local _, instanceType = GetInstanceInfo()
    local isMythicPlus = C_ChallengeMode.GetActiveKeystoneInfo() > 0

    -- Return true if in Raid, Mythic+, or a Delve
    return (instanceType == "raid") or isMythicPlus or (instanceType == "scenario")
end
--updates display when something changes
function BattleRezTracker_Mixin:UpdateDisplay()
    -- Preview behavior for Edit Mode
    if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then
        return
    end

    if not self:ShouldShowTracker() then
        self:SetAlpha(0)
        return
    end

    -- Test mode: use simulated data
    local chargesTable, currentCharges, startTime, duration
    if testMode then
        currentCharges = testCount
        duration = testExpirationTime
        startTime = GetTime()
    else 
        chargesTable = C_Spell.GetSpellCharges(20484)
        if chargesTable then
            currentCharges = chargesTable.currentCharges
            startTime = chargesTable.cooldownStartTime
            duration = chargesTable.cooldownDuration
        end
    end
    
    if  currentCharges then
        self.countText:SetFormattedText("%d", currentCharges)
        if issecretvalue and issecretvalue(currentCharges) then
            self.icon:SetDesaturated(false )
        else
            self.icon:SetDesaturated(currentCharges == 0 )
        end
    else
        self.countText:SetFormattedText("%d", 0)
        self.icon:SetDesaturated(true)
    end

    -- Update the Cooldown Swipe/Timer
    if startTime and duration then
        --self.cd:SetCooldownFromExpirationTime(startTime, duration)
        self.cd:SetCooldown(startTime, duration)
        self.cd:SetHideCountdownNumbers(false)
        self.cd:SetCountdownAbbrevThreshold(3600)
    else
        self.cd:Clear() -- Stops the visual timer
    end

    self:SetAlpha(1)
end

function BattleRezTracker_Mixin:EditModeStartMock()
    self.countText:SetText(PREVIEW_CHARGES)
    self.cd:SetCooldown(GetTime(), PREVIEW_TIMER)
    self.icon:SetDesaturated(false)
    self:SetAlpha(1)
end

function BattleRezTracker_Mixin:EditModeStopMock()
    self.cd:Clear()
    self:UpdateDisplay() -- Returns to real combat data
end

local function InitializeBattleRezTracker()
    -- 1. Create the Main Square Frame
    local f = CreateFrame("Frame", "BattleRezTracker", UIParent, "SecureHandlerStateTemplate")
    Mixin(f, BattleRezTracker_Mixin)
    f:SetSize(FRAME_SIZE, FRAME_SIZE)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)

    --The Icon (Rebirth)
    f.icon = f:CreateTexture(nil, "BACKGROUND")
    f.icon:SetAllPoints(f)

    -- Get the icon texture dynamically from the spell data
    local spellInfo = C_Spell.GetSpellInfo(REBIRTH_SPELL_ID)
    if spellInfo then
        f.icon:SetTexture(spellInfo.iconID)
    else
        -- Fallback if the spell data isn't ready yet
        f.icon:SetTexture(136048)
    end

    f.icon:SetTexCoord(TEXCOORD_LEFT, TEXCOORD_RIGHT, TEXCOORD_LEFT, TEXCOORD_RIGHT)

    --The Timer Text (Centered)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetFrameLevel(f:GetFrameLevel() + 1)
    f.cd:SetDrawSwipe(false)
    f.cd:SetCountdownAbbrevThreshold(3600)
    f.cd:SetPoint("TOPLEFT", f, "TOPLEFT",0,0)
    f.cd:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",0,6) 
    f.cd:SetHideCountdownNumbers(false)

    --The Charge Count (Bottom Right)
    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    f.countText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.countText:SetFont(f.countText:GetFont(), COUNT_FONT_SIZE, "OUTLINE")

    if lib then
        lib:Register(f, BRT_Settings)
    end

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"
    print(FERROZ_COLOR:WrapTextInColorCode("[BattleRezTracker] v" .. version) .. " loaded (/brt)")

    --Event Handling
    f:RegisterEvent("PLAYER_ENTERING_WORLD") 
    f:RegisterEvent("SPELL_UPDATE_CHARGES")  -- Fires when a charge is used or gained
    f:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering Combat
    f:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving Combat
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- Triggered when loading into a dungeon/raid
    f:RegisterEvent("CHALLENGE_MODE_START")  -- Specifically for Mythic+ starts

    f:SetScript("OnEvent", function(self, event)
        self:UpdateDisplay()
    end)
end

-- Slash commands for testing
SLASH_BATTLEREZTRACKER1 = "/brt"
SLASH_BATTLEREZTRACKER2 = "/battlereztracker"
SlashCmdList["BATTLEREZTRACKER"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    
    if cmd == "reset" then
        lib:ResetPosition(BattleRezTracker)
        BattleRezTracker:UpdateDisplay()
        print(FERROZ_COLOR:WrapTextInColorCode("[BRT]:").." Position and Scale have been reset.")
    elseif cmd == "test" then
        testMode = not testMode
        local status = testMode and "ENABLED" or "DISABLED"
        print(string.format(FERROZ_COLOR:WrapTextInColorCode("[BRT]:").." Test mode %s", status))
        if testMode then
            print(FERROZ_COLOR:WrapTextInColorCode("[BRT]:").." Use /brt count # to set test charges")
            print(FERROZ_COLOR:WrapTextInColorCode("[BRT]:").." Use /brt timer # to set test timer (seconds, 0 to clear)")
        end
        BattleRezTracker:UpdateDisplay()
    elseif cmd == "refresh" then
        print("force refresh")
        BattleRezTracker:UpdateDisplay()
    elseif cmd == "count" and tonumber(arg) then
        testCount = math_max(0, tonumber(arg))
        print(string.format(FERROZ_COLOR:WrapTextInColorCode("[BRT]:").." Test charges set to %d", testCount))
        if testMode then
            BattleRezTracker:UpdateDisplay()
        end
    elseif cmd == "timer" and tonumber(arg) then
        local seconds = tonumber(arg)
        testExpirationTime = math_max(0, seconds)
        if testExpirationTime > 0 then
            print(string.format(FERROZ_COLOR:WrapTextInColorCode("[BRT]:").." Test timer set to %d seconds", testExpirationTime))
        else
            print(FERROZ_COLOR:WrapTextInColorCode("[BRT]:").." Test timer cleared")
        end
        if testMode then
            BattleRezTracker:UpdateDisplay()
        end
    else
        print(FERROZ_COLOR:WrapTextInColorCode("Battle Rez Tracker Commands:"))
        print("  /brt reset - Reset position to center and scale to 1.0")
        print("  /brt test - Toggle test mode (simulates battle rez data)")
        print("  /brt count # - Set test charge count (e.g., /brt count 2)")
        print("  /brt timer # - Set test timer in seconds (e.g., /brt timer 300 for 5 min, 0 to clear)")
        BattleRezTracker:UpdateDisplay()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        InitializeBattleRezTracker()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
