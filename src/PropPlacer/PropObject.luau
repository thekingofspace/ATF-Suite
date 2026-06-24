local ServerStorage = game:GetService("ServerStorage")
local prop_real = require("./Prop")
local signal = require("./signal")
export type class<i> = {
    New:(Model:Model, id:string) -> class<i> ,
    id:string,

    Model:Model,
    Importance:number,
    CanScale:boolean, -- whether children may be scaled at all
    MinScale:number, -- lowest Scale a child may take
    MaxScale:number, -- highest Scale a child may take

    RegisterChild:(self:class<i> , Position:CFrame?) -> prop_real.class<any>,
    ChildAdded:signal.Signal< prop_real.class<any> >,
    ChildRemoved:signal.Signal< prop_real.class<any> >,
    GetAbstract:(self:class<i> ) -> {Importance:number, ModelName:string},

    GetStat:<key>(self:class<i>, State:key & keyof<i>) -> index<i, key>,
    SetStat:(self:class<i>, State:keyof<i>, Value:any) -> (),
    SetStats:(self:class<i>, stats:i) -> (),

    FindFirstChild:(self:class<i> , id:string) -> prop_real.class<any>?,
    GetChildren:(self:class<i> ) -> {prop_real.class<any>}
}

local Class = {}
Class.__index = Class

function Class.New(Model:Model, id:string)
    if not Model:IsDescendantOf(ServerStorage) then warn("It is HIGHLY recommended that you keep models in serverstorage for performance and security.") end
    return setmetatable({Model = Model, Importance = 1, CanScale = true, MinScale = 1, MaxScale = 1, Children = {}, ChildAdded = signal.new("Deffered"), ChildRemoved = signal.new("Deffered"), id = id, stats = {}}, Class)
end

function Class.RegisterChild(self:class<any> , Position:CFrame?)
    local ChildClass = prop_real.New(Position, {Original = self.Model:GetScale(), Min = self.MinScale, Max = self.MaxScale, CanScale = self.CanScale}, self.Model.Name, self.Importance)

    ChildClass.Destroying:Once(function(Prop)
        self.Children[Prop.id] = nil
        self.ChildRemoved:Fire(Prop)
    end)
    self.Children[ChildClass.id] = ChildClass
    self.ChildAdded:Fire(ChildClass)
    return ChildClass
end

function Class.GetStat(self:class<any>, State:string)
    return self.stats[State]
end

function Class.SetStat(self:class<any>, State:string, Value:any)
    self.stats[State] = Value
end

function Class.SetStats(self:class<any>, States:any)
    for State:string, value in pairs(States) do
        self.stats[State] = value
    end
end

function Class.GetAbstract(self:class<any>)
    return {Importance = self.Importance, ModelName = self.Model.Name}
end

function Class.FindFirstChild(self:class<any>, id:string)
    return self.Children[id]
end

function Class.GetChildren(self:class<any>)
    local children = {}
    for _, child in pairs(self.Children) do
        table.insert(children, child)
    end
    return children
end

return Class::class<any>