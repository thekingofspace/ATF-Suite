local Players = game:GetService("Players")

local Prop = require("./Prop")

local HIGHLIGHT_FILL = Color3.fromRGB(0, 170, 255)
local HIGHLIGHT_OUTLINE = Color3.fromRGB(0, 200, 255)
local ROTATION_STEPS = { 15, 90, 180, 360 }

export type Mode = "Move" | "Resize" | "Rotate"
export type SmoothnessKind = "Rotation" | "Scale" | "Position"

export type class = {
    New: (props: Prop.class<any> | { Prop.class<any> }) -> class,

    SetMode: (self: class, mode: Mode) -> class,
    GetMode: (self: class) -> Mode,
    SetSmoothness: (self: class, kind: SmoothnessKind, value: number) -> class,
    Reflow: (self: class) -> (),
    Restore: (self: class) -> (),
    Destroy: (self: class) -> (),

    Container: Model,
    Props: { Prop.class<any> },
    Mode: Mode,
    CanResize: boolean,
    Smoothness: { Rotation: number, Scale: number, Position: number },
}

local Class = {}
Class.__index = Class

local function snap(value: number, increment: number): number
    if increment <= 0 then
        return value
    end
    return math.round(value / increment) * increment
end

local function groupBounds(props: { any }): (CFrame, Vector3)
    local minV: Vector3? = nil
    local maxV: Vector3? = nil
    for _, prop in props do
        local model = prop.Model
        if model then
            local boxCF, boxSize = model:GetBoundingBox()
            local half = boxSize * 0.5
            for x = -1, 1, 2 do
                for y = -1, 1, 2 do
                    for z = -1, 1, 2 do
                        local corner = boxCF * Vector3.new(half.X * x, half.Y * y, half.Z * z)
                        if minV == nil or maxV == nil then
                            minV, maxV = corner, corner
                        else
                            minV, maxV = minV:Min(corner), maxV:Max(corner)
                        end
                    end
                end
            end
        end
    end
    if minV == nil or maxV == nil then
        return CFrame.new(), Vector3.one
    end
    return CFrame.new((minV + maxV) * 0.5), maxV - minV
end

function Class.New(props)
    local list = if (props :: any)[1] ~= nil then (props :: any) else { props }
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    local container = Instance.new("Model")
    container.Name = "PropEditContainer"

    local originals = {}
    for _, prop in list do
        local model = prop.Model
        table.insert(originals, {
            prop = prop,
            model = model,
            parent = if model then model.Parent else workspace,
            cframe = prop.Position,
            scale = prop.Scale,
        })
        if model then
            model.Parent = container
        end
    end

    local boundsCF, boundsSize = groupBounds(list)
    local adornee = Instance.new("Part")
    adornee.Name = "Adornee"
    adornee.Size = boundsSize
    adornee.CFrame = boundsCF
    adornee.Transparency = 1
    adornee.Anchored = true
    adornee.CanCollide = false
    adornee.CanQuery = false
    adornee.CanTouch = false
    adornee.Locked = true
    adornee.Parent = container
    container.PrimaryPart = adornee

    local highlight = Instance.new("Highlight")
    highlight.FillColor = HIGHLIGHT_FILL
    highlight.OutlineColor = HIGHLIGHT_OUTLINE
    highlight.FillTransparency = 0.6
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = container

    container.Parent = workspace

    local moveHandles = Instance.new("Handles")
    moveHandles.Name = "MoveHandles"
    moveHandles.Style = Enum.HandlesStyle.Movement
    moveHandles.Adornee = adornee
    moveHandles.Visible = false
    moveHandles.Parent = playerGui

    local resizeHandles = Instance.new("Handles")
    resizeHandles.Name = "ResizeHandles"
    resizeHandles.Style = Enum.HandlesStyle.Resize
    resizeHandles.Adornee = adornee
    resizeHandles.Visible = false
    resizeHandles.Parent = playerGui

    local arcHandles = Instance.new("ArcHandles")
    arcHandles.Name = "RotateHandles"
    arcHandles.Adornee = adornee
    arcHandles.Visible = false
    arcHandles.Parent = playerGui

    local self = setmetatable({
        Container = container,
        Props = list,
        Mode = "Move" :: Mode,
        CanResize = #list == 1,
        Smoothness = { Rotation = 15, Scale = 0, Position = 0 },

        _adornee = adornee,
        _highlight = highlight,
        _moveHandles = moveHandles,
        _resizeHandles = resizeHandles,
        _arcHandles = arcHandles,
        _originals = originals,
        _connections = {},
    }, Class)

    do
        local startPivot = container:GetPivot()
        table.insert(self._connections, moveHandles.MouseButton1Down:Connect(function()
            startPivot = container:GetPivot()
        end))
        table.insert(self._connections, moveHandles.MouseDrag:Connect(function(face, distance)
            local step = snap(distance, self.Smoothness.Position)
            container:PivotTo(startPivot * CFrame.new(Vector3.FromNormalId(face) * step))
        end))
    end

    do
        local startPivot = container:GetPivot()
        table.insert(self._connections, arcHandles.MouseButton1Down:Connect(function()
            startPivot = container:GetPivot()
        end))
        table.insert(self._connections, arcHandles.MouseDrag:Connect(function(axis, relativeAngle)
            local degrees = snap(math.deg(relativeAngle), self.Smoothness.Rotation)
            container:PivotTo(startPivot * CFrame.fromAxisAngle(Vector3.FromAxis(axis), math.rad(degrees)))
        end))
    end

    do
        local prop = list[1]
        local startScale = 1
        local startSize = adornee.Size
        table.insert(self._connections, resizeHandles.MouseButton1Down:Connect(function()
            startScale = prop.Scale
            startSize = adornee.Size
        end))
        table.insert(self._connections, resizeHandles.MouseDrag:Connect(function(face, distance)
            local axisSize = math.abs(startSize:Dot(Vector3.FromNormalId(face)))
            if axisSize <= 0 then
                return
            end
            prop:SetScale(snap(startScale * (axisSize + distance) / axisSize, self.Smoothness.Scale))
            self._adornee.Size = startSize * (prop.Scale / startScale)
        end))
        table.insert(self._connections, resizeHandles.MouseButton1Up:Connect(function()
            self:Reflow()
        end))
    end

    self:SetMode("Move")
    return self
end

function Class.SetMode(self, mode: Mode)
    if mode == "Resize" and not self.CanResize then
        warn("[ScaleManager] Resize is only available when editing a single prop.")
        return self
    end
    self.Mode = mode
    self._moveHandles.Visible = mode == "Move"
    self._resizeHandles.Visible = mode == "Resize"
    self._arcHandles.Visible = mode == "Rotate"
    return self
end

function Class.GetMode(self)
    return self.Mode
end

function Class.SetSmoothness(self, kind: SmoothnessKind, value: number)
    value = math.max(0, value)
    if kind == "Rotation" then
        local nearest = ROTATION_STEPS[1]
        for _, step in ROTATION_STEPS do
            if math.abs(value - step) < math.abs(value - nearest) then
                nearest = step
            end
        end
        value = nearest
    end
    self.Smoothness[kind] = value
    return self
end

function Class.Reflow(self)
    local boundsCF, boundsSize = groupBounds(self.Props)
    self._adornee.Size = boundsSize
    self._adornee.CFrame = boundsCF
end

function Class.Restore(self)
    for _, entry in self._originals do
        local prop = entry.prop
        local model = entry.model
        if prop and not prop.Destroyed then
            prop:SetScale(entry.scale)
            if model then
                model:PivotTo(entry.cframe)
            end
        end
    end
    self:Reflow()
end

function Class.Destroy(self)
    for _, entry in self._originals do
        local prop = entry.prop
        local model = entry.model
        if prop and model and not prop.Destroyed then
            prop:SetCFrame(model:GetPivot())
        end
    end

    for _, conn in self._connections do
        conn:Disconnect()
    end
    table.clear(self._connections)

    for _, entry in self._originals do
        local model = entry.model
        if model and model.Parent == self.Container then
            model.Parent = entry.parent or workspace
        end
    end

    self._moveHandles:Destroy()
    self._resizeHandles:Destroy()
    self._arcHandles:Destroy()
    self.Container:Destroy()
end

return Class
