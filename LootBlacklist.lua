-- Loot Blacklist: never pick up items on your list.
--
-- The game's own auto loot takes everything before an addon can step in, so
-- while this addon is enabled it turns the game's Auto Loot setting off and
-- auto loots everything else itself. Your auto loot choice is kept in
-- LootBlacklistCharDB.autoLoot (per character) and given back to the game when
-- you disable the addon and at every logout, so the saved game setting stays yours.
-- LootBlacklistDB.autoLoot (account wide) is the choice a new character starts with,
-- because by then the game setting has already been turned off.

local ADDON = ...
local PREFIX = "|cff33ff99Loot Blacklist|r: "
local ROWS = 11
local ROW_HEIGHT = 26

local db
local account
local frame -- manager window, built on first open

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function ItemInstant(item)
    if item == nil or IsSecret(item) then
        return nil
    end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then
        return nil
    end
    local ok, id = pcall(fn, item)
    if ok and type(id) == "number" and not IsSecret(id) then
        return id
    end
    return nil
end

local function ItemInfo(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then
        return nil
    end
    local name, link, quality, _, _, _, _, _, _, icon = fn(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    if not icon then
        icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
    end
    return name, link, quality, icon
end

-- Turn "12345", "item:12345", an item link, or a cached item name into an ID.
local function ParseItem(text)
    if type(text) ~= "string" or IsSecret(text) then
        return nil
    end
    text = strtrim(text)
    if text == "" then
        return nil
    end
    local n = tonumber(text)
    if n and n > 0 then
        return math.floor(n)
    end
    return ItemInstant(text)
end

local function IsBlocked(id)
    return id ~= nil and db ~= nil and db.items[id] ~= nil
end

local function Describe(id)
    local name, link = ItemInfo(id)
    return link or name or (db.items[id] ~= "" and db.items[id]) or ("item " .. id)
end

---------------------------------------------------------------------------
-- Auto loot takeover
---------------------------------------------------------------------------

local settingCVar = false

local function GetAutoLootCVar()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return get and get("autoLootDefault") == "1"
end

local function SetAutoLootCVar(on)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then
        return
    end
    settingCVar = true
    pcall(set, "autoLootDefault", on and "1" or "0")
    settingCVar = false
end

-- The player's auto loot choice, for this character and as the default for new ones.
local function SetAutoLootChoice(on)
    db.autoLoot = on and true or false
    account.autoLoot = db.autoLoot
end

local function ApplyAutoLootMode()
    if db.enabled then
        if GetAutoLootCVar() then
            SetAutoLootCVar(false)
        end
    else
        SetAutoLootCVar(db.autoLoot)
    end
end

local function OnCVarUpdate(name, value)
    if settingCVar or not db or not db.enabled then
        return
    end
    if type(name) ~= "string" or name:lower() ~= "autolootdefault" then
        return
    end
    if tostring(value) == "1" then
        -- The player ticked Auto Loot in the game options: keep auto looting,
        -- but through this addon so blacklisted items stay on the corpse.
        SetAutoLootChoice(true)
        SetAutoLootCVar(false)
        Print("auto loot stays on, and blacklisted items are skipped.")
        if frame and frame:IsShown() then
            frame:Refresh()
        end
    end
end

-- The addon's own auto loot. Like the game's, it keeps the loot window out of
-- sight, takes everything it can, and closes the window when done. Anything it
-- cannot take (full bags, a roll, a bind-on-pickup prompt) brings the window
-- back, as the game does.

local RETRY_DELAY = 0.1
local MAX_PASSES = 10

local session -- the open loot window while the addon auto loots it, else nil
local lootFrameHidden = false

local function SlotItemID(slot)
    if LootSlotHasItem and not LootSlotHasItem(slot) then
        return nil
    end
    return ItemInstant(GetLootSlotLink(slot))
end

local function HideLootFrame(hide)
    local lf = LootFrame
    if not lf or not lf.SetAlpha then
        return
    end
    -- Fade instead of Hide: hiding the loot frame closes the loot.
    if hide and not lootFrameHidden then
        lootFrameHidden = true
        lf:SetAlpha(0)
    elseif not hide and lootFrameHidden then
        lootFrameHidden = false
        lf:SetAlpha(1)
    end
end

-- Stop auto looting this window and let the player see it.
local function HandToPlayer()
    if session then
        session.auto = false
    end
    HideLootFrame(false)
end

local LootPass

local function ScheduleLootPass(s)
    if C_Timer and C_Timer.After then
        C_Timer.After(RETRY_DELAY, function()
            if session == s then
                LootPass()
            end
        end)
    end
end

LootPass = function()
    local s = session
    if not s or not s.auto then
        return
    end
    local left = false -- items the addon still wants to take
    for slot = GetNumLootItems(), 1, -1 do
        local texture, _, _, _, _, locked = GetLootSlotInfo(slot)
        if texture then
            s.sawLoot = true
            local id = SlotItemID(slot)
            if IsBlocked(id) then
                if not s.noted[slot] then
                    s.noted[slot] = true
                    s.skipped[#s.skipped + 1] = GetLootSlotLink(slot) or Describe(id)
                end
            else
                left = true
                -- Ask for each slot once, so a bind-on-pickup prompt shows only once.
                if not locked and not s.asked[slot] then
                    s.asked[slot] = true
                    LootSlot(slot)
                end
            end
        end
    end

    if not s.sawLoot then
        -- The loot list can arrive a moment after the event.
        s.passes = s.passes + 1
        if s.passes <= MAX_PASSES then
            ScheduleLootPass(s)
        end
        return
    end
    if not s.announced and db.announce and #s.skipped > 0 and not left then
        s.announced = true
        Print("left behind " .. table.concat(s.skipped, ", "))
    end
    if not left then
        CloseLoot()
        return
    end
    s.passes = s.passes + 1
    if s.passes > MAX_PASSES then
        HandToPlayer() -- full bags, a roll in progress, or a prompt waiting on the player
        return
    end
    ScheduleLootPass(s)
end

-- Runs on LOOT_READY and LOOT_OPENED; clients send one or both.
local function OnLootOpened()
    if not db.enabled then
        return
    end
    if not session then
        local auto = db.autoLoot
        if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then
            auto = not auto
        end
        session = { auto = auto, passes = 0, asked = {}, noted = {}, skipped = {} }
        if auto then
            HideLootFrame(true)
        end
    end
    LootPass()
end

local function OnLootClosed()
    session = nil
    HideLootFrame(false)
end

---------------------------------------------------------------------------
-- Blacklist edits
---------------------------------------------------------------------------

local function Add(id)
    if not id then
        return false
    end
    local name = ItemInfo(id)
    db.items[id] = name or ""
    Print("added " .. Describe(id) .. ". It will never be looted.")
    if frame and frame:IsShown() then
        frame:Refresh()
    end
    return true
end

local function Remove(id)
    if not IsBlocked(id) then
        return false
    end
    local label = Describe(id)
    db.items[id] = nil
    Print("removed " .. label .. ".")
    if frame and frame:IsShown() then
        frame:Refresh()
    end
    return true
end

local function Toggle(id)
    if IsBlocked(id) then
        Remove(id)
    else
        Add(id)
    end
end

---------------------------------------------------------------------------
-- Manager window
---------------------------------------------------------------------------

local function SortedIDs(filter)
    local ids = {}
    filter = filter and strtrim(filter):lower() or ""
    for id, saved in pairs(db.items) do
        local name = ItemInfo(id) or saved or ""
        if filter == "" or name:lower():find(filter, 1, true) or tostring(id):find(filter, 1, true) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b)
        local na = (ItemInfo(a) or db.items[a] or ""):lower()
        local nb = (ItemInfo(b) or db.items[b] or ""):lower()
        if na ~= nb then
            return na < nb
        end
        return a < b
    end)
    return ids
end

local function AddFromCursor()
    local kind, id = GetCursorInfo()
    if kind ~= "item" or type(id) ~= "number" then
        return false
    end
    ClearCursor()
    if IsBlocked(id) then
        Print(Describe(id) .. " is already on the list.")
    else
        Add(id)
    end
    return true
end

local function MakeCheck(parent, label, tip, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    local text = check.Text or check.text
    if not text then
        text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    end
    text:SetFontObject("GameFontHighlightSmall")
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    return check
end

local function BuildFrame()
    local f = CreateFrame("Frame", "LootBlacklistFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnReceiveDrag", AddFromCursor)
    f:SetScript("OnMouseDown", AddFromCursor)
    f:Hide()
    tinsert(UISpecialFrames, "LootBlacklistFrame")

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("Loot Blacklist - " .. (UnitName("player") or "this character"))

    f.enabled = MakeCheck(f, "Enabled", "Skip blacklisted items when looting. Turning this off gives the game its Auto Loot setting back.", function(on)
        db.enabled = on
        ApplyAutoLootMode()
        f:Refresh()
    end)
    f.enabled:SetPoint("TOPLEFT", 12, -30)

    f.auto = MakeCheck(f, "Auto loot everything else", "Loot all other items as soon as the loot window opens. Hold Shift to do the opposite for one corpse, like the game's Auto Loot.", function(on)
        SetAutoLootChoice(on)
    end)
    f.auto:SetPoint("TOPLEFT", f.enabled, "BOTTOMLEFT", 0, 2)

    f.announce = MakeCheck(f, "Say in chat what was left behind", "Print the blacklisted items left on each corpse.", function(on)
        db.announce = on
    end)
    f.announce:SetPoint("TOPLEFT", f.auto, "BOTTOMLEFT", 0, 2)

    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(220, 22)
    input:SetPoint("TOPLEFT", f.announce, "BOTTOMLEFT", 8, -8)
    input:SetAutoFocus(false)
    input:SetFontObject("ChatFontNormal")
    f.input = input

    local placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 2, 0)
    placeholder:SetText("Item ID, name, or Shift-click a link")

    local addButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addButton:SetSize(70, 22)
    addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
    addButton:SetText("Add")

    local function SubmitInput()
        local id = ParseItem(input:GetText())
        if not id then
            Print("could not find that item. Try its item ID, or Shift-click its link into the box.")
            return
        end
        input:SetText("")
        input:ClearFocus()
        if IsBlocked(id) then
            Print(Describe(id) .. " is already on the list.")
        else
            Add(id)
        end
    end
    addButton:SetScript("OnClick", SubmitInput)
    input:SetScript("OnEnterPressed", SubmitInput)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    input:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -6)
    hint:SetWidth(310)
    hint:SetJustifyH("LEFT")
    hint:SetText("Drop an item on this window, or Ctrl+Shift+right-click any item in your bags, the loot window, or chat.")

    local search = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    search:SetSize(300, 20)
    search:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 6, -8)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function()
        f.offset = 0
        f:Refresh()
    end)
    f.search = search

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -6)
    list:SetSize(316, ROWS * ROW_HEIGHT)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        f.offset = math.max(0, (f.offset or 0) - delta * 3)
        f:Refresh()
    end)

    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(316, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 2, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWidth(200)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.idText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.idText:SetPoint("RIGHT", -30, 0)

        row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.remove:SetSize(22, 22)
        row.remove:SetPoint("RIGHT", 0, 0)
        row.remove:SetScript("OnClick", function()
            Remove(row.itemID)
        end)
        row.remove:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove from the blacklist")
            GameTooltip:Show()
        end)
        row.remove:SetScript("OnLeave", GameTooltip_Hide)

        row:SetScript("OnClick", function(self, button)
            if AddFromCursor() then
                return
            end
            if button == "RightButton" then
                Remove(self.itemID)
            elseif IsModifiedClick("CHATLINK") then
                local _, link = ItemInfo(self.itemID)
                if link then
                    ChatEdit_InsertLink(link)
                end
            end
        end)
        row:SetScript("OnReceiveDrag", AddFromCursor)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:AddLine("Right-click to remove", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        f.rows[i] = row
    end

    f.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(280)
    f.empty:SetText("No items yet. Ctrl+Shift+right-click an item to add it.")

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer:SetPoint("BOTTOMLEFT", 14, 12)

    function f:Refresh()
        self.enabled:SetChecked(db.enabled)
        self.auto:SetChecked(db.autoLoot)
        self.announce:SetChecked(db.announce)
        self.auto:SetEnabled(db.enabled)
        self.announce:SetEnabled(db.enabled)

        local ids = SortedIDs(self.search:GetText())
        local maxOffset = math.max(0, #ids - ROWS)
        self.offset = math.min(self.offset or 0, maxOffset)
        for i = 1, ROWS do
            local row = self.rows[i]
            local id = ids[i + self.offset]
            if id then
                local name, _, quality, icon = ItemInfo(id)
                if name and db.items[id] ~= name then
                    db.items[id] = name
                end
                row.itemID = id
                row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.name:SetText(name or (db.items[id] ~= "" and db.items[id]) or "Loading...")
                local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                if color then
                    row.name:SetTextColor(color.r, color.g, color.b)
                else
                    row.name:SetTextColor(1, 0.82, 0)
                end
                row.idText:SetText(id)
                row:Show()
            else
                row.itemID = nil
                row:Hide()
            end
        end

        local total = 0
        for _ in pairs(db.items) do
            total = total + 1
        end
        self.empty:SetShown(total == 0)
        local status = db.enabled and "" or "  |cffff6060(disabled)|r"
        if #ids > ROWS then
            self.footer:SetText(("%d-%d of %d shown, %d blacklisted%s"):format(self.offset + 1, math.min(#ids, self.offset + ROWS), #ids, total, status))
        else
            self.footer:SetText(("%d blacklisted%s"):format(total, status))
        end
    end

    f:SetScript("OnShow", f.Refresh)
    return f
end

local function ShowUI(toggle)
    if not frame then
        frame = BuildFrame()
    end
    if toggle and frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        frame:Refresh()
    end
end

function LootBlacklist_OnAddonCompartmentClick()
    ShowUI(true)
end

-- For other add-ons (ahprice). A menu host shows one shared item menu with a
-- Never loot box, so our Ctrl+Shift+right-click opens that menu instead of ours.
local menuHost = nil
LootBlacklistAPI = {
    version = 1,
    IsBlocked = function(id)
        return IsBlocked(tonumber(id))
    end,
    Toggle = function(id)
        id = tonumber(id)
        if id then
            Toggle(id)
        end
    end,
    Open = function()
        ShowUI(false)
    end,
    -- fn(itemID) opens the host's menu; nil removes the host.
    SetMenuHost = function(fn)
        menuHost = type(fn) == "function" and fn or nil
    end,
}

---------------------------------------------------------------------------
-- Ctrl+Shift+right-click on any item
---------------------------------------------------------------------------

local lastClickID, lastClickTime = nil, 0

local function OnItemClick(id)
    if not id then
        return
    end
    -- Bags can report the same click through two hooks; act once.
    local now = GetTime()
    if id == lastClickID and now - lastClickTime < 0.3 then
        return
    end
    lastClickID, lastClickTime = id, now

    if menuHost and pcall(menuHost, id) then
        return
    end

    if MenuUtil and MenuUtil.CreateContextMenu then
        local blocked = IsBlocked(id)
        local ok = pcall(MenuUtil.CreateContextMenu, UIParent, function(_, root)
            root:CreateTitle("Loot Blacklist")
            root:CreateButton(blocked and "Remove from blacklist" or "Add to blacklist (never loot)", function()
                Toggle(id)
            end)
            root:CreateButton("Open Loot Blacklist", function()
                ShowUI()
            end)
        end)
        if ok then
            return
        end
    end
    Toggle(id)
end

local function IsBlacklistClick(button)
    if button == nil and GetMouseButtonClicked then
        button = GetMouseButtonClicked()
    end
    if IsModifiedClick and GetModifiedClick and GetModifiedClick("LOOTBLACKLIST") then
        -- Bindings.xml registers this click (Ctrl+Shift+right by default).
        local ok, hit = pcall(IsModifiedClick, "LOOTBLACKLIST")
        if ok then
            return hit and (button == nil or button == "RightButton")
        end
    end
    if not (IsControlKeyDown() and IsShiftKeyDown()) or IsAltKeyDown() then
        return false
    end
    return button == "RightButton"
end

local function TooltipItemID()
    if not GameTooltip:IsShown() or not GameTooltip.GetItem then
        return nil
    end
    local _, link, id = GameTooltip:GetItem()
    if type(id) == "number" and not IsSecret(id) then
        return id
    end
    return ItemInstant(link)
end

BINDING_HEADER_LOOTBLACKLIST = "Loot Blacklist"
BINDING_NAME_LOOTBLACKLIST_TOGGLE_HOVER = "Add or remove the item under the mouse"
BINDING_NAME_LOOTBLACKLIST_OPEN = "Open Loot Blacklist"

-- Key binding: blacklist whatever item tooltip is showing, without clicking it.
function LootBlacklist_ToggleHovered()
    local id = TooltipItemID()
    if id then
        Toggle(id)
    else
        Print("point at an item first.")
    end
end

local function HookClicks()
    if type(HandleModifiedItemClick) == "function" then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if IsBlacklistClick() then
                OnItemClick(ItemInstant(link))
            end
        end)
    end
    -- Backup for bag buttons that skip HandleModifiedItemClick.
    if type(ContainerFrameItemButtonMixin) == "table" and type(ContainerFrameItemButtonMixin.OnClick) == "function" then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnClick", function(_, button)
            if IsBlacklistClick(button) then
                OnItemClick(TooltipItemID())
            end
        end)
    end

    -- Shift-clicking a link while the Add box has focus puts the link there.
    local function insertLink(link)
        if frame and frame.input and frame.input:HasFocus() and type(link) == "string" and not IsSecret(link) then
            frame.input:SetText(link)
        end
    end
    if type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", insertLink)
    end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
        hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink)
    end
end

local function HookTooltip()
    local function addLine(tip, id)
        if IsBlocked(id) then
            tip:AddLine("Loot Blacklist: never looted", 1, 0.35, 0.35)
        end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
            if tip ~= GameTooltip and tip ~= ItemRefTooltip then
                return
            end
            local id = data and data.id
            if type(id) == "number" and not IsSecret(id) then
                addLine(tip, id)
            end
        end)
    elseif GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tip)
            local _, link = tip:GetItem()
            addLine(tip, ItemInstant(link))
        end)
    end
end

---------------------------------------------------------------------------
-- Slash commands and events
---------------------------------------------------------------------------

SLASH_LOOTBLACKLIST1 = "/lootblacklist"
SLASH_LOOTBLACKLIST2 = "/lbl"
SlashCmdList.LOOTBLACKLIST = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "add" or cmd == "remove" or cmd == "del" then
        local id = ParseItem(rest)
        if not id then
            Print("usage: /lbl " .. cmd .. " <item ID or link>")
        elseif cmd == "add" then
            Add(id)
        elseif not Remove(id) then
            Print(Describe(id) .. " is not on the list.")
        end
    elseif cmd == "on" or cmd == "off" then
        db.enabled = cmd == "on"
        ApplyAutoLootMode()
        Print(db.enabled and "enabled." or "disabled. The game's Auto Loot setting is back.")
        if frame and frame:IsShown() then
            frame:Refresh()
        end
    elseif cmd == "" or cmd == "show" then
        ShowUI(true)
    else
        Print("/lbl opens the list. /lbl add <item>, /lbl remove <item>, /lbl on, /lbl off.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        -- Each character has its own list and settings, so bank alts loot everything.
        LootBlacklistCharDB = type(LootBlacklistCharDB) == "table" and LootBlacklistCharDB or {}
        db = LootBlacklistCharDB
        db.items = type(db.items) == "table" and db.items or {}
        if db.enabled == nil then
            db.enabled = true
        end
        if db.announce == nil then
            db.announce = true
        end
        LootBlacklistDB = type(LootBlacklistDB) == "table" and LootBlacklistDB or {}
        account = LootBlacklistDB
        if db.autoLoot == nil then
            -- A new character: the game setting is already off if another
            -- character runs this addon, so use the account-wide choice.
            if account.autoLoot ~= nil then
                db.autoLoot = account.autoLoot
            else
                db.autoLoot = GetAutoLootCVar() and true or false
            end
        elseif db.autoLoot == false and not db.autoLootFixed then
            -- Older versions gave each new character the game setting after
            -- another character had turned it off, so they wrongly started on
            -- manual looting. Turn auto loot back on once for them.
            db.autoLoot = true
        end
        db.autoLootFixed = true
        if account.autoLoot == nil then
            account.autoLoot = db.autoLoot
        end
        -- Each step on its own, so one failure does not stop the rest.
        for _, step in ipairs({ ApplyAutoLootMode, HookClicks, HookTooltip }) do
            local ok, err = pcall(step)
            if not ok then
                Print("a startup step failed: " .. tostring(err))
            end
        end
        self:RegisterEvent("LOOT_READY")
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("LOOT_SLOT_CLEARED")
        self:RegisterEvent("LOOT_BIND_CONFIRM")
        self:RegisterEvent("LOOT_CLOSED")
        self:RegisterEvent("CVAR_UPDATE")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_LOGOUT")
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "LOOT_SLOT_CLEARED" then
        LootPass()
    elseif event == "LOOT_BIND_CONFIRM" then
        -- A bind-on-pickup prompt needs the player; show the window with it.
        HandToPlayer()
    elseif event == "LOOT_CLOSED" then
        OnLootClosed()
    elseif event == "CVAR_UPDATE" then
        OnCVarUpdate(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The game can restore its saved CVar on login; take it back over.
        ApplyAutoLootMode()
    elseif event == "PLAYER_LOGOUT" then
        -- Save the player's own choice, so the game setting is right even if
        -- the addon is removed before the next login.
        SetAutoLootCVar(db.autoLoot)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local id = ...
        if IsBlocked(id) and frame and frame:IsShown() then
            frame:Refresh()
        end
    end
end)
