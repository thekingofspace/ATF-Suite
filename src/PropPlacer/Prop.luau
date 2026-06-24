local HttpService = game:GetService("HttpService")
local signal = require("./signal")
--[[
    why attributes:
        So the reason I used attributes is for props that hold data.
        this means you dont need external tables with ID lookups for attributes and it avoids the issue of memory leaks
]]

export type class<i> = {
    New:(Position:CFrame?, Scaling:{Original:number?, Min:number?, Max:number?, CanScale:boolean?}?, ModelName:string?, Importance:number?, Model:Model?) -> class<i>,

    SetAttribute:(self:class<i>, Attribute:keyof<i>, value:any) -> (),
    GetAttribute:<key>(self:class<i>, Attribute:key & keyof<i>) -> index<i, key>,
    GetAttributeChanged:(self:class<i>, Attribute:keyof<i>) -> signal.Signal<any>,
    GetAttributes:(self:class<i>) -> i,
    SetAttributes:(self:class<i>, Attributes:i & any) -> (),
    SetScale:(self:class<i>, scale:number) -> (),
    SetCFrame:(self:class<i>, cframe:CFrame) -> (),

    Destroy:(self:class<i>) -> (),

    id:string,
    Position:CFrame,
    ModelName:string, -- name of the source model, copied from the spawning object
    Importance:number, -- copied from the spawning object; used for ordering
    Scale:number, -- current multiplier on the model's original scale (1 == original)
    OriginalScale:number, -- the model's scale at creation, treated as Scale 1
    MinScale:number, -- lowest Scale the source object allows
    MaxScale:number, -- highest Scale the source object allows
    CanScale:boolean, -- when false, Scale is locked at 1
    Destroyed:boolean,
    Destroying:signal.Signal<class<i>>,
    Changed:signal.Signal<string, any>,
    AttributeChanged:signal.Signal<string, any>, -- (name, value) on any SetAttribute
    Model:Model?
}

local Class = {}
Class.__index = Class
local ReservedFields = {
    "SetAttribute",
    "GetAttribute",
    "GetAttributeChanged",
    "GetAttributes",
    "Changed",
    "Destroying",
    "Id",
    "New",
    "Destroy",
    "SetScale",
    "SetCFrame"
}
Class.__newindex = function(self:class<any>, property:string, value:any)
    if table.find(ReservedFields, property) then error(`Field {property} is locked and can not be changed`) end
    if property ~= "Destroyed" then
        self.Changed:Fire(property, value)
    end
    rawset(self, property, value)
end

function Class.New(Position:CFrame?, Scaling:{Original:number?, Min:number?, Max:number?, CanScale:boolean?}?, ModelName:string?, Importance:number?, Model:Model?)
    Scaling = Scaling or {}

    local self = setmetatable({
        id = HttpService:GenerateGUID(),
        Attributes = {},
        AttSignal = {},

        Position = Position or CFrame.new(),
        Scale = 1,
        OriginalScale = if Model then Model:GetScale() else (Scaling.Original or 1), -- a real model's current scale IS the baseline (Scale 1)
        MinScale = Scaling.Min or 1,
        MaxScale = Scaling.Max or 1,
        CanScale = if Scaling.CanScale == nil then true else Scaling.CanScale,

        Model = Model,
        ModelName = ModelName or "",
        Importance = Importance or 1,

        Destroyed = false,
        Destroying = signal.new("Serial"),
        Changed = signal.new("Deffered"),
        AttributeChanged = signal.new("Deffered"),
    }, Class)

    if Model then -- sync the model to the prop's starting transform
        Model:PivotTo(self.Position)
        Model:ScaleTo(self.OriginalScale * self.Scale)
    end

    return self
end

function Class.SetAttribute(self:class<any>, Attribute:string, Value:any)
    if self.Destroyed == true then error(`Object {self.Id} is already destroyed`) end
    if self.Attributes[Attribute] == Value then return end
    local Sig:(signal.Signal<>)? = self.AttSignal[Attribute]
    self.Attributes[Attribute] = Value
    if Sig then
        Sig:Fire(Value)
    end
    self.AttributeChanged:Fire(Attribute, Value)
end

function Class.GetAttribute(self:class<any>, Attribute:string)
    return self.Attributes[Attribute]
end

function Class.GetAttributes(self:class<any>)
    return self.Attributes
end

function Class.GetAttributeChanged(self:class<any>, Attribute:string)
    if self.Destroyed == true then error(`Object {self.Id} is already destroyed`) end
    local SignalInput:(signal.Signal<>)? = self.AttSignal[Attribute]
    if not SignalInput then
        SignalInput = signal.new("Deffered")
        self.AttSignal[Attribute] = SignalInput
    end
    return SignalInput
end

function Class.SetAttributes(self:class<any>, Attributes:{[string]:any})
    for key, item in pairs(Attributes) do
        self.Attributes[key] = item
        local sig:(signal.Signal<>)? = self.AttSignal[key]
        if sig then
            sig:Fire(item)
        end
        self.AttributeChanged:Fire(key, item)
    end
end

function Class.SetScale(self:class<any>, scale:number)
    if self.Destroyed == true then error(`Object {self.Id} is already destroyed`) end
    local lower = self.CanScale and self.MinScale or 1
    local upper = self.CanScale and self.MaxScale or 1
    scale = math.clamp(scale, lower, upper)
    if self.Scale == scale then return end
    rawset(self, "Scale", scale) -- bypass __newindex (Scale is pre-initialised) and fire Changed manually
    if self.Model then
        self.Model:ScaleTo(self.OriginalScale * scale) -- absolute scale = baseline * multiplier
    end
    self.Changed:Fire("Scale", scale)
end

function Class.SetCFrame(self:class<any>, cframe:CFrame)
    if self.Destroyed == true then error(`Object {self.Id} is already destroyed`) end
    if self.Position == cframe then return end
    rawset(self, "Position", cframe) -- bypass __newindex (Position is pre-initialised) and fire Changed manually
    if self.Model then
        self.Model:PivotTo(cframe)
    end
    self.Changed:Fire("Position", cframe)
end

function Class.Destroy(self:class<any>)
    if self.Destroyed == true then error(`Object {self.Id} is already destroyed`) end
    self.Destroyed = true
    for _, item:signal.Signal<> in pairs(self.AttSignal) do
        item:Destroy()
    end
    table.clear(self.AttSignal)

    self.Destroying:Fire(self)
    self.Changed:Destroy()
    self.AttributeChanged:Destroy()
    self.Destroying:Destroy()
    if self.Model then
        self.Model:Destroy()
        self.Model = nil
    end
end

return Class::class<any>
