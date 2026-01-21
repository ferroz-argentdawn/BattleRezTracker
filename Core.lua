-- Constants
BRT_Settings = BRT_Settings or { scale = 1.0 }
local FRAME_SIZE = 42                    -- Standard action button size
local REBIRTH_SPELL_ID = 20484           -- SpellID for Rebirth spell icon
local TEXCOORD_LEFT = 0.08               -- Texture coordinate crop (WeakAura style)
local TEXCOORD_RIGHT = 0.92
local COUNT_FONT_SIZE = 12               -- Font size for charge count
local TIMER_FONT_SIZE = 16               -- Font size for timer text
local PREVIEW_TIMER = 599                -- Realistic preview timer (10-minute cooldown)
local PREVIEW_CHARGES = 3              -- Preview charge count for Edit Mode
local BREZ_SPELL_IDS = {
    [20484] = true,  -- Rebirth (Druid)
    [61999] = true,  -- Raise Ally (DK)
    [20707] = true,  -- Soulstone (Warlock)
    [199115] = true, -- Failure Detection Pylon (Engineer)
    [391139] = true, -- Intercession (Paladin)
}


-- Test mode variables
local testMode = false
local testCount = PREVIEW_CHARGES
local testExpirationTime = PREVIEW_TIMER  -- 0 = no timer, > 0 = recharging

-- Cache globals for peak performance
local GetBattleResurrectionDetails = GetBattleResurrectionDetails
local GetTime = GetTime
local math_floor = math.floor
local math_max = math.max
local C_Timer = C_Timer

-- 1. Create the Main Square Frame
local f = CreateFrame("Frame", "BattleRezTrackerFrame", UIParent)
f:SetSize(FRAME_SIZE, FRAME_SIZE)
f:SetPoint("CENTER", UIParent, "CENTER")
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)

-- Blue Box Style: Manual Selection Highlight
f.Selection = f:CreateTexture(nil, "OVERLAY")
f.Selection:SetAllPoints(true)
f.Selection:SetColorTexture(1, 1, 0, 0.3) -- Yellow highlight
f.Selection:Hide()

-- Blue Box Style: Required Mixin Methods
Mixin(f, EditModeSystemMixin)
function f:GetSystemName() return "Battle Rez Tracker" end
function f:SetSelected(selected)
    if selected then self.Selection:Show() else self.Selection:Hide() end
end

-- 2. The Icon (Rebirth)
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

-- 3. The Timer Text (Centered)
f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
f.cd:SetDrawSwipe(false)
f.cd:SetCountdownAbbrevThreshold(3600)
f.cd:SetPoint("TOPLEFT", f, "TOPLEFT",0,0)
f.cd:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",0,6) 
f.cd:SetHideCountdownNumbers(false)
local cdText = f.cd:GetRegions() -- Usually the first region is the text
if cdText and cdText.SetFont then
    cdText:SetFont("Fonts\\FRIZQT__.TTF", TIMER_FONT_SIZE, "OUTLINE")
    cdText:SetTextColor(1, 1, 1)
end

-- 4. The Charge Count (Bottom Right)
f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
f.countText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
f.countText:SetFont(f.countText:GetFont(), COUNT_FONT_SIZE, "OUTLINE")


-- boolean whether tracker should be visible
local function ShouldShowTracker()
    -- Always show in Edit Mode or Test Mode
    if testMode or (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
        return true
    end

    --if InCombatLockdown() then return true end -- Force show if fighting

    -- Check if we are in a Raid or Mythic+
    local _, instanceType = GetInstanceInfo()
    local isMythicPlus = C_ChallengeMode.GetActiveKeystoneInfo() > 0

    -- Return true if in Raid, Mythic+, or a Delve
    return (instanceType == "raid") or isMythicPlus or (instanceType == "scenario")
end
--updates display when something changes
local function UpdateDisplay()
    -- Preview behavior for Edit Mode
    if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then
        return
    end

    if not ShouldShowTracker() then
        f:Hide()
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
        if f.countText.SetFormattedText then
            f.countText:SetFormattedText("%d", currentCharges)
        else
            f.countText:SetText(currentCharges or "0")
        end
    end

    -- Update the Cooldown Swipe/Timer
    if startTime and duration then
        if f.cd.SetCooldownFromExpirationTime then
            f.cd:SetCooldownFromExpirationTime(startTime, duration)
        else
            -- 11.2.7: Live math
            f.cd:SetCooldown(startTime, duration)
        end
    else
        f.cd:Clear() -- Stops the visual timer
    end

    f:Show()
end

local function BRT_OnEnter(frame)
    frame.countText:SetText(PREVIEW_CHARGES)
    frame.cd:SetCooldown(GetTime(), PREVIEW_TIMER)
    frame.icon:SetDesaturated(false)
    frame:Show()
end

local function BRT_OnExit(frame)
    frame.cd:Clear()
    UpdateDisplay() -- Returns to real combat data
end

-- Slash commands for testing
SLASH_BATTLEREZTRACKER1 = "/brt"
SLASH_BATTLEREZTRACKER2 = "/battlereztracker"
SlashCmdList["BATTLEREZTRACKER"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    
    if cmd == "reset" then
        FerrozEditModeLib:ResetPosition(f,BRT_Settings)
        UpdateDisplay()
        print("|cFF00FF00[BRT]:|r Position and Scale have been reset.")
    elseif cmd == "test" then
        testMode = not testMode
        local status = testMode and "ENABLED" or "DISABLED"
        print(string.format("|cFF00FF00[BRT]:|r Test mode %s", status))
        if testMode then
            print("|cFF00FF00[BRT]:|r Use /brt count # to set test charges")
            print("|cFF00FF00[BRT]:|r Use /brt timer # to set test timer (seconds, 0 to clear)")
        end
        UpdateDisplay()
    elseif cmd == "refresh" then
        print("force refresh")
        UpdateDisplay()
    elseif cmd == "count" and tonumber(arg) then
        testCount = math_max(0, tonumber(arg))
        print(string.format("|cFF00FF00[BRT]:|r Test charges set to %d", testCount))
        if testMode then
            UpdateDisplay()
        end
    elseif cmd == "timer" and tonumber(arg) then
        local seconds = tonumber(arg)
        testExpirationTime = math_max(0, seconds)
        if testExpirationTime > 0 then
            print(string.format("|cFF00FF00[BRT]:|r Test timer set to %d seconds", testExpirationTime))
        else
            print("|cFF00FF00[BRT]:|r Test timer cleared")
        end
        if testMode then
            UpdateDisplay()
        end
    else
        print("|cFF00FF00[BRT] Commands:|r")
        print("  /brt reset - Reset position to center and scale to 1.0")
        print("  /brt test - Toggle test mode (simulates battle rez data)")
        print("  /brt count # - Set test charge count (e.g., /brt count 2)")
        print("  /brt timer # - Set test timer in seconds (e.g., /brt timer 300 for 5 min, 0 to clear)")
        UpdateDisplay()
    end
end

--Event Handling
f:RegisterEvent("PLAYER_ENTERING_WORLD") 
f:RegisterEvent("SPELL_UPDATE_CHARGES")  -- Fires when a charge is used or gained
f:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering Combat
f:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving Combat
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- Triggered when loading into a dungeon/raid
f:RegisterEvent("CHALLENGE_MODE_START")  -- Specifically for Mythic+ starts
f:RegisterEvent("ADDON_LOADED") 

f:SetScript("OnEvent", function(self, event, ...)
    local arg1, arg2, arg3 = ... -- Capture arguments generically
    if event == "ADDON_LOADED" then
        if arg1 == "BattleRezTracker" then
            -- Load Settings
            FerrozEditModeLib:Register(BattleRezTrackerFrame, BRT_Settings, BRT_OnEnter, BRT_OnExit, nil)
            UpdateDisplay()
            print("|cFF00FF00[BRT]:|r  Addon Loaded and Registered")
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitTarget = arg1
        local spellID = arg3
        -- Only update if the spell cast was actually a Battle Rez
        if BREZ_SPELL_IDS[spellID] then
            local name = UnitName(unitTarget) or "Someone"
            print("|cFF00FF00[BRT]:|r " .. name .. " casted Battle Rez (ID: " .. spellID .. ")")
            --no need to update display, it will update when the charge changes.
        end
    else -- This covers all other events we track
        UpdateDisplay()
    end
end)
