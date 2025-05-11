--Author: @.desespoire | https://v3rm.net/members/001.1198/
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
	HealthBarMode = "Filled", -- Filled / Gradient
	HealthBarGradient = false,
	HealthBarDisplayMode = "Left",

	ShowBox = false,
	BoxMode = "Full", -- Full / Corner

	ShowTracer = false,
	TracerMode = "Bottom", -- Mouse / Bottom / Top / Center

	ShowWeapon = false,

	Color = Color3.fromRGB(255, 255, 255),
	NameColor = Color3.fromRGB(255, 255, 255),
	DistanceColor = Color3.fromRGB(255, 255, 255),
	BoxColor = Color3.fromRGB(255, 255, 255),
	TracerColor = Color3.fromRGB(255, 255, 255),
	WeaponColor = Color3.fromRGB(255, 255, 255),

	PrimaryHealthColor = Color3.fromRGB(0, 255, 0),
	SecondaryHealthColor = Color3.fromRGB(255, 0, 0),

	HealthGradientTopColor = Color3.fromRGB(0, 255, 0),
	HealthGradientBottomColor = Color3.fromRGB(255, 0, 0),

	VisibleOnly = false,
	AliveOnly = false,
	TeamCheck = false,
	ShowTeam = false,

	ChamsEnabled = false,
	Chams = {
		Occluded = true,

		OutlineColor = Color3.fromRGB(255, 255, 255),
		FillColor = Color3.fromRGB(255, 255, 255),

		OutlineTransparency = 0,
		FillTransparency = 100,
	},

	MaxDistance = 9e9,
}

local Library = {
	Items = {},

	Players = {}, -- Created later
	Connections = {},

	Enabled = true,

	FontSize = 11,
	Font = Enum.Font.BuilderSansMedium,

	TracerMode = defaultSettings.TracerMode,
	tracerOrigin = Vector2.zero,

	CurrentTeam = nil,
	CustomRootPart = nil,
}

local Item = {}
Item.__index = Item

local REFRESH_RATE = 1 / 120
local ScreenGui

local clamp = math.clamp
local floor = math.floor

local function DistanceFromCharacter(from)
	if Library.CustomRootPart then
		return (from - Library.CustomRootPart.Position).Magnitude
	else
		return LocalPlayer:DistanceFromCharacter(from)
	end
end

local function Connect(signal, fn)
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

local function Create(className, config)
	local instance = Instance.new(className)
	config = config or {}

	if className == "ScreenGui" then
		local getUi = get_hidden_gui or gethui or function() return CoreGui end
		local protectGUi = protectgui or gethui or get_hidden_gui or (function() end)
		protectGUi(instance)

		config.Parent = getUi()
	elseif className == "UIGradient" or className == "UIStroke" or className == "Highlight" then
		config.Enabled = false
	else
		config.Visible = false
	end

	if not config.Parent then
		--awp breaks breaks the highlight renders in gethui
		config.Parent = ScreenGui
	end

	if className == "TextLabel" then
		config.TextColor3 = Color3.fromRGB(255, 255, 255)
		config.Font = Library.Font
		config.TextSize = Library.FontSize
		config.TextStrokeTransparency = 0
		config.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		config.RichText = true
		config.Size = UDim2.new(0, 100, 0, 20)
		config.AnchorPoint = Vector2.new(0.5, 0.5)
		config.Visible = false
		config.BackgroundTransparency = 1
	elseif className == "Frame" then
		config.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		config.Visible = false
	end

	for k, v in pairs(config) do
		if k == "Occluded" then
			continue
		end

		instance[k] = v
	end

	return instance
end

local function GetTracerOrigin()
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

local function IsInRange(point, range)
	local distance = DistanceFromCharacter(point)

	if distance == 0 then
		return false
	end

	return distance <= range
end

function Item.new(flag, object)
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
			self:hide()
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
	self:hide()

	childUpdate()

	if Library.Items[self.flag].Enabled then
		self:updateDrawedItemsVisibility()
		self:update(true)
	end

	return self
end

function Item:getSettings()
	return Library.Items[self.flag].Settings
end

function Item:init()
	local drawing = {
		NameLabel = Create("TextLabel"),

		DistanceText = Create("TextLabel"),

		HealthBar = Create("Frame"),

		Box = Create("Frame", { BackgroundTransparency = 1}),

		BoxLeftTop = Create("Frame"),
		BoxLeftSide = Create("Frame"),
		BoxRightTop = Create("Frame"),
		BoxRightSide = Create("Frame"),
		BoxBottomSide = Create("Frame"),
		BoxBottomDown = Create("Frame"),
		BoxBottomRightSide = Create("Frame"),
		BoxBottomRightDown = Create("Frame"),

		Tracer = Create("Frame"),

		WeaponLabel = Create("TextLabel"),
	}

	drawing.HealthBarFiller = Create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Parent = drawing.HealthBar })
	drawing.HealthBarOutline = Create("UIStroke", { Parent = drawing.HealthBar })
	drawing.HealthBarGradient = Create("UIGradient", { Rotation = -90, Parent = drawing.HealthBar })
	drawing.BoxStroke = Create("UIStroke", { Enabled = false, Parent = drawing.Box })

	self.Highlight = Create("Highlight", defaultSettings.Chams)
	self.Drawing = drawing
end

function Item:hide()
	if self.hidden then return end
	self.hidden = true

	for _, elem in self.Drawing do
		if elem.ClassName == "UIGradient" or elem.ClassName == "UIStroke" then
			elem.Enabled = false
			continue
		end

		elem.Visible = false
	end

	if self._objectMoved then self._objectMoved:Disconnect() end
	if self._healthChanged then self._healthChanged:Disconnect() end

	self.Highlight.Parent = nil
	self.Highlight.Enabled = false
end

function Item:_trackMovements()
	if self._objectMoved then
		self._objectMoved:Disconnect()
		self._objectMoved = nil
	end

	if not self.rootPart then
		return
	end

	local oldCFrame = nil
	local lastUpdate = 0

	self._healthChanged = RunService.Stepped:Connect(function(steppedTime)
		if self.hidden or steppedTime - lastUpdate < REFRESH_RATE then return end
		lastUpdate = steppedTime

		local newCFrame = self.rootPart.CFrame

		if oldCFrame ~= newCFrame then
			oldCFrame = newCFrame
			self:update()
		end
	end)

	-- self._objectMoved = self.rootPart:GetPropertyChangedSignal("CFrame"):Connect(function()
	-- 	if self.hidden then return end
	-- 	self:update()
	-- end)
end

function Item:_trackHealth()
	if self._healthChanged then
		self._healthChanged:Disconnect()
		self._healthChanged = nil
	end

	local humanoid = self.humanoid
	if not humanoid then return end

	local function update()
		self.currentHp = clamp(humanoid.Health / (humanoid.MaxHealth or 100), 0, 1)
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

function Item:isVisible()
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

function Item:update(forcedUpdate)
	local now = os.clock()

	if not forcedUpdate and now - self._lastUpdate < REFRESH_RATE then return end
	self._lastUpdate = now

	if not self.object:IsDescendantOf(game) or not self.rootPart then return self:hide() end

	local config = self:getSettings()
	local draw = self.Drawing
	local pos = self.rootPart.Position

	if config.MaxDistance and not IsInRange(pos, config.MaxDistance) then return self:hide() end

	local boundCFrame, modelSize = self.object:GetBoundingBox()
	local modelSizeY = Vector3.new(0, modelSize.Y / 2, 0)
	local modelPos = boundCFrame.Position

	local top, topVisible = CurrentCamera:WorldToViewportPoint(modelPos + modelSizeY)
	local bottom, bottomVisible = CurrentCamera:WorldToViewportPoint(modelPos - modelSizeY)
	local onScreen = topVisible or bottomVisible

	if not onScreen then return self:hide() end

	if config.VisibleOnly and not self:isVisible()
		or config.AliveOnly and self.humanoid and self.humanoid.Health <= 0
	then
		return self:hide()
	end

	if self.player and config.TeamCheck and not config.ShowTeam then
		if self.player.Team == (Library.CurrentTeam or LocalPlayer.Team) then return self:hide() end
	end

	if self.hidden then
		self.hidden = false
		self:updateDrawedItemsVisibility()
		self:_trackHealth()
		self:_trackMovements()
	end

	self:updateChams()

	local boxHeight = bottom.Y - top.Y
	local boxWidth = boxHeight / 2
	local topLeft = Vector2.new(top.X - boxWidth / 2, top.Y)

	local topLeftX, topLeftY = topLeft.X, topLeft.Y

	local topLeftXPlusWidth = topLeftX + boxWidth
	local topLeftYPlusHeight = topLeftY + boxHeight

	if config.ShowBox then
		if config.BoxMode == "Full" then
			draw.Box.Position = UDim2.fromOffset(topLeftX, topLeftY)
			draw.Box.Size = UDim2.fromOffset(boxWidth, boxHeight)
		else
			draw.BoxLeftTop.Position = UDim2.fromOffset(topLeftX, topLeftY)
			draw.BoxLeftTop.Size = UDim2.fromOffset(boxWidth / 5, 1)

			draw.BoxLeftSide.Position = UDim2.fromOffset(topLeftX, topLeftY)
			draw.BoxLeftSide.Size = UDim2.fromOffset(1, boxHeight / 5)

			draw.BoxRightTop.Position = UDim2.fromOffset(topLeftXPlusWidth, topLeftY)
			draw.BoxRightTop.Size = UDim2.fromOffset(boxWidth / 5, 1)
			draw.BoxRightTop.AnchorPoint = Vector2.new(1, 0)

			draw.BoxRightSide.Position = UDim2.fromOffset(topLeftXPlusWidth - 1, topLeftY)
			draw.BoxRightSide.Size = UDim2.fromOffset(1, boxHeight / 5)

			draw.BoxBottomSide.Position = UDim2.fromOffset(topLeftX, topLeftYPlusHeight)
			draw.BoxBottomSide.Size = UDim2.fromOffset(1, boxHeight / 5)
			draw.BoxBottomSide.AnchorPoint = Vector2.new(0, 1)

			draw.BoxBottomDown.Position = UDim2.fromOffset(topLeftX, topLeftYPlusHeight)
			draw.BoxBottomDown.Size = UDim2.fromOffset(boxWidth / 5, 1)
			draw.BoxBottomDown.AnchorPoint = Vector2.new(0, 1)

			draw.BoxBottomRightSide.Position = UDim2.fromOffset(topLeftXPlusWidth, topLeftYPlusHeight)
			draw.BoxBottomRightSide.Size = UDim2.fromOffset(1, boxHeight / 5)
			draw.BoxBottomRightSide.AnchorPoint = Vector2.new(1, 1)

			draw.BoxBottomRightDown.Position = UDim2.fromOffset(topLeftXPlusWidth, topLeftYPlusHeight)
			draw.BoxBottomRightDown.Size = UDim2.fromOffset(boxWidth / 5, 1)
			draw.BoxBottomRightDown.AnchorPoint = Vector2.new(1, 1)
		end
	end

	if config.ShowName then
		draw.NameLabel.Position = UDim2.fromOffset(top.X, top.Y - 16)
		draw.NameLabel.Text = self.object.Name
	end

	if config.ShowDistance then
		draw.DistanceText.Position = UDim2.fromOffset(top.X, bottom.Y + 5)
		draw.DistanceText.Text = string.format("%d Studs", floor(
			DistanceFromCharacter(pos)
		))
	end

	if config.ShowHealth and self.humanoid then
		local topColor, botColor = config.HealthGradientTopColor, config.HealthGradientBottomColor
		local healthPercentage = self.currentHp
		local thickness = 2.5

		if config.HealthBarDisplayMode == "Left" then
			draw.HealthBar.Position = UDim2.fromOffset(topLeftX - 6, topLeftY)
			draw.HealthBar.Size = UDim2.fromOffset(thickness, boxHeight)
			draw.HealthBarFiller.Size = UDim2.fromScale(1, healthPercentage)
		elseif config.HealthBarDisplayMode == "Right" then
			draw.HealthBar.Position = UDim2.fromOffset(topLeftXPlusWidth + 3, topLeftY)
			draw.HealthBar.Size = UDim2.fromOffset(thickness, boxHeight)
			draw.HealthBarFiller.Size = UDim2.fromScale(1, healthPercentage)
		elseif config.HealthBarDisplayMode == "Bottom" then
			draw.HealthBar.Position = UDim2.fromOffset(topLeftX, topLeftYPlusHeight + 3)
			draw.HealthBar.Size = UDim2.fromOffset(boxWidth, thickness)
			draw.HealthBarFiller.Size = UDim2.fromScale(healthPercentage, 1)
		elseif config.HealthBarDisplayMode == "Top" then
			draw.HealthBar.Position = UDim2.fromOffset(topLeftX, topLeftY - 5)
			draw.HealthBar.Size = UDim2.fromOffset(boxWidth, thickness)
			draw.HealthBarFiller.Size = UDim2.fromScale(healthPercentage, 1)
		end

		if config.HealthBarMode == "Gradient" then
			draw.HealthBarGradient.Color =
				healthPercentage == 1 and ColorSequence.new({ ColorSequenceKeypoint.new(0, topColor), ColorSequenceKeypoint.new(1, topColor)})
				or healthPercentage == 0 and ColorSequence.new({ ColorSequenceKeypoint.new(0, botColor), ColorSequenceKeypoint.new(1, botColor)})
				or ColorSequence.new({
					ColorSequenceKeypoint.new(0, topColor),
					-- ColorSequenceKeypoint.new(healthPercentage, topColor:Lerp(botColor, healthPercentage)),
					ColorSequenceKeypoint.new(clamp( healthPercentage - healthPercentage / 2, 0, 1), topColor),
					ColorSequenceKeypoint.new(clamp( healthPercentage + healthPercentage / 2, 0, 1), botColor),
					ColorSequenceKeypoint.new(1, botColor)
				})

		end
	end

	-- if config.ShowTracer then
	-- 	local origin = Library.tracerOrigin
	-- 	local bottom2D = Vector2.new(bottom.X, bottom.Y)

	-- 	local delta = bottom2D - origin
	-- 	local length = delta.Magnitude
	-- 	local angle = math.deg(math.atan2(delta.Y, delta.X)) + 90

	-- 	draw.Tracer.Position = UDim2.fromOffset(origin.X, origin.Y)
	-- 	draw.Tracer.Size = UDim2.fromOffset(2, length)
	-- 	draw.Tracer.Rotation = angle
	-- end

	if config.ShowWeapon and self.player then
		local tool = self.weapon or self.player.Character and self.player.Character:FindFirstChildOfClass("Tool")
		draw.WeaponLabel.Text = tool and tool.Name or "None"
		draw.WeaponLabel.Position = UDim2.fromOffset(top.X, bottom.Y + 20)
	end
end

function Item:updateDrawedItemsVisibility()
	if self.hidden or not Library.Items[self.flag].Enabled then return end

	local draw = self.Drawing
	local config = self:getSettings()

	local showingBox = config.ShowBox

	draw.NameLabel.Visible = config.ShowName
	draw.DistanceText.Visible = config.ShowDistance
	draw.WeaponLabel.Visible = config.ShowWeapon

	draw.Box.Visible = showingBox and config.BoxMode == "Full"
	draw.BoxStroke.Enabled = showingBox and config.BoxMode == "Full"

	local healthBarMode = config.HealthBarDisplayMode
	draw.HealthBarFiller.AnchorPoint =
		((healthBarMode == "Left" or healthBarMode == "Right") and Vector2.new(0.5, 1)) or
		Vector2.new(0, 0.5)

	draw.HealthBarFiller.Position =
		(healthBarMode == "Left" or healthBarMode == "Right") and UDim2.fromScale(0.5, 1)
		or UDim2.fromScale(0, 0.5)

	draw.HealthBar.BackgroundColor3 = config.HealthBarMode == "Gradient" and Color3.fromRGB(255, 255, 255) or config.SecondaryHealthColor

	local showCorner = showingBox and config.BoxMode == "Corner"
	draw.BoxLeftTop.Visible = showCorner
	draw.BoxLeftSide.Visible = showCorner
	draw.BoxRightTop.Visible = showCorner
	draw.BoxRightSide.Visible = showCorner
	draw.BoxBottomSide.Visible = showCorner
	draw.BoxBottomDown.Visible = showCorner
	draw.BoxBottomRightSide.Visible = showCorner
	draw.BoxBottomRightDown.Visible = showCorner

	draw.Tracer.Visible = config.ShowTracer
	draw.HealthBar.Visible = config.ShowHealth
	draw.HealthBarFiller.Visible = config.ShowHealth and config.HealthBarMode == "Filled"

	draw.HealthBarOutline.Enabled = config.ShowHealth
	draw.HealthBarGradient.Enabled = config.ShowHealth and config.HealthBarMode == "Gradient"


	self.Highlight.DepthMode = (self.hidden or config.Occluded) and Enum.HighlightDepthMode.Occluded
			or Enum.HighlightDepthMode.AlwaysOnTop


	self.Highlight.Parent = self.object
	self.Highlight.Enabled = config.ChamsEnabled
end

function Item:updateColors()
	local config = self:getSettings()
	local highlightConfig = config.Chams

	local draw = self.Drawing
	local highlight = self.Highlight

	draw.NameLabel.TextColor3 = config.NameColor
	draw.DistanceText.TextColor3 = config.DistanceColor

	draw.Tracer.BackgroundColor3 = config.TracerColor
	draw.WeaponLabel.TextColor3 = config.WeaponColor

	draw.Box.BackgroundColor3 = config.BoxColor
	draw.BoxStroke.Color = config.BoxColor
	draw.BoxLeftTop.BackgroundColor3 = config.BoxColor
	draw.BoxLeftSide.BackgroundColor3 = config.BoxColor
	draw.BoxRightTop.BackgroundColor3 = config.BoxColor
	draw.BoxRightSide.BackgroundColor3 = config.BoxColor
	draw.BoxBottomSide.BackgroundColor3 = config.BoxColor
	draw.BoxBottomDown.BackgroundColor3 = config.BoxColor
	draw.BoxBottomRightSide.BackgroundColor3 = config.BoxColor
	draw.BoxBottomRightDown.BackgroundColor3 = config.BoxColor

	draw.HealthBar.BackgroundColor3 = config.HealthBarMode == "Gradient" and Color3.fromRGB(255, 255, 255) or config.SecondaryHealthColor
	draw.HealthBarFiller.BackgroundColor3 = config.PrimaryHealthColor

	highlight.OutlineColor = highlightConfig.OutlineColor
	highlight.FillColor = highlightConfig.FillColor

	highlight.OutlineTransparency = 1 - highlightConfig.OutlineTransparency / 100
	highlight.FillTransparency = 1 - highlightConfig.FillTransparency / 100
end

function Item:updateChams()
	if not self.rootPart then return end

	local config = self:getSettings()

	self.Highlight.Adornee = self.object
	self.Highlight.Enabled = config.ChamsEnabled
end

function Item:Destroy()
	for _, item in self.Drawing do
		item:Destroy()
	end

	self.Highlight:Destroy()

	if self._ancestryChanged then self._ancestryChanged:Disconnect() end
	if self.con2 then self.con2:Disconnect() end
	if self.con3 then self.con3:Disconnect() end
	if self.con4 then self.con4:Disconnect() end

	local itemList = Library.Items[self.flag].List
	local index = table.find(itemList, self)
	assert(index, "INDEX NOT FOUND IN LIBRARRY")
	table.remove(itemList, index)
end
--

function Update()
	if not Library.Enabled then return end

	-- Library.tracerOrigin = GetTracerOrigin()

	for _, group in Library.Items do
		for _, item in group.List do
			if not group.Enabled then continue end
			item:update()
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
            elseif typeof(v) == "boolean" or typeof(v) == "string" then
                for _, item in itemTable.List do
                    item:updateDrawedItemsVisibility()
					item:update(true)
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
                    if v and Library.Enabled then
                        item:update(true)
                    else
                        item:hide()
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

	for _, group in Library.Items do
		for _, item in group.List do
			if state and group.Enabled then
				item:update(true)
			else
				item:hide()
			end
		end
	end
end

function Library:Destroy()
	Library.Enabled = false

	for _, group in Library.Items do
		group.Enabled = false

		for _, item in group.List do
			item:hide()
			item:Destroy()
		end
	end

	for _, con in self.Connections do
		con:Disconnect()
	end

	ScreenGui:Destroy()
end
--

local function CreatePlayerESP(player: Player)
	if player == LocalPlayer then return end
	local character = nil

	local function characterAdded(newCharacter: Model)
		repeat task.wait() until newCharacter.Parent and newCharacter:FindFirstChildWhichIsA("BasePart") or not player.Parent or character ~= newCharacter
		if not player.Parent then return end

		Library.newItem("Players", newCharacter)
	end

	Connect(player.CharacterAdded, characterAdded)

	if player.Character then
		characterAdded(player.Character)
	end
end

Library.Players = Library:createGroup("Players")
ScreenGui = Create("ScreenGui", { Parent = CoreGui, DisplayOrder = 99999, ClipToDeviceSafeArea = false, IgnoreGuiInset = true, ResetOnSpawn = false, })

for _, player in Players:GetPlayers() do
	task.spawn(CreatePlayerESP, player)
end

Connect(Players.PlayerAdded, CreatePlayerESP)
Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), newCamera)
task.spawn(newCamera)

return Library
