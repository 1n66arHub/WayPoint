--[[
    ═══════════════════════════════════════════════════════════
    MYWAYPOINTS v2.1  (patched)
    Universal Waypoint Manager
    Made By in66ar
    ═══════════════════════════════════════════════════════════
    Patch notes:
    - "-" = true minimize (show floating button)
    - "×" = true close (hide window + floating)
    - Preserve dragged window position across minimize/reopen
    - Drag threshold 8px, tap-safe for both window & floating btn
    - Filter row: horizontal scroll for narrow screens
    - Duplicate FAVORITES buttons unified
    - Saved Maps shows game name if known, else PlaceId
    - History: no confusing entries on BACK
    - Database & all v2.1 features preserved
]]

--============================================================
-- SERVICES
--============================================================
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

--============================================================
-- CONSTANTS
--============================================================
local DATA_FILE         = "MyWaypoints_v2_Data.json"
local LEGACY_FILE       = "MyWaypoints_Data.txt"
local GUI_NAME          = "MyWaypointGUI_v2"
local CREDIT_TEXT       = "Made By in66ar"
local VERSION_TEXT      = "v2.1"
local MAX_HISTORY       = 12
local DISTANCE_INTERVAL = 1.2
local SAVE_DEBOUNCE     = 0.4
local DRAG_THRESHOLD    = 8
local FLOATING_SIZE     = 52

--============================================================
-- THEME
--============================================================
local Theme = {
    BG         = Color3.fromRGB(20, 20, 22),
    PANEL      = Color3.fromRGB(30, 30, 33),
    PANEL_ALT  = Color3.fromRGB(40, 40, 44),
    CARD       = Color3.fromRGB(34, 34, 38),
    BORDER     = Color3.fromRGB(70, 70, 75),
    BORDER_LO  = Color3.fromRGB(52, 52, 57),
    TEXT       = Color3.fromRGB(235, 235, 235),
    TEXT_DIM   = Color3.fromRGB(155, 155, 160),
    TEXT_MUTE  = Color3.fromRGB(120, 120, 128),

    ACTION     = Color3.fromRGB(56, 60, 70),
    ACTION_TP  = Color3.fromRGB(62, 68, 80),
    ACTIVE     = Color3.fromRGB(56, 58, 66),
    ACTIVE_BRD = Color3.fromRGB(110, 115, 130),
    INACTIVE   = Color3.fromRGB(34, 34, 38),

    GOOD       = Color3.fromRGB(120, 200, 140),
    DANGER     = Color3.fromRGB(215, 100, 100),
    WARN       = Color3.fromRGB(225, 175, 90),
    FAV        = Color3.fromRGB(240, 200, 100),
    TOGGLE     = Color3.fromRGB(40, 40, 46),

    TR_WINDOW  = 0.06,
    TR_PANEL   = 0.14,
    TR_CARD    = 0.08,
}

--============================================================
-- PERSISTENCE
--============================================================
local FS_AVAILABLE = (type(writefile) == "function"
    and type(readfile) == "function"
    and type(isfile) == "function")

--============================================================
-- DATABASE
--============================================================
local Database = {}
local CurrentPlaceId = tostring(game.PlaceId)

local function isArrayOfWaypoints(value)
    if type(value) ~= "table" then return false end
    for _, wp in ipairs(value) do
        if type(wp) ~= "table" then return false end
        if type(wp.NAME) ~= "string" then return false end
        if type(wp.COORD) ~= "table" or #wp.COORD < 3 then return false end
        for i = 1, 3 do
            if type(wp.COORD[i]) ~= "number" then return false end
        end
        wp.FAVORITE = wp.FAVORITE == true
        wp.CREATED  = type(wp.CREATED) == "number" and wp.CREATED or os.time()
    end
    return true
end

local function sanitizeDatabase(raw)
    local clean = {}
    if type(raw) ~= "table" then return clean end
    for placeId, list in pairs(raw) do
        if placeId == "__meta" then
            if type(list) == "table" then
                clean.__meta = {}
                if type(list.LAST_POSITION) == "table" then
                    local lp = list.LAST_POSITION
                    if type(lp.COORD) == "table" and #lp.COORD >= 3 then
                        clean.__meta.LAST_POSITION = {
                            NAME    = type(lp.NAME) == "string" and lp.NAME or "Last Position",
                            COORD   = { tonumber(lp.COORD[1]) or 0, tonumber(lp.COORD[2]) or 0, tonumber(lp.COORD[3]) or 0 },
                            PLACEID = tostring(lp.PLACEID or CurrentPlaceId),
                            TIME    = tonumber(lp.TIME) or os.time(),
                        }
                    end
                end
                if type(list.HISTORY) == "table" then
                    clean.__meta.HISTORY = {}
                    for _, h in ipairs(list.HISTORY) do
                        if type(h) == "table" and type(h.COORD) == "table" and #h.COORD >= 3 then
                            table.insert(clean.__meta.HISTORY, {
                                NAME    = type(h.NAME) == "string" and h.NAME or "Waypoint",
                                COORD   = { tonumber(h.COORD[1]) or 0, tonumber(h.COORD[2]) or 0, tonumber(h.COORD[3]) or 0 },
                                PLACEID = tostring(h.PLACEID or CurrentPlaceId),
                                TIME    = tonumber(h.TIME) or os.time(),
                            })
                        end
                    end
                end
                -- NEW: place names cache
                if type(list.PLACE_NAMES) == "table" then
                    clean.__meta.PLACE_NAMES = {}
                    for k, v in pairs(list.PLACE_NAMES) do
                        if type(k) == "string" and type(v) == "string" then
                            clean.__meta.PLACE_NAMES[k] = v
                        end
                    end
                end
            end
        else
            local placeKey = tostring(placeId)
            if isArrayOfWaypoints(list) then
                clean[placeKey] = list
            end
        end
    end
    return clean
end

local function loadDatabase()
    if not FS_AVAILABLE then return {} end
    local ok, decoded
    if isfile(DATA_FILE) then
        ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(DATA_FILE)) end)
        if ok then return sanitizeDatabase(decoded) end
    end
    if isfile(LEGACY_FILE) then
        ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(LEGACY_FILE)) end)
        if ok and type(decoded) == "table" then
            local migrated = {}
            for _, wp in ipairs(decoded) do
                if type(wp) == "table" and wp.GAME and wp.NAME and wp.COORD then
                    local key = tostring(wp.GAME)
                    migrated[key] = migrated[key] or {}
                    table.insert(migrated[key], {
                        NAME = wp.NAME,
                        COORD = wp.COORD,
                        FAVORITE = false,
                        CREATED = os.time(),
                    })
                end
            end
            return sanitizeDatabase(migrated)
        end
    end
    return {}
end

Database = loadDatabase()
Database.__meta = Database.__meta or {}
Database.__meta.HISTORY = Database.__meta.HISTORY or {}
Database.__meta.PLACE_NAMES = Database.__meta.PLACE_NAMES or {}

--============================================================
-- SAVE (debounced)
--============================================================
local savePending = false
local saveToken = 0
local saveStatusLabel

local function writeDatabaseNow()
    if not FS_AVAILABLE then return end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(Database) end)
    if not ok then return end
    pcall(function() writefile(DATA_FILE, encoded) end)
end

local function flashSaved()
    if not (saveStatusLabel and saveStatusLabel.Parent) then return end
    saveStatusLabel.Text = "✓ Saved"
    saveStatusLabel.TextColor3 = Theme.GOOD
    task.delay(1.4, function()
        if saveStatusLabel and saveStatusLabel.Parent then
            saveStatusLabel.Text = FS_AVAILABLE and "Auto-save ON" or "Local persistence unavailable"
            saveStatusLabel.TextColor3 = Theme.TEXT_DIM
        end
    end)
end

local function saveDatabase()
    if not FS_AVAILABLE then
        if saveStatusLabel and saveStatusLabel.Parent then
            saveStatusLabel.Text = "Local persistence unavailable"
            saveStatusLabel.TextColor3 = Theme.WARN
        end
        return
    end
    savePending = true
    saveToken += 1
    local myToken = saveToken
    if saveStatusLabel and saveStatusLabel.Parent then
        saveStatusLabel.Text = "Saving..."
        saveStatusLabel.TextColor3 = Theme.TEXT_DIM
    end
    task.delay(SAVE_DEBOUNCE, function()
        if myToken ~= saveToken then return end
        if not savePending then return end
        savePending = false
        writeDatabaseNow()
        flashSaved()
    end)
end

--============================================================
-- HELPERS
--============================================================
local function getCharacterRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
end

local function getPlaceName()
    local ok, name = pcall(function() return game.Name end)
    if ok and type(name) == "string" and #name > 0 and name ~= "Place" then
        return name
    end
    return nil
end

local function currentPlaceLabel()
    local n = getPlaceName()
    if n then return n end
    return "PlaceId: " .. CurrentPlaceId
end

local function getCurrentWaypoints()
    Database[CurrentPlaceId] = Database[CurrentPlaceId] or {}
    return Database[CurrentPlaceId]
end

local function waypointDistance(wp)
    local root = getCharacterRoot()
    if not root then return nil end
    local wpPos = Vector3.new(wp.COORD[1], wp.COORD[2], wp.COORD[3])
    return math.floor((root.Position - wpPos).Magnitude)
end

local function cloneCoord(c)
    return { c[1], c[2], c[3] }
end

local function pushHistory(wp, placeId)
    local hist = Database.__meta.HISTORY
    table.insert(hist, 1, {
        NAME    = wp.NAME,
        COORD   = cloneCoord(wp.COORD),
        PLACEID = tostring(placeId or CurrentPlaceId),
        TIME    = os.time(),
    })
    while #hist > MAX_HISTORY do
        table.remove(hist)
    end
end

local function setLastPosition(coord, placeId)
    Database.__meta.LAST_POSITION = {
        NAME    = "Last Position",
        COORD   = cloneCoord(coord),
        PLACEID = tostring(placeId or CurrentPlaceId),
        TIME    = os.time(),
    }
end

-- Cache current place name
do
    local n = getPlaceName()
    if n then
        Database.__meta.PLACE_NAMES[CurrentPlaceId] = n
    end
end

--============================================================
-- CLEANUP OLD GUIs
--============================================================
for _, obj in ipairs(PlayerGui:GetChildren()) do
    if obj.Name == GUI_NAME or obj.Name == "MyWaypointGUI" or obj.Name == "CreditNotify" then
        pcall(function() obj:Destroy() end)
    end
end

--============================================================
-- UTILITY
--============================================================
local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 10)
    c.Parent = obj
    return c
end

local function stroke(obj, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.BORDER
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

--============================================================
-- LAYOUT CONSTANTS
--============================================================
local L = {
    PAD       = 12,
    HEADER_H  = 68,
    SEARCH_H  = 42,
    MAP_H     = 48,
    FILTER_H  = 36,
    SAVE_H    = 52,
    NAV_H     = 40,
    CREDIT_H  = 14,
    GAP       = 8,
    GAP_S     = 6,
}

local function computeWindowSize()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(360, 800)
    local w = math.clamp(vp.X * 0.92, 320, 420)
    local h = math.clamp(vp.Y * 0.72, 420, 620)
    return UDim2.new(0, w, 0, h)
end

--============================================================
-- SCREEN GUI
--============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

--============================================================
-- MAIN WINDOW
--============================================================
local Window = Instance.new("Frame")
Window.Name = "Window"
Window.BackgroundColor3 = Theme.BG
Window.BackgroundTransparency = Theme.TR_WINDOW
Window.BorderSizePixel = 0
Window.AnchorPoint = Vector2.new(0.5, 0.5)
Window.Position = UDim2.new(0.5, 0, 0.5, 0)
Window.Size = UDim2.new(0, 0, 0, 0)
Window.ClipsDescendants = true
Window.Visible = false
Window.Parent = ScreenGui
round(Window, 14)
stroke(Window, Theme.BORDER, 1, 0.15)

--============================================================
-- HEADER
--============================================================
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.BackgroundColor3 = Theme.PANEL
Header.BackgroundTransparency = Theme.TR_PANEL
Header.BorderSizePixel = 0
Header.Size = UDim2.new(1, 0, 0, L.HEADER_H)
Header.Parent = Window
round(Header, 14)

local headerMask = Instance.new("Frame")
headerMask.BackgroundColor3 = Theme.PANEL
headerMask.BackgroundTransparency = Theme.TR_PANEL
headerMask.BorderSizePixel = 0
headerMask.Position = UDim2.new(0, 0, 0.5, 0)
headerMask.Size = UDim2.new(1, 0, 0.5, 0)
headerMask.ZIndex = 1
headerMask.Parent = Header

local headerSep = Instance.new("Frame")
headerSep.BackgroundColor3 = Theme.BORDER
headerSep.BackgroundTransparency = 0.5
headerSep.BorderSizePixel = 0
headerSep.Position = UDim2.new(0, 0, 1, -1)
headerSep.Size = UDim2.new(1, 0, 0, 1)
headerSep.ZIndex = 2
headerSep.Parent = Header

local TitleLabel = Instance.new("TextLabel")
TitleLabel.BackgroundTransparency = 1
TitleLabel.Position = UDim2.new(0, 16, 0, 6)
TitleLabel.Size = UDim2.new(1, -120, 0, 24)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "MYWAYPOINTS"
TitleLabel.TextColor3 = Theme.TEXT
TitleLabel.TextSize = 20
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 3
TitleLabel.Parent = Header

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Position = UDim2.new(0, 16, 0, 30)
SubtitleLabel.Size = UDim2.new(1, -120, 0, 17)
SubtitleLabel.Font = Enum.Font.Gotham
SubtitleLabel.Text = "Universal Waypoint Manager  •  " .. VERSION_TEXT
SubtitleLabel.TextColor3 = Theme.TEXT_DIM
SubtitleLabel.TextSize = 13
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.ZIndex = 3
SubtitleLabel.Parent = Header

local SaveStatus = Instance.new("TextLabel")
SaveStatus.BackgroundTransparency = 1
SaveStatus.Position = UDim2.new(0, 16, 0, 48)
SaveStatus.Size = UDim2.new(1, -120, 0, 15)
SaveStatus.Font = Enum.Font.Gotham
SaveStatus.Text = FS_AVAILABLE and "Auto-save ON" or "Local persistence unavailable"
SaveStatus.TextColor3 = Theme.TEXT_MUTE
SaveStatus.TextSize = 12
SaveStatus.TextXAlignment = Enum.TextXAlignment.Left
SaveStatus.ZIndex = 3
SaveStatus.Parent = Header
saveStatusLabel = SaveStatus

local function makeHeaderButton(text, xOffset)
    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = Theme.PANEL_ALT
    btn.BackgroundTransparency = 0.1
    btn.BorderSizePixel = 0
    btn.Position = UDim2.new(1, xOffset, 0, 15)
    btn.Size = UDim2.new(0, 38, 0, 38)
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 20
    btn.TextColor3 = Theme.TEXT
    btn.ZIndex = 4
    btn.Parent = Header
    round(btn, 11)
    stroke(btn, Theme.BORDER_LO, 1, 0.3)
    return btn
end

local CloseBtn    = makeHeaderButton("×", -50)
local MinimizeBtn = makeHeaderButton("–", -94)

--============================================================
-- SEARCH BAR
--============================================================
local SearchContainer = Instance.new("Frame")
SearchContainer.BackgroundColor3 = Theme.PANEL
SearchContainer.BackgroundTransparency = Theme.TR_PANEL
SearchContainer.BorderSizePixel = 0
SearchContainer.Position = UDim2.new(0, L.PAD, 0, L.HEADER_H + L.GAP)
SearchContainer.Size = UDim2.new(1, -L.PAD * 2, 0, L.SEARCH_H)
SearchContainer.Parent = Window
round(SearchContainer, 10)
stroke(SearchContainer, Theme.BORDER_LO, 1, 0.35)

local SearchIcon = Instance.new("TextLabel")
SearchIcon.BackgroundTransparency = 1
SearchIcon.Position = UDim2.new(0, 12, 0, 0)
SearchIcon.Size = UDim2.new(0, 24, 1, 0)
SearchIcon.Font = Enum.Font.Gotham
SearchIcon.Text = "🔎"
SearchIcon.TextColor3 = Theme.TEXT_MUTE
SearchIcon.TextSize = 15
SearchIcon.Parent = SearchContainer

local SearchBox = Instance.new("TextBox")
SearchBox.BackgroundTransparency = 1
SearchBox.Position = UDim2.new(0, 40, 0, 0)
SearchBox.Size = UDim2.new(1, -50, 1, 0)
SearchBox.Font = Enum.Font.Gotham
SearchBox.Text = ""
SearchBox.PlaceholderText = "Search waypoint..."
SearchBox.PlaceholderColor3 = Theme.TEXT_MUTE
SearchBox.TextColor3 = Theme.TEXT
SearchBox.TextSize = 15
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = SearchContainer

--============================================================
-- CURRENT MAP INFO
--============================================================
local MapInfo = Instance.new("Frame")
MapInfo.BackgroundColor3 = Theme.PANEL
MapInfo.BackgroundTransparency = Theme.TR_PANEL
MapInfo.BorderSizePixel = 0
MapInfo.Position = UDim2.new(0, L.PAD, 0, L.HEADER_H + L.GAP + L.SEARCH_H + L.GAP_S)
MapInfo.Size = UDim2.new(1, -L.PAD * 2, 0, L.MAP_H)
MapInfo.Parent = Window
round(MapInfo, 10)
stroke(MapInfo, Theme.BORDER_LO, 1, 0.35)

local MapInfoLabel = Instance.new("TextLabel")
MapInfoLabel.BackgroundTransparency = 1
MapInfoLabel.Position = UDim2.new(0, 14, 0, 5)
MapInfoLabel.Size = UDim2.new(1, -28, 0, 15)
MapInfoLabel.Font = Enum.Font.GothamBold
MapInfoLabel.Text = "CURRENT MAP"
MapInfoLabel.TextColor3 = Theme.TEXT_MUTE
MapInfoLabel.TextSize = 11
MapInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
MapInfoLabel.Parent = MapInfo

local MapNameLabel = Instance.new("TextLabel")
MapNameLabel.BackgroundTransparency = 1
MapNameLabel.Position = UDim2.new(0, 14, 0, 24)
MapNameLabel.Size = UDim2.new(1, -28, 0, 18)
MapNameLabel.Font = Enum.Font.Gotham
MapNameLabel.Text = currentPlaceLabel() .. "  •  0 waypoints"
MapNameLabel.TextColor3 = Theme.TEXT
MapNameLabel.TextSize = 13
MapNameLabel.TextXAlignment = Enum.TextXAlignment.Left
MapNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
MapNameLabel.Parent = MapInfo

--============================================================
-- FILTER ROW (horizontal scroll)
--============================================================
local filterRowY = L.HEADER_H + L.GAP + L.SEARCH_H + L.GAP_S + L.MAP_H + L.GAP_S

local FilterRow = Instance.new("Frame")
FilterRow.BackgroundTransparency = 1
FilterRow.Position = UDim2.new(0, L.PAD, 0, filterRowY)
FilterRow.Size = UDim2.new(1, -L.PAD * 2, 0, L.FILTER_H)
FilterRow.Parent = Window

local FilterScroll = Instance.new("ScrollingFrame")
FilterScroll.BackgroundTransparency = 1
FilterScroll.BorderSizePixel = 0
FilterScroll.Position = UDim2.new(0, 0, 0, 0)
FilterScroll.Size = UDim2.new(1, 0, 1, 0)
FilterScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
FilterScroll.ScrollBarThickness = 0
FilterScroll.ScrollingDirection = Enum.ScrollingDirection.X
FilterScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
FilterScroll.Parent = FilterRow

local FILTER_LABELS = { "ALL", "FAVORITES", "NEWEST", "NAME", "DISTANCE" }
local FILTER_BTN_W = 92
local FILTER_GAP = 6
local filterButtons = {}
local currentFilter = "ALL"

local totalFilterWidth = (#FILTER_LABELS * FILTER_BTN_W) + ((#FILTER_LABELS - 1) * FILTER_GAP)
FilterScroll.CanvasSize = UDim2.new(0, totalFilterWidth, 0, 0)

local function refreshFilterButtons()
    for name, btn in pairs(filterButtons) do
        local active = (name == currentFilter)
        if active then
            btn.BackgroundColor3 = Theme.ACTIVE
            btn.BackgroundTransparency = 0
            btn.TextColor3 = Theme.TEXT
        else
            btn.BackgroundColor3 = Theme.INACTIVE
            btn.BackgroundTransparency = 0.2
            btn.TextColor3 = Theme.TEXT_MUTE
        end
    end
end

for i, name in ipairs(FILTER_LABELS) do
    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = Theme.INACTIVE
    btn.BackgroundTransparency = 0.2
    btn.BorderSizePixel = 0
    btn.Position = UDim2.new(0, (i - 1) * (FILTER_BTN_W + FILTER_GAP), 0, 0)
    btn.Size = UDim2.new(0, FILTER_BTN_W, 1, 0)
    btn.Font = Enum.Font.GothamBold
    btn.Text = name
    btn.TextColor3 = Theme.TEXT_MUTE
    btn.TextSize = 12
    btn.TextTruncate = Enum.TextTruncate.AtEnd
    btn.Parent = FilterScroll
    round(btn, 8)
    btn.MouseButton1Click:Connect(function()
        currentFilter = name
        refreshFilterButtons()
        renderWaypoints()
    end)
    filterButtons[name] = btn
end

--============================================================
-- FORWARD DECLARATIONS
--============================================================
local renderWaypoints
local teleportToWaypoint
local promptRename
local openMenuForWaypoint
local makeWaypointCard

--============================================================
-- WAYPOINT SCROLL FRAME
--============================================================
local listY = filterRowY + L.FILTER_H + L.GAP_S
local bottomReserved = L.SAVE_H + L.GAP_S + L.NAV_H + 4 + L.CREDIT_H + L.PAD

local ListFrame = Instance.new("ScrollingFrame")
ListFrame.Name = "WaypointList"
ListFrame.BackgroundTransparency = 1
ListFrame.BorderSizePixel = 0
ListFrame.Position = UDim2.new(0, L.PAD, 0, listY)
ListFrame.Size = UDim2.new(1, -L.PAD * 2, 1, -(listY + bottomReserved))
ListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ListFrame.ScrollBarThickness = 5
ListFrame.ScrollBarImageColor3 = Theme.BORDER
ListFrame.ScrollBarImageTransparency = 0.35
ListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
ListFrame.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
ListFrame.Parent = Window

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 8)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = ListFrame

local ListPadding = Instance.new("UIPadding")
ListPadding.PaddingTop = UDim.new(0, 2)
ListPadding.PaddingBottom = UDim.new(0, 8)
ListPadding.PaddingRight = UDim.new(0, 4)
ListPadding.Parent = ListFrame

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ListFrame.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
end)

-- Empty state (child of Window so it doesn't affect ListLayout)
local EmptyLabel = Instance.new("TextLabel")
EmptyLabel.Name = "EmptyState"
EmptyLabel.BackgroundTransparency = 1
EmptyLabel.Position = UDim2.new(0, 0, 0, listY + 40)
EmptyLabel.Size = UDim2.new(1, 0, 0, 70)
EmptyLabel.Font = Enum.Font.Gotham
EmptyLabel.Text = "No waypoints yet."
EmptyLabel.TextColor3 = Theme.TEXT_MUTE
EmptyLabel.TextSize = 14
EmptyLabel.TextWrapped = true
EmptyLabel.Visible = false
EmptyLabel.ZIndex = 6
EmptyLabel.Parent = Window

--============================================================
-- SAVE POSITION BUTTON
--============================================================
local SaveBtn = Instance.new("TextButton")
SaveBtn.BackgroundColor3 = Theme.ACTION
SaveBtn.BorderSizePixel = 0
SaveBtn.Position = UDim2.new(0, L.PAD, 1, -(L.SAVE_H + L.GAP_S + L.NAV_H + 4 + L.CREDIT_H))
SaveBtn.Size = UDim2.new(1, -L.PAD * 2, 0, L.SAVE_H)
SaveBtn.Font = Enum.Font.GothamBold
SaveBtn.Text = "＋  SAVE POSITION"
SaveBtn.TextColor3 = Theme.TEXT
SaveBtn.TextSize = 15
SaveBtn.Parent = Window
round(SaveBtn, 11)
stroke(SaveBtn, Theme.ACTIVE_BRD, 1, 0.5)

--============================================================
-- BOTTOM NAV
--============================================================
local navY = -(L.NAV_H + 4 + L.CREDIT_H)

local TabRow = Instance.new("Frame")
TabRow.BackgroundTransparency = 1
TabRow.Position = UDim2.new(0, L.PAD, 1, navY)
TabRow.Size = UDim2.new(1, -L.PAD * 2, 0, L.NAV_H)
TabRow.Parent = Window

local tabButtons = {}
local function makeTab(name, index, total)
    local w = 1 / total
    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = Theme.PANEL_ALT
    btn.BackgroundTransparency = 0.25
    btn.BorderSizePixel = 0
    btn.Position = UDim2.new(w * (index - 1), 0, 0, 0)
    btn.Size = UDim2.new(w, -4, 1, 0)
    btn.Font = Enum.Font.GothamBold
    btn.Text = name
    btn.TextColor3 = Theme.TEXT_DIM
    btn.TextSize = 13
    btn.Parent = TabRow
    round(btn, 8)
    stroke(btn, Theme.BORDER_LO, 1, 0.5)
    tabButtons[name] = btn
    return btn
end
makeTab("MAPS",      1, 4)
makeTab("FAVORITES", 2, 4)
makeTab("MORE",      3, 4)
makeTab("BACK",      4, 4)

--============================================================
-- CREDIT
--============================================================
local Credit = Instance.new("TextLabel")
Credit.BackgroundTransparency = 1
Credit.Position = UDim2.new(0, L.PAD, 1, -(L.CREDIT_H + 2))
Credit.Size = UDim2.new(1, -L.PAD * 2, 0, L.CREDIT_H)
Credit.Font = Enum.Font.Gotham
Credit.Text = CREDIT_TEXT
Credit.TextColor3 = Theme.TEXT_MUTE
Credit.TextSize = 11
Credit.TextXAlignment = Enum.TextXAlignment.Center
Credit.Parent = Window

--============================================================
-- FLOATING BUTTON (circular, right side default)
--============================================================
local FloatingBtn = Instance.new("TextButton")
FloatingBtn.Name = "FloatingBtn"
FloatingBtn.BackgroundColor3 = Theme.TOGGLE
FloatingBtn.BackgroundTransparency = 0.1
FloatingBtn.BorderSizePixel = 0
FloatingBtn.AnchorPoint = Vector2.new(0.5, 0.5)
FloatingBtn.Size = UDim2.new(0, FLOATING_SIZE, 0, FLOATING_SIZE)
FloatingBtn.Position = UDim2.new(1, -(FLOATING_SIZE/2 + 16), 0.4, 0)
FloatingBtn.Font = Enum.Font.GothamBold
FloatingBtn.Text = "MW"
FloatingBtn.TextColor3 = Theme.TEXT
FloatingBtn.TextSize = 16
FloatingBtn.Visible = false
FloatingBtn.AutoButtonColor = false
FloatingBtn.Parent = ScreenGui
round(FloatingBtn, FLOATING_SIZE / 2)
stroke(FloatingBtn, Theme.ACTIVE_BRD, 1.5, 0.3)

--============================================================
-- NOTIFICATION
--============================================================
local Notify = Instance.new("Frame")
Notify.BackgroundColor3 = Theme.PANEL
Notify.BackgroundTransparency = 0.1
Notify.BorderSizePixel = 0
Notify.Position = UDim2.new(0.5, -110, 0, -60)
Notify.Size = UDim2.new(0, 220, 0, 40)
Notify.Parent = ScreenGui
round(Notify, 10)
stroke(Notify, Theme.BORDER, 1, 0.3)

local NotifyLabel = Instance.new("TextLabel")
NotifyLabel.BackgroundTransparency = 1
NotifyLabel.Size = UDim2.new(1, -20, 1, 0)
NotifyLabel.Position = UDim2.new(0, 10, 0, 0)
NotifyLabel.Font = Enum.Font.Gotham
NotifyLabel.Text = ""
NotifyLabel.TextColor3 = Theme.TEXT
NotifyLabel.TextSize = 13
NotifyLabel.TextWrapped = true
NotifyLabel.Parent = Notify

local notifyToken = 0
local function showNotify(text, color)
    notifyToken += 1
    local my = notifyToken
    NotifyLabel.Text = text
    NotifyLabel.TextColor3 = color or Theme.TEXT
    TweenService:Create(Notify, TweenInfo.new(0.22), {
        Position = UDim2.new(0.5, -110, 0, 20)
    }):Play()
    task.delay(2.0, function()
        if my ~= notifyToken then return end
        TweenService:Create(Notify, TweenInfo.new(0.22), {
            Position = UDim2.new(0.5, -110, 0, -60)
        }):Play()
    end)
end

--============================================================
-- DRAG SYSTEM (threshold-aware, tap-safe, single-touch safe)
--============================================================
local function attachDrag(frame, handle, onClick, ignoreChildren)
    local dragging     = false
    local moved        = false
    local dragStart    = nil
    local startPos     = nil
    local activeInput  = nil

    handle.InputBegan:Connect(function(input)
        if dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        -- If tap started on one of the ignore children (buttons), skip drag
        if ignoreChildren then
            local pos = input.Position
            for _, child in ipairs(ignoreChildren) do
                if child and child.Parent then
                    local ap, as = child.AbsolutePosition, child.AbsoluteSize
                    if pos.X >= ap.X and pos.X <= ap.X + as.X
                    and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y then
                        return
                    end
                end
            end
        end
        dragging    = true
        moved       = false
        dragStart   = input.Position
        startPos    = frame.Position
        activeInput = input
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = input.Position - dragStart
        if not moved and delta.Magnitude >= DRAG_THRESHOLD then
            moved = true
        end
        if moved then
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not activeInput then return end
        if input.UserInputType ~= activeInput.UserInputType then return end
        if dragging and not moved and onClick then
            onClick()
        end
        dragging    = false
        moved       = false
        activeInput = nil
    end)
end

--============================================================
-- MINIMIZE / CLOSE
--============================================================
local function showFloatingButton()
    FloatingBtn.Visible = true
    FloatingBtn.BackgroundTransparency = 1
    FloatingBtn.TextTransparency = 1
    TweenService:Create(FloatingBtn, TweenInfo.new(0.18), {
        BackgroundTransparency = 0.1,
        TextTransparency = 0,
    }):Play()
end

local function hideFloatingButton(callback)
    local t = TweenService:Create(FloatingBtn, TweenInfo.new(0.15), {
        BackgroundTransparency = 1,
        TextTransparency = 1,
    })
    t:Play()
    t.Completed:Connect(function()
        FloatingBtn.Visible = false
        FloatingBtn.BackgroundTransparency = 0.1
        FloatingBtn.TextTransparency = 0
        if callback then callback() end
    end)
end

local function animateShrinkAndHide(afterHidden)
    local t = TweenService:Create(Window, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 0, 0, 0),
    })
    t:Play()
    t.Completed:Connect(function()
        Window.Visible = false
        -- NOTE: intentionally do NOT reset Window.Position — it persists.
        if afterHidden then afterHidden() end
    end)
end

local function minimizeWindow()
    if not Window.Visible then return end
    animateShrinkAndHide(function()
        showFloatingButton()
    end)
end

local function closeUI()
    -- Distinct from minimize: fully closes the UI (hides floating button too).
    -- Database is untouched; re-executing the script re-opens the UI.
    writeDatabaseNow()
    if Window.Visible then
        animateShrinkAndHide(function()
            FloatingBtn.Visible = false
        end)
    else
        FloatingBtn.Visible = false
    end
    print("[MyWaypoints v2.1] UI closed. Re-execute the script to reopen.")
end

local function openWindow()
    local target = computeWindowSize()
    Window.Size = UDim2.new(0, 0, 0, 0)
    Window.Visible = true
    TweenService:Create(Window, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = target,
    }):Play()
    if FloatingBtn.Visible then
        hideFloatingButton()
    end
end

MinimizeBtn.MouseButton1Click:Connect(minimizeWindow)
CloseBtn.MouseButton1Click:Connect(closeUI)

-- Attach drag: Window (header) — ignore header buttons
attachDrag(Window, Header, nil, { CloseBtn, MinimizeBtn })

-- Attach drag: FloatingBtn — tap opens window, drag moves
attachDrag(FloatingBtn, FloatingBtn, function()
    openWindow()
end)

--============================================================
-- WAYPOINT CARD METADATA
--============================================================
local renderedCards = {}
local cardInfo = {}  -- [card] = { wp = wp, distLbl = distLbl }

local function clearList()
    for _, c in ipairs(renderedCards) do
        cardInfo[c] = nil
        c:Destroy()
    end
    renderedCards = {}
end

--============================================================
-- CONTEXT MENU
--============================================================
openMenuForWaypoint = function(wp, anchorBtn)
    local existing = Window:FindFirstChild("ContextMenu")
    if existing then existing:Destroy() end

    local menu = Instance.new("Frame")
    menu.Name = "ContextMenu"
    menu.BackgroundColor3 = Theme.PANEL_ALT
    menu.BackgroundTransparency = 0.05
    menu.BorderSizePixel = 0
    menu.Size = UDim2.new(0, 200, 0, 178)
    menu.ZIndex = 20
    menu.Parent = Window
    round(menu, 10)
    stroke(menu, Theme.BORDER, 1, 0.3)

    local items = {
        { text = "Rename", action = function() promptRename(wp) end },
        { text = (wp.FAVORITE and "★ Unfavorite" or "☆ Favorite"), action = function()
            wp.FAVORITE = not wp.FAVORITE
            saveDatabase()
            renderWaypoints()
            showNotify(wp.FAVORITE and "Added to favorites" or "Removed from favorites", Theme.FAV)
        end },
        { text = "Copy Coordinates", action = function()
            local str = string.format("X: %d\nY: %d\nZ: %d", wp.COORD[1], wp.COORD[2], wp.COORD[3])
            local ok = false
            if type(setclipboard) == "function" then
                ok = pcall(setclipboard, str)
            end
            if ok then
                showNotify("Coordinates copied", Theme.GOOD)
            else
                showNotify("Clipboard unavailable", Theme.WARN)
            end
        end },
        { text = "Delete", action = function()
            local list = getCurrentWaypoints()
            for i, w in ipairs(list) do
                if w == wp then table.remove(list, i) break end
            end
            saveDatabase()
            renderWaypoints()
            showNotify("Waypoint deleted", Theme.DANGER)
        end, danger = true },
    }

    local y = 6
    for _, item in ipairs(items) do
        local btn = Instance.new("TextButton")
        btn.BackgroundColor3 = Theme.PANEL
        btn.BackgroundTransparency = 0.3
        btn.BorderSizePixel = 0
        btn.Position = UDim2.new(0, 6, 0, y)
        btn.Size = UDim2.new(1, -12, 0, 38)
        btn.Font = Enum.Font.Gotham
        btn.Text = item.text
        btn.TextColor3 = item.danger and Theme.DANGER or Theme.TEXT
        btn.TextSize = 13
        btn.ZIndex = 21
        btn.Parent = menu
        round(btn, 6)
        btn.MouseButton1Click:Connect(function()
            menu:Destroy()
            item.action()
        end)
        y += 42
    end

    local anchorAbs = anchorBtn.AbsolutePosition
    local winAbs    = Window.AbsolutePosition
    local winSz     = Window.AbsoluteSize
    menu.Position = UDim2.new(
        0,
        math.clamp(anchorAbs.X - winAbs.X - 150, 8, winSz.X - 210),
        0,
        math.clamp(anchorAbs.Y - winAbs.Y + 42, 8, winSz.Y - 194)
    )

    local conn
    conn = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            task.wait(0.1)
            if menu and menu.Parent then
                local pos = input.Position
                local abs = menu.AbsolutePosition
                local sz  = menu.AbsoluteSize
                local inside = pos.X >= abs.X and pos.X <= abs.X + sz.X
                           and pos.Y >= abs.Y and pos.Y <= abs.Y + sz.Y
                if not inside then
                    menu:Destroy()
                    conn:Disconnect()
                end
            end
        end
    end)
end

--============================================================
-- RENAME PROMPT
--============================================================
promptRename = function(wp)
    local overlay = Instance.new("Frame")
    overlay.BackgroundColor3 = Theme.BG
    overlay.BackgroundTransparency = 0.02
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.new(0, 280, 0, 132)
    overlay.Position = UDim2.new(0.5, -140, 0.5, -66)
    overlay.ZIndex = 30
    overlay.Parent = Window
    round(overlay, 12)
    stroke(overlay, Theme.BORDER, 1, 0.2)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 16, 0, 10)
    lbl.Size = UDim2.new(1, -32, 0, 22)
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = "Rename Waypoint"
    lbl.TextColor3 = Theme.TEXT
    lbl.TextSize = 15
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 31
    lbl.Parent = overlay

    local box = Instance.new("TextBox")
    box.BackgroundColor3 = Theme.PANEL
    box.BorderSizePixel = 0
    box.Position = UDim2.new(0, 16, 0, 38)
    box.Size = UDim2.new(1, -32, 0, 36)
    box.Font = Enum.Font.Gotham
    box.Text = wp.NAME
    box.TextColor3 = Theme.TEXT
    box.TextSize = 14
    box.ZIndex = 31
    box.ClearTextOnFocus = false
    box.Parent = overlay
    round(box, 8)
    stroke(box, Theme.BORDER_LO, 1, 0.3)

    local okBtn = Instance.new("TextButton")
    okBtn.BackgroundColor3 = Theme.ACTION
    okBtn.BorderSizePixel = 0
    okBtn.Position = UDim2.new(0, 16, 0, 84)
    okBtn.Size = UDim2.new(0.5, -20, 0, 36)
    okBtn.Font = Enum.Font.GothamBold
    okBtn.Text = "Save"
    okBtn.TextColor3 = Theme.TEXT
    okBtn.TextSize = 14
    okBtn.ZIndex = 31
    okBtn.Parent = overlay
    round(okBtn, 8)
    stroke(okBtn, Theme.ACTIVE_BRD, 1, 0.5)

    local cancelBtn = Instance.new("TextButton")
    cancelBtn.BackgroundColor3 = Theme.PANEL_ALT
    cancelBtn.BackgroundTransparency = 0.2
    cancelBtn.BorderSizePixel = 0
    cancelBtn.Position = UDim2.new(0.5, 4, 0, 84)
    cancelBtn.Size = UDim2.new(0.5, -20, 0, 36)
    cancelBtn.Font = Enum.Font.Gotham
    cancelBtn.Text = "Cancel"
    cancelBtn.TextColor3 = Theme.TEXT_DIM
    cancelBtn.TextSize = 14
    cancelBtn.ZIndex = 31
    cancelBtn.Parent = overlay
    round(cancelBtn, 8)

    okBtn.MouseButton1Click:Connect(function()
        local newName = box.Text
        if newName and #newName > 0 then
            wp.NAME = newName
            saveDatabase()
            renderWaypoints()
            showNotify("Renamed", Theme.GOOD)
        end
        overlay:Destroy()
    end)
    cancelBtn.MouseButton1Click:Connect(function()
        overlay:Destroy()
    end)
end

--============================================================
-- TELEPORT
--============================================================
teleportToWaypoint = function(wp)
    local root = getCharacterRoot()
    if not root then
        showNotify("Character not ready", Theme.WARN)
        return
    end
    setLastPosition({ root.Position.X, root.Position.Y, root.Position.Z }, CurrentPlaceId)
    pushHistory(wp, wp.PLACEID or CurrentPlaceId)
    saveDatabase()
    root.CFrame = CFrame.new(wp.COORD[1], wp.COORD[2], wp.COORD[3])
    showNotify("Teleported to " .. wp.NAME, Theme.ACTION)
end

--============================================================
-- CARD BUILDER
--============================================================
makeWaypointCard = function(wp)
    local card = Instance.new("Frame")
    card.BackgroundColor3 = Theme.CARD
    card.BackgroundTransparency = Theme.TR_CARD
    card.BorderSizePixel = 0
    card.Size = UDim2.new(1, -4, 0, 64)
    card.Parent = ListFrame
    round(card, 10)
    stroke(card, Theme.BORDER_LO, 1, 0.4)

    local favBtn = Instance.new("TextButton")
    favBtn.BackgroundTransparency = 1
    favBtn.Position = UDim2.new(0, 8, 0, 16)
    favBtn.Size = UDim2.new(0, 34, 0, 34)
    favBtn.Font = Enum.Font.GothamBold
    favBtn.Text = wp.FAVORITE and "★" or "☆"
    favBtn.TextColor3 = wp.FAVORITE and Theme.FAV or Theme.TEXT_MUTE
    favBtn.TextSize = 22
    favBtn.Parent = card
    favBtn.MouseButton1Click:Connect(function()
        wp.FAVORITE = not wp.FAVORITE
        favBtn.Text = wp.FAVORITE and "★" or "☆"
        favBtn.TextColor3 = wp.FAVORITE and Theme.FAV or Theme.TEXT_MUTE
        saveDatabase()
        -- Re-render to apply filter (FAVORITES may hide/show)
        task.delay(0.15, renderWaypoints)
    end)

    local nameLbl = Instance.new("TextLabel")
    nameLbl.BackgroundTransparency = 1
    nameLbl.Position = UDim2.new(0, 48, 0, 8)
    nameLbl.Size = UDim2.new(1, -166, 0, 22)
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.Text = wp.NAME
    nameLbl.TextColor3 = Theme.TEXT
    nameLbl.TextSize = 15
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.Parent = card

    local distLbl = Instance.new("TextLabel")
    distLbl.BackgroundTransparency = 1
    distLbl.Position = UDim2.new(0, 48, 0, 32)
    distLbl.Size = UDim2.new(1, -166, 0, 20)
    distLbl.Font = Enum.Font.Gotham
    distLbl.Text = "-- studs"
    distLbl.TextColor3 = Theme.TEXT_MUTE
    distLbl.TextSize = 13
    distLbl.TextXAlignment = Enum.TextXAlignment.Left
    distLbl.Parent = card

    local tpBtn = Instance.new("TextButton")
    tpBtn.BackgroundColor3 = Theme.ACTION_TP
    tpBtn.BorderSizePixel = 0
    tpBtn.Position = UDim2.new(1, -106, 0, 15)
    tpBtn.Size = UDim2.new(0, 62, 0, 34)
    tpBtn.Font = Enum.Font.GothamBold
    tpBtn.Text = "TP"
    tpBtn.TextColor3 = Color3.fromRGB(220, 228, 240)
    tpBtn.TextSize = 14
    tpBtn.Parent = card
    round(tpBtn, 8)
    stroke(tpBtn, Theme.ACTIVE_BRD, 1, 0.5)

    local menuBtn = Instance.new("TextButton")
    menuBtn.BackgroundColor3 = Theme.PANEL_ALT
    menuBtn.BackgroundTransparency = 0.3
    menuBtn.BorderSizePixel = 0
    menuBtn.Position = UDim2.new(1, -40, 0, 15)
    menuBtn.Size = UDim2.new(0, 34, 0, 34)
    menuBtn.Font = Enum.Font.GothamBold
    menuBtn.Text = "⋮"
    menuBtn.TextColor3 = Theme.TEXT_DIM
    menuBtn.TextSize = 18
    menuBtn.Parent = card
    round(menuBtn, 8)

    tpBtn.MouseButton1Click:Connect(function()
        teleportToWaypoint(wp)
    end)

    menuBtn.MouseButton1Click:Connect(function()
        openMenuForWaypoint(wp, menuBtn)
    end)

    cardInfo[card] = { wp = wp, distLbl = distLbl }
    renderedCards[#renderedCards + 1] = card
    return card
end

--============================================================
-- RENDER (filter + search + sort)
--============================================================
renderWaypoints = function()
    clearList()

    local list  = getCurrentWaypoints()
    local query = SearchBox.Text:lower()

    -- Step 1: FILTER
    local filtered = {}
    if currentFilter == "FAVORITES" then
        for _, wp in ipairs(list) do
            if wp.FAVORITE then
                table.insert(filtered, wp)
            end
        end
    else
        for _, wp in ipairs(list) do
            table.insert(filtered, wp)
        end
    end

    -- Step 2: SEARCH (case-insensitive, on top of filter)
    if query ~= "" then
        local searched = {}
        for _, wp in ipairs(filtered) do
            if wp.NAME:lower():find(query, 1, true) then
                table.insert(searched, wp)
            end
        end
        filtered = searched
    end

    -- Step 3: SORT
    if currentFilter == "NAME" then
        table.sort(filtered, function(a, b)
            return a.NAME:lower() < b.NAME:lower()
        end)
    elseif currentFilter == "DISTANCE" then
        table.sort(filtered, function(a, b)
            local da = waypointDistance(a) or math.huge
            local db = waypointDistance(b) or math.huge
            return da < db
        end)
    elseif currentFilter == "FAVORITES" then
        table.sort(filtered, function(a, b)
            return (a.CREATED or 0) > (b.CREATED or 0)
        end)
    else
        -- ALL / NEWEST → newest first
        table.sort(filtered, function(a, b)
            return (a.CREATED or 0) > (b.CREATED or 0)
        end)
    end

    -- Render cards
    for _, wp in ipairs(filtered) do
        makeWaypointCard(wp)
    end

    -- Empty state
    local emptyText
    if #list == 0 then
        emptyText = "No waypoints yet.\nTap + SAVE POSITION to add one."
    elseif currentFilter == "FAVORITES" and #filtered == 0 and query == "" then
        emptyText = "No favorite waypoints yet."
    elseif query ~= "" and #filtered == 0 then
        emptyText = "No matching waypoints."
    end

    if emptyText then
        EmptyLabel.Text = emptyText
        EmptyLabel.Visible = true
    else
        EmptyLabel.Visible = false
    end

    -- Map info
    local total = #list
    MapNameLabel.Text = currentPlaceLabel() .. "  •  " .. total .. " waypoint" .. (total == 1 and "" or "s")

    refreshFilterButtons()
end

--============================================================
-- DISTANCE UPDATER (throttled)
--============================================================
local distanceAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
    if not Window.Visible then return end
    distanceAccumulator += dt
    if distanceAccumulator < DISTANCE_INTERVAL then return end
    distanceAccumulator = 0

    for card, info in pairs(cardInfo) do
        if card.Parent and info.distLbl and info.distLbl.Parent then
            local d = waypointDistance(info.wp)
            info.distLbl.Text = d and (tostring(d) .. " studs") or "-- studs"
        end
    end
end)

--============================================================
-- SAVE POSITION FLOW
--============================================================
local function promptSavePosition()
    local root = getCharacterRoot()
    if not root then
        showNotify("Character not loaded", Theme.WARN)
        return
    end

    local overlay = Instance.new("Frame")
    overlay.BackgroundColor3 = Theme.BG
    overlay.BackgroundTransparency = 0.02
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.new(0, 290, 0, 138)
    overlay.Position = UDim2.new(0.5, -145, 0.5, -69)
    overlay.ZIndex = 30
    overlay.Parent = Window
    round(overlay, 12)
    stroke(overlay, Theme.BORDER, 1, 0.2)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 16, 0, 10)
    lbl.Size = UDim2.new(1, -32, 0, 22)
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = "Save Waypoint"
    lbl.TextColor3 = Theme.TEXT
    lbl.TextSize = 15
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 31
    lbl.Parent = overlay

    local box = Instance.new("TextBox")
    box.BackgroundColor3 = Theme.PANEL
    box.BorderSizePixel = 0
    box.Position = UDim2.new(0, 16, 0, 38)
    box.Size = UDim2.new(1, -32, 0, 36)
    box.Font = Enum.Font.Gotham
    box.Text = ""
    box.PlaceholderText = "Waypoint name"
    box.PlaceholderColor3 = Theme.TEXT_MUTE
    box.TextColor3 = Theme.TEXT
    box.TextSize = 14
    box.ClearTextOnFocus = false
    box.ZIndex = 31
    box.Parent = overlay
    round(box, 8)
    stroke(box, Theme.BORDER_LO, 1, 0.3)

    local okBtn = Instance.new("TextButton")
    okBtn.BackgroundColor3 = Theme.ACTION
    okBtn.BorderSizePixel = 0
    okBtn.Position = UDim2.new(0, 16, 0, 86)
    okBtn.Size = UDim2.new(0.5, -20, 0, 36)
    okBtn.Font = Enum.Font.GothamBold
    okBtn.Text = "Save"
    okBtn.TextColor3 = Theme.TEXT
    okBtn.TextSize = 14
    okBtn.ZIndex = 31
    okBtn.Parent = overlay
    round(okBtn, 8)
    stroke(okBtn, Theme.ACTIVE_BRD, 1, 0.5)

    local cancelBtn = Instance.new("TextButton")
    cancelBtn.BackgroundColor3 = Theme.PANEL_ALT
    cancelBtn.BackgroundTransparency = 0.2
    cancelBtn.BorderSizePixel = 0
    cancelBtn.Position = UDim2.new(0.5, 4, 0, 86)
    cancelBtn.Size = UDim2.new(0.5, -20, 0, 36)
    cancelBtn.Font = Enum.Font.Gotham
    cancelBtn.Text = "Cancel"
    cancelBtn.TextColor3 = Theme.TEXT_DIM
    cancelBtn.TextSize = 14
    cancelBtn.ZIndex = 31
    cancelBtn.Parent = overlay
    round(cancelBtn, 8)

    box:CaptureFocus()

    okBtn.MouseButton1Click:Connect(function()
        local name = box.Text
        if not name or #name == 0 then
            showNotify("Name cannot be empty", Theme.WARN)
            return
        end
        local pos = root.Position
        local wp = {
            NAME = name,
            COORD = { math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z) },
            FAVORITE = false,  -- never auto-favorite
            CREATED = os.time(),
        }
        table.insert(getCurrentWaypoints(), wp)
        -- Refresh place name cache
        local pn = getPlaceName()
        if pn then Database.__meta.PLACE_NAMES[CurrentPlaceId] = pn end
        saveDatabase()
        renderWaypoints()
        overlay:Destroy()
        showNotify("Saved: " .. name, Theme.GOOD)
    end)
    cancelBtn.MouseButton1Click:Connect(function()
        overlay:Destroy()
    end)
end

SaveBtn.MouseButton1Click:Connect(promptSavePosition)

--============================================================
-- SEARCH
--============================================================
SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    renderWaypoints()
end)

--============================================================
-- TAB HANDLERS
--============================================================
local function promptMaps()
    local overlay = Instance.new("Frame")
    overlay.BackgroundColor3 = Theme.BG
    overlay.BackgroundTransparency = 0.02
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.new(0, 320, 0, 360)
    overlay.Position = UDim2.new(0.5, -160, 0.5, -180)
    overlay.ZIndex = 30
    overlay.Parent = Window
    round(overlay, 12)
    stroke(overlay, Theme.BORDER, 1, 0.2)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 16, 0, 10)
    title.Size = UDim2.new(1, -70, 0, 24)
    title.Font = Enum.Font.GothamBold
    title.Text = "SAVED MAPS"
    title.TextColor3 = Theme.TEXT
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 31
    title.Parent = overlay

    local closeBtn = Instance.new("TextButton")
    closeBtn.BackgroundColor3 = Theme.PANEL_ALT
    closeBtn.BackgroundTransparency = 0.2
    closeBtn.BorderSizePixel = 0
    closeBtn.Position = UDim2.new(1, -42, 0, 8)
    closeBtn.Size = UDim2.new(0, 34, 0, 34)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "×"
    closeBtn.TextColor3 = Theme.TEXT
    closeBtn.TextSize = 18
    closeBtn.ZIndex = 31
    closeBtn.Parent = overlay
    round(closeBtn, 8)
    closeBtn.MouseButton1Click:Connect(function() overlay:Destroy() end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.BackgroundTransparency = 1
    scroll.Position = UDim2.new(0, 12, 0, 50)
    scroll.Size = UDim2.new(1, -24, 1, -62)
    scroll.ScrollBarThickness = 5
    scroll.ScrollBarImageColor3 = Theme.BORDER
    scroll.ScrollBarImageTransparency = 0.4
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.Parent = overlay

    local ll = Instance.new("UIListLayout")
    ll.Padding = UDim.new(0, 8)
    ll.Parent = scroll

    for placeId, list in pairs(Database) do
        if placeId ~= "__meta" and type(list) == "table" and #list > 0 then
            local row = Instance.new("TextButton")
            row.BackgroundColor3 = Theme.CARD
            row.BackgroundTransparency = 0.1
            row.BorderSizePixel = 0
            row.Size = UDim2.new(1, -6, 0, 48)
            row.Font = Enum.Font.Gotham
            row.Text = ""
            row.Parent = scroll
            round(row, 8)
            stroke(row, Theme.BORDER_LO, 1, 0.4)

            -- Resolve display name: prefer cached place name, else PlaceId
            local placeKey = tostring(placeId)
            local pn = Database.__meta.PLACE_NAMES and Database.__meta.PLACE_NAMES[placeKey]
            if not pn and placeKey == CurrentPlaceId then
                pn = getPlaceName()
                if pn then Database.__meta.PLACE_NAMES[placeKey] = pn end
            end
            local displayName = pn and pn or ("PlaceId: " .. placeKey)
            local prefix = (placeKey == CurrentPlaceId) and "[current] " or ""

            local nameTxt = Instance.new("TextLabel")
            nameTxt.BackgroundTransparency = 1
            nameTxt.Position = UDim2.new(0, 12, 0, 4)
            nameTxt.Size = UDim2.new(1, -70, 1, -8)
            nameTxt.Font = Enum.Font.Gotham
            nameTxt.Text = prefix .. displayName
            nameTxt.TextColor3 = Theme.TEXT
            nameTxt.TextSize = 13
            nameTxt.TextXAlignment = Enum.TextXAlignment.Left
            nameTxt.TextTruncate = Enum.TextTruncate.AtEnd
            nameTxt.Parent = row

            local countLbl = Instance.new("TextLabel")
            countLbl.BackgroundTransparency = 1
            countLbl.Position = UDim2.new(1, -52, 0, 0)
            countLbl.Size = UDim2.new(0, 42, 1, 0)
            countLbl.Font = Enum.Font.GothamBold
            countLbl.Text = tostring(#list)
            countLbl.TextColor3 = Theme.TEXT_DIM
            countLbl.TextSize = 14
            countLbl.TextXAlignment = Enum.TextXAlignment.Right
            countLbl.Parent = row
        end
    end
end

local function promptFavorites()
    -- Uses SAME filter as the FAVORITES button in filter row
    currentFilter = "FAVORITES"
    SearchBox.Text = ""
    refreshFilterButtons()
    renderWaypoints()
    showNotify("Showing favorites only", Theme.FAV)
end

local function promptMore()
    local overlay = Instance.new("Frame")
    overlay.BackgroundColor3 = Theme.BG
    overlay.BackgroundTransparency = 0.02
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.new(0, 310, 0, 320)
    overlay.Position = UDim2.new(0.5, -155, 0.5, -160)
    overlay.ZIndex = 30
    overlay.Parent = Window
    round(overlay, 12)
    stroke(overlay, Theme.BORDER, 1, 0.2)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 16, 0, 10)
    title.Size = UDim2.new(1, -70, 0, 24)
    title.Font = Enum.Font.GothamBold
    title.Text = "MORE"
    title.TextColor3 = Theme.TEXT
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 31
    title.Parent = overlay

    local closeBtn = Instance.new("TextButton")
    closeBtn.BackgroundColor3 = Theme.PANEL_ALT
    closeBtn.BackgroundTransparency = 0.2
    closeBtn.BorderSizePixel = 0
    closeBtn.Position = UDim2.new(1, -42, 0, 8)
    closeBtn.Size = UDim2.new(0, 34, 0, 34)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "×"
    closeBtn.TextColor3 = Theme.TEXT
    closeBtn.TextSize = 18
    closeBtn.ZIndex = 31
    closeBtn.Parent = overlay
    round(closeBtn, 8)
    closeBtn.MouseButton1Click:Connect(function() overlay:Destroy() end)

    local function menuButton(text, y, color, cb)
        local b = Instance.new("TextButton")
        b.BackgroundColor3 = color or Theme.CARD
        b.BackgroundTransparency = 0.1
        b.BorderSizePixel = 0
        b.Position = UDim2.new(0, 16, 0, y)
        b.Size = UDim2.new(1, -32, 0, 42)
        b.Font = Enum.Font.Gotham
        b.Text = text
        b.TextColor3 = (color == Theme.DANGER) and Theme.DANGER or Theme.TEXT
        b.TextSize = 14
        b.ZIndex = 31
        b.Parent = overlay
        round(b, 8)
        stroke(b, Theme.BORDER_LO, 1, 0.4)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    menuButton("Export Database (clipboard)", 50, Theme.CARD, function()
        local ok, encoded = pcall(function() return HttpService:JSONEncode(Database) end)
        if not ok then showNotify("Export failed", Theme.DANGER) return end
        if type(setclipboard) == "function" then
            local okc = pcall(setclipboard, encoded)
            if okc then showNotify("Exported to clipboard", Theme.GOOD)
            else showNotify("Clipboard unavailable", Theme.WARN) end
        else
            showNotify("Clipboard unavailable", Theme.WARN)
        end
    end)

    menuButton("Import from Clipboard", 100, Theme.CARD, function()
        if type(getclipboard) ~= "function" then
            showNotify("getclipboard unavailable", Theme.WARN)
            return
        end
        local ok, data = pcall(getclipboard)
        if not ok or type(data) ~= "string" then
            showNotify("Clipboard read failed", Theme.DANGER)
            return
        end
        local ok2, decoded = pcall(function() return HttpService:JSONDecode(data) end)
        if not ok2 or type(decoded) ~= "table" then
            showNotify("Invalid JSON", Theme.DANGER)
            return
        end
        local cleaned = sanitizeDatabase(decoded)
        for k, v in pairs(cleaned) do
            if k == "__meta" then
                Database.__meta = Database.__meta or {}
                for mk, mv in pairs(v) do
                    Database.__meta[mk] = mv
                end
            else
                Database[k] = v
            end
        end
        saveDatabase()
        renderWaypoints()
        showNotify("Import success", Theme.GOOD)
    end)

    menuButton("View History", 150, Theme.CARD, function()
        overlay:Destroy()
        local h = Instance.new("Frame")
        h.BackgroundColor3 = Theme.BG
        h.BackgroundTransparency = 0.02
        h.BorderSizePixel = 0
        h.Size = UDim2.new(0, 310, 0, 330)
        h.Position = UDim2.new(0.5, -155, 0.5, -165)
        h.ZIndex = 32
        h.Parent = Window
        round(h, 12)
        stroke(h, Theme.BORDER, 1, 0.2)

        local ht = Instance.new("TextLabel")
        ht.BackgroundTransparency = 1
        ht.Position = UDim2.new(0, 16, 0, 10)
        ht.Size = UDim2.new(1, -70, 0, 24)
        ht.Font = Enum.Font.GothamBold
        ht.Text = "HISTORY"
        ht.TextColor3 = Theme.TEXT
        ht.TextSize = 15
        ht.TextXAlignment = Enum.TextXAlignment.Left
        ht.ZIndex = 33
        ht.Parent = h

        local hb = Instance.new("TextButton")
        hb.BackgroundColor3 = Theme.PANEL_ALT
        hb.BackgroundTransparency = 0.2
        hb.BorderSizePixel = 0
        hb.Position = UDim2.new(1, -42, 0, 8)
        hb.Size = UDim2.new(0, 34, 0, 34)
        hb.Font = Enum.Font.GothamBold
        hb.Text = "×"
        hb.TextColor3 = Theme.TEXT
        hb.TextSize = 18
        hb.ZIndex = 33
        hb.Parent = h
        round(hb, 8)
        hb.MouseButton1Click:Connect(function() h:Destroy() end)

        local hscroll = Instance.new("ScrollingFrame")
        hscroll.BackgroundTransparency = 1
        hscroll.Position = UDim2.new(0, 12, 0, 50)
        hscroll.Size = UDim2.new(1, -24, 1, -62)
        hscroll.ScrollBarThickness = 5
        hscroll.ScrollBarImageColor3 = Theme.BORDER
        hscroll.ScrollBarImageTransparency = 0.4
        hscroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        hscroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        hscroll.Parent = h

        local hll = Instance.new("UIListLayout")
        hll.Padding = UDim.new(0, 8)
        hll.Parent = hscroll

        for _, entry in ipairs(Database.__meta.HISTORY or {}) do
            local row = Instance.new("TextButton")
            row.BackgroundColor3 = Theme.CARD
            row.BackgroundTransparency = 0.1
            row.BorderSizePixel = 0
            row.Size = UDim2.new(1, -6, 0, 44)
            row.Font = Enum.Font.Gotham
            row.Text = ""
            row.Parent = hscroll
            round(row, 8)
            stroke(row, Theme.BORDER_LO, 1, 0.4)

            local nm = Instance.new("TextLabel")
            nm.BackgroundTransparency = 1
            nm.Position = UDim2.new(0, 12, 0, 0)
            nm.Size = UDim2.new(1, -24, 1, 0)
            nm.Font = Enum.Font.Gotham
            nm.Text = entry.NAME .. "  •  PlaceId: " .. tostring(entry.PLACEID)
            nm.TextColor3 = Theme.TEXT
            nm.TextSize = 13
            nm.TextXAlignment = Enum.TextXAlignment.Left
            nm.TextTruncate = Enum.TextTruncate.AtEnd
            nm.Parent = row

            row.MouseButton1Click:Connect(function()
                if tostring(entry.PLACEID) ~= CurrentPlaceId then
                    showNotify("Different PlaceId", Theme.WARN)
                    return
                end
                local root = getCharacterRoot()
                if not root then
                    showNotify("Character not loaded", Theme.WARN)
                    return
                end
                -- Save current pos as Last Position before teleport
                setLastPosition({ root.Position.X, root.Position.Y, root.Position.Z }, CurrentPlaceId)
                -- Remove old history entry, then re-push (moves to top with fresh time)
                for i = #Database.__meta.HISTORY, 1, -1 do
                    if Database.__meta.HISTORY[i] == entry then
                        table.remove(Database.__meta.HISTORY, i)
                    end
                end
                pushHistory(entry, entry.PLACEID or CurrentPlaceId)
                saveDatabase()
                root.CFrame = CFrame.new(entry.COORD[1], entry.COORD[2], entry.COORD[3])
                showNotify("Teleported: " .. entry.NAME, Theme.ACTION)
            end)
        end
    end)

    menuButton("Clear History", 200, Theme.CARD, function()
        Database.__meta.HISTORY = {}
        saveDatabase()
        showNotify("History cleared", Theme.GOOD)
    end)

    menuButton("Clear Current Map", 250, Theme.DANGER, function()
        Database[CurrentPlaceId] = {}
        saveDatabase()
        renderWaypoints()
        showNotify("Current map cleared", Theme.DANGER)
    end)
end

local function promptBack()
    local lp = Database.__meta.LAST_POSITION
    if not lp or not lp.COORD then
        showNotify("No last position saved", Theme.WARN)
        return
    end
    if tostring(lp.PLACEID) ~= CurrentPlaceId then
        showNotify("Last position from another place", Theme.WARN)
        return
    end
    local root = getCharacterRoot()
    if not root then showNotify("Character not loaded", Theme.WARN) return end
    -- NOTE: No history push here — BACK goes to a saved position, not a waypoint.
    root.CFrame = CFrame.new(lp.COORD[1], lp.COORD[2], lp.COORD[3])
    showNotify("Back to last position", Theme.ACTION)
end

tabButtons["MAPS"].MouseButton1Click:Connect(promptMaps)
tabButtons["FAVORITES"].MouseButton1Click:Connect(promptFavorites)
tabButtons["MORE"].MouseButton1Click:Connect(promptMore)
tabButtons["BACK"].MouseButton1Click:Connect(promptBack)

--============================================================
-- RESPONSIVE ON VIEWPORT CHANGE
--============================================================
local function repositionIfNeeded()
    if Window.Visible then
        local target = computeWindowSize()
        -- Preserve Position (AnchorPoint handles centering)
        TweenService:Create(Window, TweenInfo.new(0.18), { Size = target }):Play()
    end
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(repositionIfNeeded)

--============================================================
-- INIT
--============================================================
renderWaypoints()
refreshFilterButtons()

-- Open on first run (fresh position = screen center via AnchorPoint)
openWindow()