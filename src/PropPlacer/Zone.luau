local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local quick_zone = require("./QuickZone")
local Prop_Real  = require("./Prop")
local Socket = require("./Common_Socket")
local PropCast = require("./PropObject")
local CommonGroup = quick_zone.Group.players()
local Max_Distance = 7000 -- changable if youd like lots of zones (not a good idea)
local Zone_Padding = 16 -- studs of buffer added to every side of a zone, so even a tiny prop gives a roomy, easy-to-enter zone
local Zone_Min_Size = Vector3.new(67.746, 39.88, 74.272) -- a zone is never smaller than this
export type class = {
    New:(Owner:any) -> class,

    Linker:quick_zone.Observer,
    Owner:any, -- owners do not need to exist but they help logically
    GroupID:string, -- used on socket communcation.
    Children:{ Prop_Real.class<any> },
    Listeners:{ Player }, -- used for dynamics
    Zones:{quick_zone.Zone},
    ZoneMembers:{ [number]:{ {Point:Vector3, Half:Vector3} } }, -- object footprints per zone id, used to recalculate room size
    prop_cache:{[PropCast.class<any>]:{Prop_Real.class<any>}},
    GenerateZone:(self:class, Position:CFrame, Size:Vector3) -> quick_zone.Zone,
    SpawnObject:(self:class, Object:PropCast.class<any>, Position:CFrame) -> Prop_Real.class<any>?, -- Fails if player is to far away
    Destroy:(self:class) -> ()
}


local Class = {}
Class.__index = Class

local function GenerateZone(cframe:CFrame, size:Vector3)
    return quick_zone.Zone.new({cframe = cframe, size = size, isDynamic = true})
end

local Zone_Indexes:{[string]:class} = {}
local lastGetProps:{[Player]:{[string]:number}} = {}

Socket:On("GetProps", function(Player:Player, Group:string)
    local now = os.clock()
    local times = lastGetProps[Player]
    if not times then
        times = {}
        lastGetProps[Player] = times
    end
    if( times[Group] and now - times[Group] < 3) or table.find(Zone_Indexes[Group].Listeners, Player) == nil then
        return
    end
    times[Group] = now

    local room = Zone_Indexes[Group]
    if not room then
        return
    end

    local alive = {}
    for _, child in room.Children do
        if not child.Destroyed then
            table.insert(alive, child)
        end
    end

    table.sort(alive, function(a, b) -- most important first
        return a.Importance > b.Importance
    end)

    local props = {}
    for _, child in alive do
        table.insert(props, {
            Id = child.id,
            ModelName = child.ModelName,
            CFrame = child.Position,
            Scale = child.Scale,
            OriginalScale = child.OriginalScale,
            MinScale = child.MinScale,
            MaxScale = child.MaxScale,
            CanScale = child.CanScale,
            Attributes = child:GetAttributes(), -- color etc. the client may need to load
        })
    end

    return props
end)

function Class.New(Owner:SlimAnimationDataEntity)
    local self = setmetatable({prop_cache = {}, Owner = Owner or "NO-OWNER", Zones = {}, Listeners = {}, Children = {}, ZoneMembers = {}, GroupID = HttpService:GenerateGUID(), Linker = quick_zone.Observer.new({groups = {CommonGroup}}) }, Class)
    self.Linker:onPlayerEntered(function(player)
        table.insert(self.Listeners, player)
        Socket:JoinRoom(player, self.GroupID)
        Socket:EmitTo(player, "Entered_Room", self.GroupID, self.Owner == player)
    end)
    self.Linker:onPlayerExited(function(player)
        local index = table.find(self.Listeners, player)
        if index then
            table.remove(self.Listeners, index)
        end
        Socket:LeaveRoom(player, self.GroupID)
        Socket:EmitTo(player, "ExitedRoom", self.GroupID)
    end)
    Zone_Indexes[self.GroupID] = self
    return self
end

function Class.GenerateZone(self:class, Position:CFrame, Size:Vector3)
    local point = Position.Position

    for _, zone in ipairs(self.Zones) do
        if zone:isPointInside(point) then
            return zone
        end

        local currentCFrame = zone:getCFrame()
        local center = currentCFrame.Position

        if (center - point).Magnitude <= Max_Distance then -- within range: grow the zone to a tight box around old + new
            local currentSize = zone:getSize()
            local half = currentSize * 0.5
            local objectHalf = Size * 0.5

            local mergedMin = (center - half):Min(point - objectHalf)
            local mergedMax = (center + half):Max(point + objectHalf)

            local mergedSize = mergedMax - mergedMin
            local mergedCenter = (mergedMin + mergedMax) * 0.5

            if mergedSize ~= currentSize then
                zone:setSize(mergedSize)
            end
            if mergedCenter ~= center then
                zone:setCFrame(currentCFrame.Rotation + mergedCenter)
            end

            return zone
        end
    end

    local zone = GenerateZone(Position, Size)
    zone:attach(self.Linker)
    table.insert(self.Zones, zone)
    return zone
end

local function recalculateZone(self:class, zone:quick_zone.Zone, zoneId:number)
    local members = self.ZoneMembers[zoneId]

    if not members or #members == 0 then -- room is empty, it no longer exists
        self.ZoneMembers[zoneId] = nil
        local index = table.find(self.Zones, zone)
        if index then
            table.remove(self.Zones, index)
        end
        zone:destroy()
        return
    end

    local mergedMin = members[1].Point - members[1].Half
    local mergedMax = members[1].Point + members[1].Half
    for i = 2, #members do
        local member = members[i]
        mergedMin = mergedMin:Min(member.Point - member.Half)
        mergedMax = mergedMax:Max(member.Point + member.Half)
    end

    local mergedCenter = (mergedMin + mergedMax) * 0.5
    local mergedSize = ((mergedMax - mergedMin) + Vector3.one * (Zone_Padding * 2)):Max(Zone_Min_Size) -- pad every side, then floor at the minimum size (center stays put)
    local currentCFrame = zone:getCFrame()

    if mergedSize ~= zone:getSize() then
        zone:setSize(mergedSize)
    end
    if mergedCenter ~= currentCFrame.Position then
        zone:setCFrame(currentCFrame.Rotation + mergedCenter)
    end
end

function Class.SpawnObject(self:class, Object:PropCast.class<any>, Position:CFrame)
    local model = Object.Model
    if not model then
        return nil
    end
    self.prop_cache[Object] = self.prop_cache[Object] or {}

    local size = model:GetExtentsSize()
    local zone = self:GenerateZone(Position, size)
    local zoneId = zone:getId()

    local members = self.ZoneMembers[zoneId]
    if not members then
        members = {}
        self.ZoneMembers[zoneId] = members
    end
    local member = {Point = Position.Position, Half = size * 0.5}
    table.insert(members, member)
    recalculateZone(self, zone, zoneId) -- grow the room if this model is bigger than the current bounds

    local child = Object:RegisterChild(Position)

    child.Destroying:Once(function(prop)
        local list = self.ZoneMembers[zoneId]
        if list then
            local index = table.find(list, member)
            if index then
                table.remove(list, index)
            end
            recalculateZone(self, zone, zoneId) -- shrink (or remove) the room to fit what is left
        end

        local childIndex = table.find(self.Children, child)
        if childIndex then
            table.remove(self.Children, childIndex)
        end

        Socket:BroadcastToRoom(self.GroupID, "Prop_Removed", self.GroupID, prop.id)
        local index = table.find(self.prop_cache[Object], prop)
        if index then
            table.remove(self.prop_cache[Object], index)
        end
    end)
    child.Changed:Connect(function(propery:string, value:any)
        if propery == "Position" then
            member.Point = value.Position -- track the prop's new location...
            recalculateZone(self, zone, zoneId) -- ...and resize the room to fit it
            Socket:BroadcastToRoom(self.GroupID, "Prop_Moved", self.GroupID, child.id, value)
        elseif propery == "Scale" then
            Socket:BroadcastToRoom(self.GroupID, "Prop_Scaled", self.GroupID, child.id, child.OriginalScale * value) -- send the absolute scale (baseline * multiplier)
        end
    end)
    child.AttributeChanged:Connect(function(name:string, value:any)
        if #self.Listeners == 0 then
            return -- nobody is in the zone; the relay is room-scoped like every other update
        end
        Socket:BroadcastToRoom(self.GroupID, "Prop_Attribute", self.GroupID, child.id, name, value)
    end)
    table.insert(self.Children, child)

    Socket:BroadcastToRoom(self.GroupID, "Prop_Placed", self.GroupID, {
        Id = child.id,
        ModelName = child.ModelName,
        CFrame = Position,
        Scale = child.Scale,
        OriginalScale = child.OriginalScale,
        MinScale = child.MinScale,
        MaxScale = child.MaxScale,
        CanScale = child.CanScale,
        Attributes = child:GetAttributes(),
    })
    table.insert(self.prop_cache[Object], child)
    return child
end

function Class.Destroy(self:class)
    for _, item in ipairs(self.Children) do
        item:Destroy()
    end
    for _, item in ipairs(self.Listeners) do
        Socket:EmitTo(item, self.GroupID, "ExitedRoom", self.GroupID)
        Socket:LeaveRoom(item, self.GroupID)
    end
    for _, item in ipairs(self.Zones) do
        item:destroy()
    end
    self.Linker:destroy()
    table.clear(self.Zones)
    table.clear(self.Listeners)
    table.clear(self.prop_cache)
end

Players.PlayerRemoving:Connect(function(player)
    for _, item in pairs(Zone_Indexes) do
        local index = table.find(item.Listeners, player)
        if index then
            Socket:LeaveRoom(player, item.GroupID)
            table.remove(item.Listeners, index)
            lastGetProps[player] = nil
        end
    end
end)

return Class::class