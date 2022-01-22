local _, CLM = ...

-- Libs
local AceGUI = LibStub("AceGUI-3.0")

local LOG = CLM.LOG
local UTILS = CLM.UTILS
local MODULES = CLM.MODULES

local GUI = CLM.GUI

local EventManager = MODULES.EventManager

local XMLExportGUI = {}

local function InitializeDB(self)
    self.db = MODULES.Database:GUI('xmlexport', {
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

function XMLExportGUI:Initialize()
    InitializeDB(self)
    EventManager:RegisterWoWEvent({"PLAYER_LOGOUT"}, (function(...) StoreLocation(self) end))
    self.tooltip = CreateFrame("GameTooltip", "CLMExportGUIDialogTooltip", UIParent, "GameTooltipTemplate")
    self:Create()
    self._initialized = true
end

function XMLExportGUI:Create()
    LOG:Trace("XMLExportGUI:Create()")
    -- Main Frame
    local f = AceGUI:Create("Frame")
    f:SetTitle(CLM.L["Export XML"])
    f:SetStatusText("")
    f:SetLayout("Fill")
    f:EnableResize(false)
    f:SetWidth(700)
    f:SetHeight(590)
    self.top = f
    UTILS.MakeFrameCloseOnEsc(f.frame, "CLM_Export_GUI")
    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("")
    editBox:DisableButton(true)
    f:AddChild(editBox)
    self.eb = editBox
    RestoreLocation(self)
    -- Hide by default
    f:Hide()
end

function XMLExportGUI:Show(text)
    LOG:Trace("XMLExportGUI:Show()")
    if not self._initialized then return end
    self.eb:SetText(text)
    self.top:Show()
end

GUI.XMLExport = XMLExportGUI