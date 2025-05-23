local cloneservice = function(s)
	return s
end

local RunService = cloneservice(game:GetService("RunService"))
local UserInputService = cloneservice(game:GetService("UserInputService"))
local CoreGui = cloneservice(game:GetService("CoreGui"))
local Players = cloneservice(game:GetService("Players"))

local LocalPlayer = Players.LocalPlayer
local CurrentCamera = workspace.CurrentCamera

local defaultSettings = {
	ShowDistance = false,
	ShowName = false,

	ShowHealth = false,
	HealthBarMode = "Filled",
	HealthBarDisplayMode = "Left",

	ShowBox = false,
	BoxMode = "Drawing",

	ShowTracer = false,

	Color = Color3.fromRGB(255, 255, 255),
	NameColor = Color3.fromRGB(255, 255, 255),
	DistanceColor = Color3.fromRGB(255, 255, 255),
	BoxColor = Color3.fromRGB(255, 255, 255),
	TracerColor = Color3.fromRGB(255, 255, 255),
	PrimaryHealthColor = Color3.fromRGB(0, 255, 0),
	SecondaryHealthColor = Color3.fromRGB(255, 0, 0),

	VisibleOnly = false,
	AliveOnly = false,

	ChamsEnabled = false,
	Chams = {
		Occluded = true,

		OutlineColor = Color3.fromRGB(255, 255, 255),
		FillColor = Color3.fromRGB(255, 255, 255),

		OutlineTransparency = 0,
		FillTransparency = 1,
	},

	-- MaxDistance = 9e9
}

local Library = {
	Items = {},

	Players = {
		Settings = table.clone(defaultSettings),
		List = {},
		Enabled = false,
		ShowTeam = false,
	},

	Connections = {},

	Enabled = false,

	TextSize = 15,
	TracerMode = "Bottom",
	--
	tracerOrigin = Vector2.zero,

	CurrentTeam = nil,
	CustomRootPart = nil,
}

local Item = {}
Item.__index = Item

local REFRESH_RATE = 1 / 120

local function DistanceFromCharacter(from: Vector3)
	if Library.CustomRootPart then
		return (from - Library.CustomRootPart.Position).Magnitude
	else
		return LocalPlayer:DistanceFromCharacter(from)
	end
end

local function Connect(signal: RBXScriptSignal, fn: (...any) -> nil): RBXScriptConnection
	local con = signal:Connect(fn)
	table.insert(Library.Connections, con)
	return con
end

local function newCamera()
	if not workspace.CurrentCamera then
		return
	end

	CurrentCamera = workspace.CurrentCamera

	if Library.Connections.updateCon then Library.Connections.updateCon:Disconnect() end
	Library.Connections.updateCon = CurrentCamera:GetPropertyChangedSignal("CFrame"):Connect(Update)
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
		if k == "Occluded" then
			continue
		end

		instance[k] = v
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
	local distance = DistanceFromCharacter(point)

	if distance == 0 then
		return false
	end

	return distance < range
end

--Item
function Item.new(flag: string, object: Model | BasePart)
	assert(object, "Missing object")

	local self = setmetatable({
		flag = flag,
		name = flag == "Players" and object.Name or flag,
		object = object,
		rootPart = nil,
		isABasePart = object:IsA("BasePart"),
		humanoid = object:WaitForChild("Humanoid", 1),

		player = Players:GetPlayerFromCharacter(object) or Players:FindFirstChild(object.Name),

		hidden = true,
		_lastUpdate = 0,
		currentHp = 0,

		_ancestryChanged = nil,
		_objectMoved = nil,
		_healthChanged = nil,
		con2 = nil,
		con3 = nil,
		con4 = nil
	}, Item)

	local function childUpdate()
		local newRoot
		if object:IsA("Model") then
			newRoot = object:FindFirstChild("HumanoidRootPart")
				or object:FindFirstChild("Root")
				or object.PrimaryPart
				or object:FindFirstChildWhichIsA("BasePart")
		else
			newRoot = object
		end

		self.rootPart = newRoot

		if (not self.rootPart) or not object.Parent then
			self.loaded = false
			self:hide(true)
		elseif self.rootPart and not self.loaded then
			self.loaded = true
		end

		self:_trackMovements()
		self:_trackHealth()
	end

	self._ancestryChanged = object.AncestryChanged:Connect(childUpdate)
	self.con2 = object.DescendantAdded:Connect(function(child)
		if not self.loaded and child:IsA("BasePart") then
			return childUpdate()
		elseif child.ClassName == "Humanoid" then
			self.humanoid = child
		end
	end)

	self.con3 = object.DescendantRemoving:Connect(function(child)
		if self.rootPart ~= child or not object:IsA("Model") then
			return
		end

		childUpdate()
	end)

	self.con4 = object.Destroying:Once(function()
		self:Destroy()
	end)

	self:init()
	self:updateColors()
	childUpdate()

	self:update(true)


	return self
end

function Item:getSettings()
	return Library.Items[self.flag].Settings
end

function Item:init()
	self.Drawing = {
		Name = Draw("Text", {
			Center = true,
			Outline = true,
			Color = Color3.fromRGB(255, 255, 255),
			Visible = false,
		}),
		Distance = Draw("Text", {
			Center = true,
			Outline = true,
			Color = Color3.fromRGB(255, 255, 255),
			Visible = false,
		}),

		HealthBarOutline = Draw("Square", {
			Thickness = 2,
			Color = Color3.fromRGB(0, 0, 0),
			Filled = false,
			Visible = false,
		}),
		HealthBar = Draw("Line", {
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 2,
			Visible = false,
		}),
		TopHealthBar = Draw("Line", {
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 2,
			Visible = false,
		}),

		Tracer = Draw("Line", {
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 1,
			Visible = false,
		}),
		Box = Draw("Square", {
			Thickness = 1,
			Color = Color3.fromRGB(255, 255, 255),
			Filled = false,
			Visible = false,
		}),
	}
	self.Highlight = Create("Highlight", defaultSettings.Chams)
end

function Item:hide(forcedToHide)
	if self.hidden then return end
	self.hidden = true

	for _, v in self.Drawing do
		v.Visible = false
	end

	if self._objectMoved then self._objectMoved:Disconnect() end
	if self._healthChanged then self._healthChanged:Disconnect() end

	if not forcedToHide then return end
	-- self.Highlight.Enabled = false
	self.Highlight.Parent = nil
end

function Item:_trackMovements()
	if self._objectMoved then
		self._objectMoved:Disconnect()
		self._objectMoved = nil
	end

	if not self.rootPart then return end

	self._objectMoved = self.rootPart:GetPropertyChangedSignal("CFrame"):Connect(function()
		if self.hidden then return end
		self:update()
	end)
end

function Item:_trackHealth()
	if self._healthChanged then
		self._healthChanged:Disconnect()
		self._healthChanged = nil
	end

	local humanoid = self.humanoid
	if not humanoid then return end

	local function update()
		self.currentHp = math.clamp(humanoid.Health / (humanoid.MaxHealth or 100), 0, 1)
		if self.hidden then return end
		self:update(true)
	end

	task.spawn(update)

	if humanoid.ClassName == "Humanoid" then -- instance
		self._healthChanged = humanoid:GetPropertyChangedSignal("Health"):Connect(update)
	else -- custom humanoids
		local currentHp = nil
		local lastUpdate = 0

		self._healthChanged = RunService.Stepped:Connect(function(steppedTime)
			if self.hidden or steppedTime - lastUpdate < REFRESH_RATE then return end
			lastUpdate = steppedTime

			local newHP = humanoid.Health

			if currentHp ~= newHP then
				currentHp = newHP
				update()
			end
		end)
	end
end

function Item:update(forcedUpdate)
	local now = os.clock()

	if not self.object:IsDescendantOf(game) or not self.rootPart then
		self:hide(true)
		return
	end

	local config = self:getSettings()
	local draw = self.Drawing

	if config.MaxDistance and not IsInRange(self.rootPart.Position, config.MaxDistance) then
		self.shouldRender = false
		self:hide(true)
		return
	end

	local objectCF, objectSize = self.object:GetBoundingBox()
	objectSize = objectSize.Y / 2

	local top, topOnScreen = CurrentCamera:WorldToViewportPoint(objectCF.Position + Vector3.new(0, objectSize, 0))
	local bottom, bottomOnScreen = CurrentCamera:WorldToViewportPoint(objectCF.Position - Vector3.new(0, objectSize, 0))

	local onScreen = topOnScreen or bottomOnScreen
	local distance = DistanceFromCharacter(self.rootPart.Position)

	self.shouldRender = not (
		self.player
		and Library.Players.Settings.TeamCheck
		and not Library.Players.Settings.ShowTeam
		and self.player.Team == (Library.CurrentTeam or LocalPlayer.Team)
	)

	if config.VisibleOnly and not self:isVisible() then
		self:hide(true)
		return
	end

	local visibleCheckFailed = config.VisibleOnly and not self:isVisible()
	local deadAndAliveCheck = config.AliveOnly and self.humanoid and self.humanoid.Health <= 0

	if not self.loaded or not onScreen or not self.shouldRender or visibleCheckFailed or self.distanceTooFar or deadAndAliveCheck then
		self:hide(self.distanceTooFar or deadAndAliveCheck)
		return
	end

	if not forcedUpdate and now - self._lastUpdate < REFRESH_RATE then return end
	self._lastUpdate = now

	if self.hidden then
		self.hidden = false
		self:updateDrawedItemsVisibility()
		self:_trackHealth()
		self:_trackMovements()
	end

	self:updateChams()

	-- Box
	local boxHeight = bottom.Y - top.Y
	local boxWidth = boxHeight / 2
	local topLeft = Vector2.new(top.X - boxWidth / 2, top.Y)

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

	-- Health
	if config.ShowHealth and self.humanoid then
		local hpPercent = self.currentHp
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
			draw.TopHealthBar.Visible = true

			draw.HealthBar.From = Vector2.new(barX, barTopY)
			draw.HealthBar.To = Vector2.new(barX, barTopY + missingHeight)
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
end

function Item:updateChams()
	local highlight: Highlight = self.Highlight
	local settings = self:getSettings()
	local enabled = settings.ChamsEnabled and self.shouldRender and not self.hidden

	highlight.Enabled = enabled

	if not enabled then
		highlight.Enabled = false
		return
	end

	local config = settings.Chams

	highlight.DepthMode = (self.hidden or config.Occluded) and Enum.HighlightDepthMode.Occluded
		or Enum.HighlightDepthMode.AlwaysOnTop

	highlight.Parent = self.object
	-- highlight.Adornee = self.object
end

function Item:updateColors()
    local config = self:getSettings()
	local highlightConfig = config.Chams

    local draw = self.Drawing
	local highlight = self.Highlight

    draw.Name.Color = config.NameColor or config.Color
    draw.Distance.Color = config.DistanceColor or config.Color
    draw.Box.Color = config.BoxColor or config.Color
    draw.Tracer.Color = config.TracerColor or config.Color

    draw.TopHealthBar.Color = config.PrimaryHealthColor or Color3.fromRGB(0, 255, 0)
    draw.HealthBar.Color = config.SecondaryHealthColor or Color3.fromRGB(255, 0, 0)

	highlight.OutlineColor = highlightConfig.OutlineColor
	highlight.FillColor = highlightConfig.FillColor

	highlight.OutlineTransparency = highlightConfig.OutlineTransparency
	highlight.FillTransparency = highlightConfig.FillTransparency
end

function Item:updateDrawedItemsVisibility()
	if self.hidden then return end

    local config = self:getSettings()
    local draw   = self.Drawing

    draw.Box.Visible = config.ShowBox
    draw.Name.Visible = config.ShowName
    draw.Distance.Visible = config.ShowDistance

    if config.ShowHealth and self.humanoid then
        draw.HealthBarOutline.Visible = true

        if config.HealthBarMode == "Filled" then
            draw.TopHealthBar.Visible   = true
            draw.HealthBar.Visible      = true
        else
            draw.TopHealthBar.Visible   = false
            draw.HealthBar.Visible      = true
        end
    else
        draw.HealthBarOutline.Visible = false
        draw.TopHealthBar.Visible     = false
        draw.HealthBar.Visible        = false
    end

    draw.Tracer.Visible = config.ShowTracer
end

function Item:isVisible()--GetPartsObscuringTarget
	if not self.rootPart then return end

	local cameraPos = CurrentCamera.CFrame.Position
	local objectPos = self.rootPart.Position

	local rayParms = RaycastParams.new()
	rayParms.FilterDescendantsInstances = { Library.CustomRootPart and Library.CustomRootPart.Parent or LocalPlayer.Character, self.object, CurrentCamera }
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
	for _, drawed in self.Drawing do
		drawed:Remove()
	end

	self.Highlight:Destroy()

	self._ancestryChanged:Disconnect()
	if self._objectMoved then self._objectMoved:Disconnect() end
	if self._healthChanged then self._healthChanged:Disconnect() end
	self.con2:Disconnect()
	self.con3:Disconnect()
	self.con4:Disconnect()
end
--

function Update()
	if not Library.Enabled then return end

	Library.tracerOrigin = GetTracerOrigin()

	for _, group in Library.Items do
		for _, item in group.List do
			if group.Enabled then
				item:update()
			else
				item:hide(true)
			end
		end
	end
end

--
function Library.newItem(flag: string, object: Model | BasePart)
	local itemTable = Library.Items[flag]

	if not itemTable then
		itemTable = Library:createGroup(flag)
	end

	local item = Item.new(flag, object)
	table.insert(itemTable.List, item)
	return item
end

function Library:createGroup(flag)
    if self.Items[flag] then
        return self.Items[flag]
    end

    local itemTable
    local realSettings = table.clone(defaultSettings)

    local chamsTable = table.clone(defaultSettings.Chams)
    local chamsProxy = setmetatable({}, {
        __index = chamsTable,
        __newindex = function(_, k, v)
            chamsTable[k] = v
            for _, item in itemTable.List do
                item:updateColors()
            end
        end
    })
    realSettings.Chams = chamsProxy

    local proxy = setmetatable({}, {
        __index = realSettings,
        __newindex = function(_, k, v)
            realSettings[k] = v

            if string.find(k, "Color") or string.find(k, "Transparency") then
                for _, item in itemTable.List do
                    item:updateColors()
                end
            elseif typeof(v) == "boolean" then
                for _, item in itemTable.List do
                    item:updateDrawedItemsVisibility()
                end
            end
        end
    })

    itemTable = setmetatable({
        List = {},
        Settings = proxy
    }, {
        __newindex = function(self, k, v)
            if k == "Enabled" then
                rawset(self, "_Enabled", v)
                for _, item in self.List do
                    if v then
                        item:update(true)
                    else
                        item:hide(true)
                    end
                end
            else
                rawset(self, k, v)
            end
        end,
        __index = function(self, k)
            if k == "Enabled" then
                return rawget(self, "_Enabled")
            end
            return rawget(self, k)
        end
    })

    self.Items[flag] = itemTable
    return itemTable
end

function Library:Enable(state: boolean)
	Library.Enabled = state

	if not state then
		for _, group in Library.Items do
			for _, item in group.List do
				item:hide(true)
			end
		end

		return
	end
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
	local character = player.Character

	local function characterAdded(newCharacter: Model)
		repeat task.wait() until newCharacter.Parent and newCharacter:FindFirstChildWhichIsA("BasePart") or not player.Parent or character ~= newCharacter
		if not player.Parent or character ~= newCharacter then return end

		Library.newItem("Players", newCharacter)
	end

	Connect(player.CharacterAdded, characterAdded)

	if player.Character then
		characterAdded(player.Character)
	end
end

Library.Players = Library:createGroup("Players")

for _, player in Players:GetPlayers() do
	task.spawn(CreatePlayerESP, player)
end

Connect(Players.PlayerAdded, CreatePlayerESP)
Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), newCamera)
task.spawn(newCamera)

return Library
