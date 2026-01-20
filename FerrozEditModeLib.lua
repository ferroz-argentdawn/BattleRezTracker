FerrozEditModeLib = {}

function FerrozEditModeLib:GetCurrentLayoutName()
    if not C_EditMode or type(C_EditMode.GetLayouts) ~= "function" then 
        return "Default" 
    end

    local layoutData = C_EditMode.GetLayouts()
    if not layoutData or not layoutData.layouts then 
        return "Default" 
    end

    local activeIdx = layoutData.activeLayout
    -- presets, hard coded as 1 and 2
    if activeIdx == 1 then
        return HUD_EDIT_MODE_PRESET_MODERN or "Modern"
    elseif activeIdx ==  2 then
        return HUD_EDIT_MODE_PRESET_CLASSIC or "Classic"
    end
    --user layouts, these are offset by 2, the number of presets.  Unfortunately we can't get that dynamically
    if activeIdx then
        local directMatch = layoutData.layouts[activeIdx-2]
        if directMatch and directMatch.layoutName then
            return directMatch.layoutName
        end
    end
    return "Default"
end 

function FerrozEditModeLib:ApplyLayout(frame, settingsTable)
    local layoutName = self:GetCurrentLayoutName()
    local s = settingsTable.layouts and settingsTable.layouts[layoutName]
    
    if s then
        frame:ClearAllPoints()
        frame:SetPoint(s.point, UIParent, s.relativePoint, s.xOfs, s.yOfs)
        frame:SetScale(s.scale or 1.0)
    elseif settingsTable.scale then
        -- Legacy fallback
        frame:SetScale(settingsTable.scale)
    end
end

function FerrozEditModeLib:ResetPosition(frame, settingsTable)
    local layoutName = self:GetCurrentLayoutName()
    if settingsTable.layouts then
        settingsTable.layouts[layoutName] = nil
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetScale(1.0)
end

-- The Registration Core
function FerrozEditModeLib:Register(frame, settingsTable, onEnter, onExit)
    frame.isEditing = false
    settingsTable.layouts = settingsTable.layouts or {}

    self:ApplyLayout(frame, settingsTable)

    -- Internal function to save current state to the active layout
    local function SaveCurrentPosition()
        local layoutName = FerrozEditModeLib:GetCurrentLayoutName()
        local point, _, rel, x, y = frame:GetPoint()
        
        settingsTable.layouts[layoutName] = {
            point = point,
            relativePoint = rel,
            xOfs = x,
            yOfs = y,
            scale = frame:GetScale()
        }
    end

    -- 1. Scaling Logic
    frame:SetScript("OnMouseWheel", function(self, delta)
        if self.isEditing then
            local centerX, centerY = self:GetCenter()
            local oldScale = self:GetScale()
            local newScale = math.max(0.4, math.min(2.5, oldScale + (delta * 0.05)))
            self:SetScale(newScale)
            if centerX and centerY then
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (centerX * oldScale) / newScale, (centerY * oldScale) / newScale)
            end

            SaveCurrentPosition()
        end
    end)

    -- 2. Drag Logic
    frame:SetScript("OnDragStart", function(self) 
        if self.isEditing then self:StartMoving() end 
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveCurrentPosition()
    end)

    -- 3. Blizzard Handshake (EventRegistry)
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        if InCombatLockdown() then return end
        frame.isEditing = true
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        if onEnter then onEnter(frame) end
    end)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        frame.isEditing = false
        frame:EnableMouse(false)
        frame:SetMovable(false)
        if onExit then onExit(frame) end
    end)

    -- 4. Layout Swapping Logic
    -- This ensures that when the user swaps profiles, the frame moves immediately
    frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    frame:HookScript("OnEvent", function(self, event)
        if event == "EDIT_MODE_LAYOUTS_UPDATED" then
            local layoutName = FerrozEditModeLib:GetCurrentLayoutName()
            local s = settingsTable.layouts[layoutName]
            if s then
                self:ClearAllPoints()
                self:SetPoint(s.point, UIParent, s.relativePoint, s.xOfs, s.yOfs)
                self:SetScale(s.scale or 1.0)
            end
        end
    end)
end