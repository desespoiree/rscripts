--Author: @.desespoire | https://v3rm.net/members/001.1198/
local gc = cloneservice or function(s) return s end

local RunService = gc(game:GetService("RunService"))
local UserInputService = gc(game:GetService("UserInputService"))
local CoreGui = gc(game:GetService("CoreGui"))
local Players = gc(game:GetService("Players"))

local LocalPlayer = Players.LocalPlayer
local CurrentCamera = workspace.CurrentCamera

local defaultSettings = {
    ShowDistance = false,
    ShowName = false,

    ShowHealth = false,
    HealthBarMode = "Filled",

    ShowBox = false,
    BoxMode = "Drawing",

    ShowTracer = false,
    Color = Color3.fromRGB(255, 255, 255),

    VisibleOnly = false,

    ChamsEnabled = false,
    Chams = {
        Occluded = "Occluded",

        OutlineColor = Color3.fromRGB(255, 255, 255),
        FillColor = Color3.fromRGB(255, 255, 255),

        OutlineTransparency = 0,
        FillTransparency = 1
    },
    -- MaxDistance = 9e9
}

local Library = {
    Items = {},

    Players = {
        Settings = defaultSettings,
        List = {},
        Enabled = false,
        ShowTeam = false,
    },

    DrawedShits = {},
    Connections = {},

    TeamColors = {
        Ally = Color3.fromRGB(160, 255, 82),
        Enemy = Color3.fromRGB(160, 255, 82),
    },

    Enabled = false,

    TextSize = 15,
    TracerMode = "Bottom",
    --
    tracerOrigin = Vector2.zero
}

Library.Items["Players"] = Library.Players -- 2025 cyclic hack

local Item = {
    Settings = defaultSettings
}
Item.__index = Item

type Setting = {
    ShowDistance: boolean,
    ShowName: boolean,

    TracerEnabled: boolean,
    TracerMode : "Mouse"| "Center" | "Top" | "Bottom",

    MaxDistance: number?,

    Color: Color3, -- Players are Ally, Enemy or Team.Color

    VisibleOnly: boolean?,

    --Specific to Objects with humanoid (Object must be a Model)
    ShowHealth: boolean,
    HealthBarMode: "Filled" | "Normal",

    ShowBox: boolean,
    BoxMode: "Drawing" | "3D",

    ChamsEnabled: boolean?,
    Chams: {
        Occluded: boolean,

        OutlineColor: Color3,
        FillColor: Color3,

        OutlineTransparency: number,
        FillTransparency: number,
    },
}

type DPlayer = {
    Settings: Setting
}

type Items = {
    Settings: Setting,
    List: {number: Item}
}

local abs, floor, clamp = math.abs, math.floor, math.clamp

local function fixTable(t: table)
    for name, value in defaultSettings do
        if t[name] == nil then
            t[name] = value
        end
    end

    return t
end

local function Connect(signal: RBXScriptSignal, fn: (...any) -> nil): RBXScriptConnection
    local con = signal:Connect(fn)
    table.insert(Library.Connections, con)
    return con
end

--
local function Draw(name: string, config: table)
    local drew = Drawing.new(name)

    for k, v in config do
        drew[k] = v
    end

    if name == "Text" and not config.TextSize then
        drew.Size = 14
    end

    return drew
end

local function Create(className: string, config)
    local instance = Instance.new(className)

    for k, v in config do
        -- if typeof(config[k]) ~= typeof(instance[k]) then
        --     continue
        -- end
        if k == "Occluded" then
            continue
        end

        instance[k] = v
    end

    if not instance.Parent then
        instance.Parent = CoreGui
    end

    return instance
end

local function GetTracerOrigin(): Vector2
    local origin = Library.TracerMode

    local viewportSize = CurrentCamera.ViewportSize

    if origin == "Mouse" then
        return UserInputService:GetMouseLocation()
    elseif origin == "Bottom" then
        return Vector2.new(viewportSize.X / 2, CurrentCamera.ViewportSize.Y)
    elseif origin == "Top" then
        return Vector2.new(viewportSize.X / 2, 0)
    else
        return Vector2.new(CurrentCamera.ViewportSize.X / 2, viewportSize.Y / 2)
    end
end

local function IsInRange(point: Vector3, range: number)
    local distance = LocalPlayer:DistanceFromCharacter(point)

    if distance == 0 then
        return false
    end

    return distance < range
end

--Item
function Item.new(flag: string, object: Model | BasePart)
    local self = setmetatable({
        flag = flag,
        name = flag == "Players" and object.Name or flag,
        object = object,
        rootPart = (object:IsA("Model") and (object:WaitForChild("HumanoidRootPart", 2) or object.PrimaryPart or object:FindFirstChildOfClass("BasePart"))) or object,
        isABasePart = object:IsA("BasePart"),
        humanoid = object:WaitForChild("Humanoid", 2),
        player = Players:GetPlayerFromCharacter(object) or Players:FindFirstChild(object.Name),
        hidden = true,

        con1 = nil,
        con2 = nil,
    }, Item)

    self.con1 = object.AncestryChanged:Connect(function()
        if object.Parent then return end
        self:Destroy()
    end)

    self.con2 = object.ChildAdded:Connect(function(child)
        if child.ClassName ~= "Humanoid" then return end
        self.humanoid = child
    end)

    self:init()

    return self
end

function Item:getSettings(): Setting
    if self.flag == "Players" then
        return Library.Players.Settings
    end

    return Library.Items[self.flag].Settings-- or defaultSettings
end

function Item:init()
    self.Drawing = {
        Name = Draw("Text", {
            Center = true,
            Outline = true,
            Color = Color3.fromRGB(255, 255, 255),
            Visible = false
        }),
        Distance = Draw("Text", {
            Center = true,
            Outline = true,
            Color = Color3.fromRGB(255, 255, 255),
            Visible = false
        }),

        HealthBarOutline = Draw("Square", {
            Thickness = 2,
            Color = Color3.fromRGB(0, 0, 0),
            Filled = false,
            Visible = false
        }),
        HealthBar = Draw("Line", {
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 2,
            Visible = false
        }),
        TopHealthBar = Draw("Line", {
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 2,
            Visible = false
        }),

        Tracer = Draw("Line", {
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 1,
            Visible = false
        }),
        Box = Draw("Square", {
            Thickness = 1,
            Color = Color3.fromRGB(255, 255, 255),
            Filled = false,
            Visible = false
        })
    }
    self.Instances = {
        highlight = Create("Highlight", defaultSettings.Chams)
    }
end

function Item:hide()
    if self.hidden then return end
    self.hidden = true

    for _, v in self.Drawing do
        v.Visible = false
    end
end

function Item:update()
    if not self.object or not self.object:IsDescendantOf(workspace) then return end
    if not self.rootPart then return end

    local config = self:getSettings()
    local draw = self.Drawing

    local objectCF, objectSize = self.object:GetBoundingBox()
    objectSize = objectSize.Y / 2

    local top, topOnScreen = CurrentCamera:WorldToViewportPoint(
        objectCF.Position + Vector3.new(0, objectSize, 0)
    )
    local bottom, bottomOnScreen = CurrentCamera:WorldToViewportPoint(
        objectCF.Position - Vector3.new(0, objectSize, 0)
    )

    local onScreen = topOnScreen or bottomOnScreen
    local distance = (LocalPlayer.Character and LocalPlayer:DistanceFromCharacter(self.rootPart.Position)) or 0

    if
        not onScreen
        or (
            config.MaxDistance
            and not IsInRange(self.rootPart.Position, config.MaxDistance)
        )
        or (
            self.player
            and Library.Players.Settings.TeamCheck
            and not Library.Players.Settings.ShowTeam
            and self.player.Team == LocalPlayer.Team
        )
        or (
            config.VisibleOnly
            and not self:isVisible()
        )
    then
        self:hide()
        self.Instances.highlight.Enabled = false
        return
    end

    self:updateUHQ()

    self.hidden = false

    local boxHeight = bottom.Y - top.Y
    local boxWidth = boxHeight / 2
    local topLeft = Vector2.new(top.X - boxWidth / 2, top.Y)

    -- Box
    if config.ShowBox then
        draw.Box.Position = topLeft
        draw.Box.Size = Vector2.new(boxWidth, boxHeight)
        draw.Box.Visible = true
    else
        draw.Box.Visible = false
    end

    -- Name
    if config.ShowName then
        draw.Name.Position = Vector2.new(top.X, top.Y - 16)
        draw.Name.Text = self.object.Name
        draw.Name.Visible = true
    else
        draw.Name.Visible = false
    end

    -- Distance
    if config.ShowDistance then
        draw.Distance.Position = Vector2.new(top.X, bottom.Y + 2)
        draw.Distance.Text = string.format("%d Studs", math.floor(distance))
        draw.Distance.Visible = true
    else
        draw.Distance.Visible = false
    end

    -- Health (vertical bar)
    if config.ShowHealth and self.humanoid then
        local hpPercent = math.clamp(self.humanoid.Health / self.humanoid.MaxHealth, 0, 1)

        local barX = topLeft.X - 6
        local barHeight = boxHeight
        local filledHeight = barHeight * hpPercent
        local missingHeight = barHeight - filledHeight

        local barTopY = topLeft.Y

        draw.HealthBarOutline.Position = Vector2.new(barX - 1, barTopY - 1)
        draw.HealthBarOutline.Size = Vector2.new(3, barHeight + 2)
        draw.HealthBarOutline.Thickness = 2
        draw.HealthBarOutline.Color = Color3.fromRGB(0, 0, 0)
        draw.HealthBarOutline.Visible = true


        if config.HealthBarMode == "Filled" then
            draw.TopHealthBar.From = Vector2.new(barX, barTopY + missingHeight)
            draw.TopHealthBar.To = Vector2.new(barX, barTopY + barHeight)
            draw.TopHealthBar.Color = Color3.fromRGB(0, 255, 0)
            draw.TopHealthBar.Visible = true

            draw.HealthBar.From = Vector2.new(barX, barTopY)
            draw.HealthBar.To = Vector2.new(barX, barTopY + missingHeight)
            draw.HealthBar.Color = Color3.fromRGB(255, 0, 0)
            draw.HealthBar.Visible = true
        else
            draw.HealthBar.From = Vector2.new(barX, barTopY + (barHeight - filledHeight))
            draw.HealthBar.To = Vector2.new(barX, barTopY + barHeight)
            draw.HealthBar.Color = Color3.fromRGB(255 - (hpPercent * 255), hpPercent * 255, 0)
            draw.HealthBar.Visible = true

            draw.TopHealthBar.Visible = false
        end
    else
        draw.HealthBar.Visible = false
        draw.TopHealthBar.Visible = false
        draw.HealthBarOutline.Visible = false
    end

    -- Tracer
    if config.ShowTracer then
        draw.Tracer.From = Library.tracerOrigin
        draw.Tracer.To = Vector2.new(top.X, bottom.Y)
        draw.Tracer.Visible = true
    else
        draw.Tracer.Visible = false
    end

    -- for name, drawedShit in self.Drawing do
    --     if name == "HealthBar" or name == "TopHealthBar" then
    --         continue
    --     end

    --     drawedShit.Color = itemColor
    -- end
end

function Item:updateUHQ()
    local highlight: Highlight = self.Instances.highlight
    local settings = self:getSettings()
    local enabled = settings.ChamsEnabled

    highlight.Enabled = enabled

    if not enabled then
        highlight.Enabled = false
        return
    end

    local config = settings.Chams
    highlight.DepthMode = config.Occluded and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop

    highlight.OutlineColor = config.OutlineColor
    highlight.FillColor = config.FillColor

    highlight.OutlineTransparency = config.OutlineTransparency
    highlight.FillTransparency = config.FillTransparency

    highlight.Adornee = self.object
end

function Item:getColor()
    if
        self.flag == "Players"
        and self.player
    then
        local team: Team = self.player.Team

        if team == LocalPlayer.Team then
            return Library.TeamColors.Ally
        else
            return Library.TeamColors[team.Name] or Library.TeamColors.Enemy or team.TeamColor.Color
        end
    end

    return self.Settings.Color
end

function Item:isVisible()
    local cameraPos = CurrentCamera.CFrame.Position
    local objectPos = self.rootPart.Position

    local rayParms = RaycastParams.new()
    rayParms.FilterDescendantsInstances = {LocalPlayer.Character, self.object}
    rayParms.RespectCanCollide = true
    rayParms.FilterType = Enum.RaycastFilterType.Exclude

    local ray = workspace:Raycast(
        cameraPos,
        objectPos - cameraPos.Unit * (cameraPos - objectPos).Magnitude,
        rayParms
    )

    return ray == nil
end

function Item:Destroy()
    if self.Drawing then
        for _, drawed in self.Drawing do
            drawed:Remove()
        end
    end


    if self.Instances then
        for _, instance in self.Instances do
            instance:Destroy()
        end
    end


    self.con1:Disconnect()
    self.con2:Disconnect()

    -- self.Drawing = nil
    -- self.object = nil
    -- self.haveHumanoid = nil
end
--

function Update()
    Library.tracerOrigin = GetTracerOrigin()

    for groupName, group in Library.Items do
        for _, item in group.List do
            if
                group.Enabled
            then
                item:update()
            else
                item:hide()
            end
        end
    end
end

--
function Library.newItem(flag: string, object: Model | BasePart, itemSettings: Setting?)
    local itemTable = Library.Items[flag]

    if not itemTable then
        itemTable = {
            Enabled = false,
            List = {},
            Settings = defaultSettings
        }

        Library.Items[flag] = itemTable
    end

    -- if not itemTable._sexy then
    --     warn("not sexied", flag)
    --     itemTable._sexy = true

    --     setmetatable(itemTable.Settings, {
    --         __newindex = function(t, k, v)
    --             print("__newindex", t, k, v)
    --             rawset(t, k, v)
    --         end,
    --     })
    -- end

    -- if flag == "Players" then
    --     setti
    -- end

    local item = Item.new(flag, object)
    -- item.Settings = createSettingsProxy({}, Setting)
    table.insert(itemTable.List, item)
    return item
end

function Library:Enable(state: boolean)
    if self.Connections.updateCon then
        self.Connections.updateCon:Disconnect()
    end

    if not state then
        for _, group in Library.Items do
            for _, item in group.List do
                item:hide()
            end
        end

        return
    end

    self.Connections.updateCon = RunService.RenderStepped:Connect(Update)
end

function Library:Destroy()
    for _, group in Library.Items do
        for _, item in group.List do
            item:Destroy()
        end
    end

    for _, con in self.Connections do
        con:Disconnect()
    end
end

--
local function CreatePlayerESP(player: Player)
    if player == LocalPlayer then return end

    local function characterAdded(character: Model)
        Library.newItem("Players", character)
    end

    Connect(player.CharacterAdded, characterAdded)

    if player.Character then
        characterAdded(player.Character)
    end
end

for _, player in Players:GetPlayers() do
    task.spawn(CreatePlayerESP, player)
end

Connect(Players.PlayerAdded, CreatePlayerESP)
Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    if not workspace.CurrentCamera then return end
    CurrentCamera = workspace.CurrentCamera
end)

return Library
