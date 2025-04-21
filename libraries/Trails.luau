local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local module = {}

local Terrain = workspace.Terrain

local function createAttachment(cf: CFrame): Attachment
    local attachment = Instance.new("Attachment")
    attachment.WorldCFrame = cf
    attachment.Parent = Terrain
    return attachment
end

local function create(instanceName, properties)
    local part = Instance.new(instanceName)

    for name, value in properties do
        part[name] = value
    end

    return part
end

local Effects = {
    ["Light Beam"] = function(origin: Attachment, destination: Attachment, fadeTime: number, color: Color3)
        local startPoint, destPoint = origin.WorldCFrame.Position, destination.WorldCFrame.Position

        local Distance = (startPoint - destPoint).Magnitude

        local bulletTracer = create("Part", {
            CanCollide = false,
            CanQuery = false,
            Anchored = true,
            Material = Enum.Material.Neon,
            Name = 'Tracer',
            CFrame = CFrame.lookAt(startPoint, destPoint) * CFrame.new(0, 0, -Distance / 2),
            Color = color,
            Size = Vector3.new(0.04, 0.04, Distance),
            Parent = Terrain,
        })

        local light = create("PointLight", {
            Shadows = true,
            Brightness = 0.5,
            Range = 15,
            Parent = origin,
        })

        Debris:AddItem(light, 0.35)

        local tween = TweenService:Create(
            bulletTracer,
            TweenInfo.new(fadeTime or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 1,
                Color = Color3.fromRGB(140, 140, 140)
            }
        )

        TweenService:Create(light, TweenInfo.new(0.2), {Brightness = 0}):Play()
        tween:Play()

        tween.Completed:Wait()
        bulletTracer:Destroy()
    end
}

function module.new(
    from: Vector3,
    to: Vector3,
    effect: "Lighting" | "Light Beam",
    fadeTime: number?,
    color: Color3
)

    local fromAtt = createAttachment(CFrame.new(from,to))
    local toAtt = createAttachment(CFrame.new(to, from))

    Effects[effect](fromAtt, toAtt, fadeTime, color)

    fromAtt:Destroy()
    toAtt:Destroy()
end


return module
