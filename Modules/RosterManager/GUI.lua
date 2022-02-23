local _, CLM = ...

-- Libs
local ScrollingTable = LibStub("ScrollingTable")
local AceGUI = LibStub("AceGUI-3.0")

local LIBS =  {
    registry = LibStub("AceConfigRegistry-3.0"),
    gui = LibStub("AceConfigDialog-3.0")
}

local LOG = CLM.LOG
local UTILS = CLM.UTILS
local MODULES = CLM.MODULES
local CONSTANTS = CLM.CONSTANTS
local ACL = MODULES.ACL

local GUI = CLM.GUI

local mergeDictsInline = UTILS.mergeDictsInline
local GetColorCodedClassDict = UTILS.GetColorCodedClassDict
local Trim = UTILS.Trim
local round = UTILS.round
local ColorCodeByPercentage = UTILS.ColorCodeByPercentage
local RemoveColorCode = UTILS.RemoveColorCode

local GuildInfoListener = MODULES.GuildInfoListener
local ProfileManager = MODULES.ProfileManager
local RosterManager = MODULES.RosterManager
local PointManager = MODULES.PointManager
local LedgerManager = MODULES.LedgerManager
local EventManager = MODULES.EventManager
local RaidManager = MODULES.RaidManager
local StandbyStagingManager = MODULES.StandbyStagingManager

local FILTER_IN_RAID = 100
-- local FILTER_ONLINE = 101
local FILTER_STANDBY = 102
local FILTER_IN_GUILD = 103
local FILTER_NOT_IN_GUILD = 104
local FILTER_MAINS_ONLY = 105


local StandingsGUI = {}

local function InitializeDB(self)
    self.db = MODULES.Database:GUI('standings', {
        location = {nil, nil, "CENTER", 0, 0 }
    })
end

local function StoreLocation(self)
    self.db.location = { self.top:GetPoint() }
end

local function RestoreLocation(self)
    if self.db.location then
        self.top:ClearAllPoints()
        self.top:SetPoint(self.db.location[3], self.db.location[4], self.db.location[5])
    end
end

function StandingsGUI:Initialize()
    InitializeDB(self)
    EventManager:RegisterWoWEvent({"PLAYER_LOGOUT"}, (function(...) StoreLocation(self) end))
    self.tooltip = CreateFrame("GameTooltip", "CLMStandingsListGUIDialogTooltip", UIParent, "GameTooltipTemplate")
    self:Create()
    self:RegisterSlash()
    self._initialized = true
    self.selectedRoster = 0
    self.numSelected = 0
    self.numInRoster = 0
    LedgerManager:RegisterOnUpdate(function(lag, uncommitted)
        if lag ~= 0 or uncommitted ~= 0 then return end
        self:Refresh(true)
    end)

end

local function ST_GetName(row)
    return row.cols[1].value
end

local function ST_GetClass(row)
    return row.cols[3].value
end

-- local function ST_GetAttendance(row)
--     return row.cols[5].value
-- end

local function ST_GetWeeklyGains(row)
    return row.cols[6].value
end

local function ST_GetWeeklyCap(row)
    return row.cols[7].value
end

local function UpdateStatusText(self)
    local selectCount = self.numSelected
    if not self.numSelected or self.numSelected == 0 then
        selectCount = CLM.L["all"]
    end
    self.top:SetStatusText(self.numInRoster .. CLM.L[" players in roster"] .. " (" .. selectCount .. " " .. CLM.L["selected"] ..  ")")
end

local function GenerateUntrustedOptions(self)
    local filters = UTILS.ShallowCopy(GetColorCodedClassDict())
    filters[FILTER_IN_RAID] = UTILS.ColorCodeText(CLM.L["In Raid"], "FFD100")
    filters[FILTER_MAINS_ONLY] = UTILS.ColorCodeText(CLM.L["Mains"], "FFD100")
    filters[FILTER_NOT_IN_GUILD] = UTILS.ColorCodeText(CLM.L["External"], "FFD100")
    filters[FILTER_IN_GUILD] = UTILS.ColorCodeText(CLM.L["In Guild"], "FFD100")
    filters[FILTER_STANDBY] = UTILS.ColorCodeText(CLM.L["Standby"], "FFD100")
    return {
        filter_header = {
            type = "header",
            name = CLM.L["Filtering"],
            order = 0
        },
        filter_display = {
            name = CLM.L["Filter"],
            type = "multiselect",
            set = function(i, k, v)
                local n = tonumber(k)
                self.filterOptions[n] = v
                if v then
                    if n == FILTER_IN_RAID then
                        self.filterOptions[FILTER_STANDBY] = not v
                    elseif n == FILTER_STANDBY then
                        self.filterOptions[FILTER_IN_RAID] = not v
                    end
                    if n == FILTER_IN_GUILD then
                        self.filterOptions[FILTER_NOT_IN_GUILD] = not v
                    elseif n == FILTER_NOT_IN_GUILD then
                        self.filterOptions[FILTER_IN_GUILD] = not v
                    end
                end
                self:Refresh()
            end,
            get = function(i, v) return self.filterOptions[tonumber(v)] end,
            values = filters,
            width = 0.49,
            disabled = function() return self.searchMethod and true or false end,
            order = 1
        },
        filter_search = {
            name = CLM.L["Search"],
            desc = CLM.L["Search for player names. Separate multiple with a comma ','. Minimum 3 characters. Overrides filtering."],
            type = "input",
            set = (function(i, v)
                self.searchString = v
                if v and strlen(v) >= 3 then
                    local searchList = { strsplit(",", v) }
                    self.searchMethod = (function(playerName)
                        for _, searchString in ipairs(searchList) do
                            searchString = Trim(searchString)
                            if strlen(searchString) >= 3 then
                                searchString = ".*" .. strlower(searchString) .. ".*"
                                if(string.find(strlower(playerName), searchString)) then
                                    return true
                                end
                            end
                        end
                        return false
                    end)
                else
                    self.searchMethod = nil
                end
                self:Refresh()
            end),
            get = (function(i) return self.searchString end),
            width = "full",
            order = 4,
        },
        filter_select_all = {
            name = CLM.L["All"],
            desc = CLM.L["Select all classes."],
            type = "execute",
            func = (function()
                for i=1,9 do
                    self.filterOptions[i] = true
                end
                self:Refresh(true)
            end),
            disabled = function() return self.searchMethod and true or false end,
            width = 0.55,
            order = 2,
        },
        filter_select_none = {
            name = CLM.L["None"],
            desc = CLM.L["Clear all classes."],
            type = "execute",
            func = (function()
                for i=1,9 do
                    self.filterOptions[i] = false
                end
                self:Refresh(true)
            end),
            disabled = function() return self.searchMethod and true or false end,
            width = 0.55,
            order = 3,
        },
    }
end

local function GenerateManagerOptions(self)
    return {
        award_header = {
            type = "header",
            name = CLM.L["Management"],
            order = 10
        },
        award_dkp_value = {
            name = CLM.L["Award DKP value"],
            desc = CLM.L["DKP value that will be awarded."],
            type = "input",
            set = function(i, v) self.awardValue = v end,
            get = function(i) return self.awardValue end,
            width = 0.6,
            pattern = CONSTANTS.REGEXP_FLOAT,
            order = 11
        },
        award_dkp_note = {
            name = CLM.L["Note"],
            desc = (function()
                local n = CLM.L["Note to be added to award. Max 32 characters. It is recommended to not include date nor selected reason here. If you will input encounter ID it will be transformed into boss name."]
                if strlen(self.note) > 0 then
                    n = n .. "\n\n|cffeeee00Note:|r " .. self.note
                end
                return n
            end),
            type = "input",
            set = function(i, v) self.note = v end,
            get = function(i) return self.note end,
            width = 0.5,
            order = 12
        },
        award_reason = {
            name = CLM.L["Reason"],
            type = "select",
            values = CONSTANTS.POINT_CHANGE_REASONS.GENERAL,
            set = function(i, v) self.awardReason = v end,
            get = function(i) return self.awardReason end,
            order = 13
        },
        award_dkp = {
            name = CLM.L["Award"],
            desc = CLM.L["Award DKP to selected players or everyone if none selected."],
            type = "execute",
            width = "full",
            func = (function(i)
                -- Award Value
                local awardValue = tonumber(self.awardValue)
                if not awardValue then LOG:Debug("StandingsGUI(Award): missing award value"); return end
                -- Reason
                local awardReason
                if self.awardReason and CONSTANTS.POINT_CHANGE_REASONS.GENERAL[self.awardReason] then
                    awardReason = self.awardReason
                else
                    LOG:Debug("StandingsGUI(Award): missing reason");
                    awardReason = CONSTANTS.POINT_CHANGE_REASON.MANUAL_ADJUSTMENT
                end
                -- Selected: roster, profiles
                local roster, profiles = self:GetSelected()
                if roster == nil then
                    LOG:Debug("StandingsGUI(Award): roster == nil")
                    return
                end
                if not profiles or #profiles == 0 then
                    LOG:Debug("StandingsGUI(Award): profiles == 0")
                    return
                end
                -- Roster award
                if #profiles == #roster:Profiles() then
                    PointManager:UpdateRosterPoints(roster, awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY, false, self.note)
                elseif RaidManager:IsInActiveRaid() then
                    local raidAward = false
                    local raid = RaidManager:GetRaid()
                    if #profiles == #raid:Players() then
                        raidAward = true
                        for _, profile in ipairs(profiles) do
                            raidAward = raidAward and raid:IsPlayerInRaid(profile:GUID())
                        end
                    end
                    if raidAward then
                        PointManager:UpdateRaidPoints(raid, awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY, self.note)
                    else
                        PointManager:UpdatePoints(roster, profiles, awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY, self.note)
                    end
                else
                    PointManager:UpdatePoints(roster, profiles, awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY, self.note)
                end
                -- Update points
                -- PointManager:UpdatePoints(roster, profiles, awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY)
            end),
            confirm = true,
            order = 14
        },
        export_xml_button = {
            name = CLM.L["Export to XML"],
            desc = CLM.L["Exports standings in XML format."],
            type = "execute",
            width = "full",
            func = (function()
                ExportString = "<dkptable>\n";
                -- Get all on the roster
                local roster = self:GetCurrentRoster()
                if not roster then return end
                for GUID,value in pairs(roster:Standings()) do
                    local profile = ProfileManager:GetProfileByGUID(GUID)
                    if profile and (not profile:Main() or profile:Main() == "") then
                        ExportString = ExportString.."    <dkpentry>\n        <player>"..profile:Name().."</player>\n        <class>"..profile:Class().."</class>\n        <dkp>"..value.."</dkp>\n    </dkpentry>\n"
                    end
                end
                ExportString = ExportString.."</dkptable>"
                GUI.XMLExport:Show(ExportString)
            end),
            confirm = false,
            order = 101
        }
    }
end

local function GenerateOfficerOptions(self)
    return {
        decay_dkp_value = {
            name = CLM.L["Decay DKP %"],
            desc = CLM.L["DKP % that will be decayed."],
            type = "input",
            set = function(i, v) self.decayValue = v end,
            get = function(i) return self.decayValue end,
            width = "half",
            pattern = CONSTANTS.REGEXP_FLOAT,
            order = 21
        },
        decay_negative = {
            name = CLM.L["Negatives"],
            desc = CLM.L["Include players with negative standings."],
            type = "toggle",
            set = function(i, v) self.includeNegative = v end,
            get = function(i) return self.includeNegative end,
            width = "half",
            order = 22
        },
        decay_dkp = {
            name = CLM.L["Decay"],
            desc = CLM.L["Execute decay for selected players or everyone if none selected."],
            type = "execute",
            width = "full",
            func = (function(i)
                -- Decay Value
                local decayValue = tonumber(self.decayValue)
                if not decayValue then LOG:Debug("StandingsGUI(Decay): missing decay value"); return end
                if decayValue > 100 or decayValue < 0 then LOG:Warning("Standings: Decay value should be between 0 and 100%"); return end
                -- Selected: roster, profiles
                local roster, profiles = self:GetSelected()
                if roster == nil then
                    LOG:Debug("StandingsGUI(Decay): roster == nil")
                    return
                end
                if not profiles or #profiles == 0 then
                    LOG:Debug("StandingsGUI(Decay): profiles == 0")
                    return
                end
                if #profiles == #roster:Profiles() then
                    PointManager:UpdateRosterPoints(roster, decayValue, CONSTANTS.POINT_CHANGE_REASON.DECAY, CONSTANTS.POINT_MANAGER_ACTION.DECAY, not self.includeNegative)
                else
                    local filter
                    if not self.includeNegative then
                        filter = (function(_roster, profile)
                            return (_roster:Standings(profile:GUID()) >= 0)
                        end)
                    end
                    roster, profiles = self:GetSelected(filter)
                    if not profiles or #profiles == 0 then
                        LOG:Debug("StandingsGUI(Decay): profiles == 0")
                        return
                    end
                    PointManager:UpdatePoints(roster, profiles, decayValue, CONSTANTS.POINT_CHANGE_REASON.DECAY, CONSTANTS.POINT_MANAGER_ACTION.DECAY)
                end
            end),
            confirm = true,
            order = 23
        }
    }
end

local function CreateManagementOptions(self, container)
    local ManagementOptions = AceGUI:Create("SimpleGroup")
    ManagementOptions:SetLayout("Flow")
    ManagementOptions:SetWidth(200)
    self.ManagementOptions = ManagementOptions
    self.filterOptions = {}
    self.searchString = ""
    self.searchMethod = nil
    self.decayValue = nil
    self.includeNegative = false
    self.awardValue = nil
    self.note = ""
    self.awardReason = CONSTANTS.POINT_CHANGE_REASON.MANUAL_ADJUSTMENT
    for _=1,9 do table.insert( self.filterOptions, true ) end
    self.filterOptions[FILTER_IN_RAID] = false
    self.filterOptions[FILTER_NOT_IN_GUILD] = false
    self.filterOptions[FILTER_IN_GUILD] = false
    self.filterOptions[FILTER_MAINS_ONLY] = false
    local options = {
        type = "group",
        args = {}
    }
    mergeDictsInline(options.args, GenerateUntrustedOptions(self))
    if ACL:CheckLevel(CONSTANTS.ACL.LEVEL.ASSISTANT) then
        mergeDictsInline(options.args, GenerateManagerOptions(self))
    end
    if ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) then
        mergeDictsInline(options.args, GenerateOfficerOptions(self))
    end
    LIBS.registry:RegisterOptionsTable("clm_standings_gui_options", options)
    LIBS.gui:Open("clm_standings_gui_options", ManagementOptions)
    self.st:SetFilter((function(stobject, row)
        local playerName = ST_GetName(row)
        local class = ST_GetClass(row)

        -- Check Search first, discard others
        if self.searchMethod then
            return self.searchMethod(playerName)
        end

        -- Check class filter

        local status
        for id, _class in pairs(GetColorCodedClassDict()) do
            if class == _class then
                status = self.filterOptions[id]
            end
        end
        if status == nil then return false end -- failsafe
        if self.filterOptions[FILTER_IN_RAID] then
            local isInRaid = {}
            for i=1,MAX_RAID_MEMBERS do
                local name = GetRaidRosterInfo(i)
                if name then
                    name = UTILS.RemoveServer(name)
                    isInRaid[name] = true
                end
            end
            status = status and isInRaid[playerName]
        elseif self.filterOptions[FILTER_STANDBY] then
            if RaidManager:IsInProgressingRaid() then
                local profile = ProfileManager:GetProfileByName(playerName)
                if profile then
                    status = status and RaidManager:GetRaid():IsPlayerOnStandby(profile:GUID())
                end
            elseif RaidManager:IsInCreatedRaid() then
                local profile = ProfileManager:GetProfileByName(playerName)
                if profile then
                    status = status and StandbyStagingManager:IsPlayerOnStandby(RaidManager:GetRaid():UID(), profile:GUID())
                end
            else
                status = false
            end
        end
        if self.filterOptions[FILTER_MAINS_ONLY] then
            local profile = ProfileManager:GetProfileByName(playerName)
            if profile then
                status = status and (profile:Main() == "")
            end
        end
        if self.filterOptions[FILTER_NOT_IN_GUILD] then
            status = status and not GuildInfoListener:GetGuildies()[playerName]
        end
        if self.filterOptions[FILTER_IN_GUILD] then
            status = status and GuildInfoListener:GetGuildies()[playerName]
        end
        return status
    end))

    return ManagementOptions
end

local function CreateStandingsDisplay(self)
    -- Profile Scrolling Table
    local columns = {
        {   name = CLM.L["Name"],   width = 100 },
        {   name = CLM.L["DKP"],    width = 80, sort = ScrollingTable.SORT_DSC, color = {r = 0.0, g = 0.93, b = 0.0, a = 1.0} },
        {   name = CLM.L["Class"],  width = 60,
            comparesort = UTILS.LibStCompareSortWrapper(
                (function(a1, b1)
                    return RemoveColorCode(a1), RemoveColorCode(b1)
                end)
            )
        },
        {   name = CLM.L["Spec"],   width = 60 },
        {   name = CLM.L["Attendance [%]"], width = 90,
            comparesort = UTILS.LibStCompareSortWrapper(
                (function(a1, b1)
                    return tonumber(RemoveColorCode(a1)), tonumber(RemoveColorCode(b1))
                end)
            )
        }
    }
    local StandingsGroup = AceGUI:Create("SimpleGroup")
    StandingsGroup:SetLayout("Flow")
    StandingsGroup:SetHeight(520)
    StandingsGroup:SetWidth(440)
    -- Roster selector
    local RosterSelectorDropDown = AceGUI:Create("Dropdown")
    RosterSelectorDropDown:SetLabel(CLM.L["Select roster"])
    RosterSelectorDropDown:SetCallback("OnValueChanged", function() self:Refresh() end)
    self.RosterSelectorDropDown = RosterSelectorDropDown
    StandingsGroup:AddChild(RosterSelectorDropDown)
    -- Standings
    self.st = ScrollingTable:CreateST(columns, 25, 18, nil, StandingsGroup.frame, true)
    self.st:EnableSelection(true)
    self.st.frame:SetPoint("TOPLEFT", RosterSelectorDropDown.frame, "TOPLEFT", 0, -60)
    self.st.frame:SetBackdropColor(0.1, 0.1, 0.1, 0.1)
    -- Dropdown menu
    local RightClickMenu = CLM.UTILS.GenerateDropDownMenu({
        {
            title = CLM.L["Add to standby"],
            func = (function()
                if not RaidManager:IsInRaid() then
                    LOG:Message(CLM.L["Not in raid"])
                    return
                end
                local roster, profiles = self:GetSelected()
                local raid = RaidManager:GetRaid()
                if roster ~= raid:Roster() then
                    LOG:Message(string.format(
                        CLM.L["You can only bench players from same roster as the raid (%s)."],
                        RosterManager:GetRosterNameByUid(raid:Roster():UID())
                    ))
                    return
                end

                if RaidManager:IsInProgressingRaid() then
                    if #profiles > 10 then
                        LOG:Message(string.format(
                            CLM.L["You can %s max %d players to standby at the same time to a %s raid."],
                            CLM.L["add"], 10, CLM.L["progressing"]
                        ))
                        return
                    end
                    RaidManager:AddToStandby(RaidManager:GetRaid(), profiles)
                elseif RaidManager:IsInCreatedRaid() then
                    if #profiles > 25 then
                        LOG:Message(string.format(
                            CLM.L["You can %s max %d players to standby at the same time to a %s raid."],
                            CLM.L["add"], 25, CLM.L["created"]
                        ))
                        return
                    end
                    for _, profile in ipairs(profiles) do
                        StandbyStagingManager:AddToStandby(RaidManager:GetRaid():UID(), profile:GUID())
                    end
                end
                self:Refresh(true)
            end),
            trustedOnly = true,
            color = "eeee00"
        },
        {
            title = CLM.L["Remove from standby"],
            func = (function()
                if not RaidManager:IsInRaid() then
                    LOG:Message(CLM.L["Not in raid"])
                    return
                end
                local roster, profiles = self:GetSelected()
                local raid = RaidManager:GetRaid()
                if roster ~= raid:Roster() then
                    LOG:Message(string.format(
                        CLM.L["You can only remove from bench players from same roster as the raid (%s)."],
                        RosterManager:GetRosterNameByUid(raid:Roster():UID())
                    ))
                    return
                end

                if RaidManager:IsInProgressingRaid() then
                    if #profiles > 10 then
                        LOG:Message(string.format(
                            CLM.L["You can %s max %d players from standby at the same time to a %s raid."],
                            CLM.L["remove"], 10, CLM.L["progressing"]
                        ))
                        return
                    end
                    RaidManager:RemoveFromStandby(RaidManager:GetRaid(), profiles)
                elseif RaidManager:IsInCreatedRaid() then
                    if #profiles > 25 then
                        LOG:Message(string.format(
                            CLM.L["You can %s max %d players from standby at the same time to a %s raid."],
                            CLM.L["remove"], 25, CLM.L["created"]
                        ))
                        return
                    end
                    for _, profile in ipairs(profiles) do
                        StandbyStagingManager:RemoveFromStandby(RaidManager:GetRaid():UID(), profile:GUID())
                    end
                end
                self:Refresh(true)
            end),
            trustedOnly = true,
            color = "eeee00"
        },
        {
            separator = true,
            trustedOnly = true
        },
        {
            title = CLM.L["Remove from roster"],
            func = (function(i)
                local roster, profiles = self:GetSelected()
                if roster == nil then
                    LOG:Debug("StandingsGUI(Remove): roster == nil")
                    return
                end
                if not profiles or #profiles == 0 then
                    LOG:Debug("StandingsGUI(Remove): profiles == 0")
                    return
                end
                if #profiles > 10 then
                    LOG:Message(string.format(
                        CLM.L["You can remove max %d players from roster at the same time."],
                        10
                    ))
                    return
                end
                RosterManager:RemoveProfilesFromRoster(roster, profiles)
            end),
            trustedOnly = true,
            color = "cc0000"
        },
    },
    CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.ASSISTANT),
    CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER)
    )
    -- OnEnter handler -> on hover
    local OnEnterHandler = (function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        local status = self.st.DefaultEvents["OnEnter"](rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        local rowData = self.st:GetRow(realrow)
        if not rowData or not rowData.cols then return status end
        local tooltip = self.tooltip
        if not tooltip then return end
        tooltip:SetOwner(rowFrame, "ANCHOR_TOPRIGHT")
        local weeklyGain = ST_GetWeeklyGains(rowData)
        local weeklyCap = ST_GetWeeklyCap(rowData)
        tooltip:AddLine(CLM.L["Weekly gains:"])
        local gains = weeklyGain
        if weeklyCap > 0 then
            gains = gains .. " / " .. weeklyCap
        end
        tooltip:AddLine(gains)
        tooltip:Show()
        return status
    end)
    -- OnLeave handler -> on hover out
    local OnLeaveHandler = (function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        local status = self.st.DefaultEvents["OnLeave"](rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        self.tooltip:Hide()
        return status
    end)
    -- OnClick handler -> click
    local OnClickHandler = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
        local rightButton = (button == "RightButton")
        local status
        local selected = self.st:GetSelection()
        local isSelected = false
        for _, _selected in ipairs(selected) do
            if _selected == realrow then
                isSelected = true
                break
            end
        end
        if not isSelected then
            status = self.st.DefaultEvents["OnClick"](rowFrame, cellFrame, data, cols, row, realrow, column, table, rightButton and "LeftButton" or button, ...)
        end
        if rightButton then
            UTILS.LibDD:CloseDropDownMenus()
            UTILS.LibDD:ToggleDropDownMenu(1, nil, RightClickMenu, cellFrame, -20, 0)
        end
         -- Delayed because selection in lib is updated after this function returns
        C_Timer.After(0.01, function()
            self.numSelected = #self.st:GetSelection()
            UpdateStatusText(self)
        end)
        return status
    end
    -- end
    self.st:RegisterEvents({
        OnClick = OnClickHandler,
        OnEnter = OnEnterHandler,
        OnLeave = OnLeaveHandler
    })

    return StandingsGroup
end

function StandingsGUI:Create()
    LOG:Trace("StandingsGUI:Create()")
    -- Main Frame
    local f = AceGUI:Create("Frame")
    f:SetTitle(CLM.L["Standings"])
    f:SetStatusText("")
    f:SetLayout("Table")
    f:SetUserData("table", { columns = {0, 0}, alignV =  "top" })
    f:EnableResize(false)
    f:SetWidth(675)
    f:SetHeight(655)
    self.top = f
    UTILS.MakeFrameCloseOnEsc(f.frame, "CLM_Rosters_GUI")
    f:AddChild(CreateStandingsDisplay(self))
    f:AddChild(CreateManagementOptions(self))
    RestoreLocation(self)
    -- Hide by default
    f:Hide()
end

function StandingsGUI:Refresh(visible)
    LOG:Trace("StandingsGUI:Refresh()")
    if not self._initialized then return end
    if visible and not self.top:IsVisible() then return end
    self.st:ClearSelection()
    self:RefreshRosters()

    local roster = self:GetCurrentRoster()
    if not roster then return end
    local weeklyCap = roster:GetConfiguration("weeklyCap")
    local rowId = 1
    local data = {}
    for GUID,value in pairs(roster:Standings()) do
        local profile = ProfileManager:GetProfileByGUID(GUID)
        local attendance = round(roster:GetAttendance(GUID) or 0, 0)
        if profile then
            local row = {cols = {}}
            row.cols[1] = {value = profile:Name()}
            row.cols[2] = {value = value}
            row.cols[3] = {value = UTILS.ColorCodeClass(profile:Class())}
            row.cols[4] = {value = profile:SpecString()}
            row.cols[5] = {value = ColorCodeByPercentage(attendance)}
            -- not displayed
            row.cols[6] = {value = roster:GetCurrentGainsForPlayer(GUID)}
            row.cols[7] = {value = weeklyCap}
            data[rowId] = row
            rowId = rowId + 1
        end
    end
    self.st:SetData(data)
    LIBS.gui:Open("clm_standings_gui_options", self.ManagementOptions)
    self.numInRoster = #data
    UpdateStatusText(self)
end

function StandingsGUI:GetCurrentRoster()
    self.db.selectedRosterUid = self.RosterSelectorDropDown:GetValue()
    return RosterManager:GetRosterByUid(self.db.selectedRosterUid)
end

function StandingsGUI:GetSelected(filter)
    if type(filter) ~= "function" then
        filter = (function(roster, profile) return profile end)
    end
    -- Roster
    local roster = self:GetCurrentRoster()
    if not roster then
        return nil, nil
    end
    -- Profiles
    local selected = self.st:GetSelection()
    local profiles = {}
    if #selected == 0 then -- nothing selected: assume all visible are selected
        selected = self.st:DoFilter()
    end
    for _,s in pairs(selected) do
        local profile = ProfileManager:GetProfileByName(ST_GetName(self.st:GetRow(s)))
        if profile then
            table.insert(profiles, profile)
        else
            LOG:Debug("No profile for %s", ST_GetName(self.st:GetRow(s)))
        end
    end
    local profiles_filtered = {}
    for _, profile in ipairs(profiles) do
        if filter(roster, profile) then
            table.insert(profiles_filtered, profile)
        end
    end
    return roster, profiles_filtered
end

function StandingsGUI:RefreshRosters()
    LOG:Trace("StandingsGUI:RefreshRosters()")
    local rosters = RosterManager:GetRosters()
    local rosterUidMap = {}
    local rosterList = {}
    local positionOfSavedRoster = 1
    local n = 1
    for name, roster in pairs(rosters) do
        rosterUidMap[roster:UID()] = name
        rosterList[n] = roster:UID()
        if roster:UID() == self.db.selectedRosterUid then
            positionOfSavedRoster = n
        end
        n = n + 1
    end
    self.RosterSelectorDropDown:SetList(rosterUidMap, rosterList)
    if not self.RosterSelectorDropDown:GetValue() then
        if #rosterList > 0 then
            self.RosterSelectorDropDown:SetValue(rosterList[positionOfSavedRoster])
        end
    end
end

function StandingsGUI:Toggle()
    LOG:Trace("StandingsGUI:Toggle()")
    if not self._initialized then return end
    if self.top:IsVisible() then
        self.top:Hide()
    else
        if IsInRaid() then
            self.filterOptions[FILTER_IN_RAID] = true
            self.filterOptions[FILTER_STANDBY] = false
        end
        self:Refresh()
        self.top:Show()
    end
end

function StandingsGUI:RegisterSlash()
    local options = {
        standings = {
            type = "execute",
            name = "Standings",
            desc = CLM.L["Toggle standings window display"],
            handler = self,
            func = "Toggle",
        }
    }
    MODULES.ConfigManager:RegisterSlash(options)
end

function StandingsGUI:Reset()
    LOG:Trace("StandingsGUI:Reset()")
    self.top:ClearAllPoints()
    self.top:SetPoint("CENTER", 0, 0)
end

GUI.Standings = StandingsGUI
