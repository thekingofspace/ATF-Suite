local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local module = {}

local zone = require("@self/Zone")
local Socket = require("@self/Common_Socket")
local PropObject = require(script.PropObject)
local Replication = require("./PropPlacer/ReplicationPP")
local signal = require("./PropPlacer/signal")

local Rooms: { [string]: zone.class } = {}
local Props: { [string]: PropObject.class<any> } = {}
local PropsByModel: { [string]: PropObject.class<any> } = {}
local PlayerRooms: { [Player]: zone.class } = {}
local PlaceCooldown: { [Player]: number } = {}
local PLACE_COOLDOWN_PER = 0.5
local PLACE_COOLDOWN_MAX = 7

module.PropObject = PropObject

module.PropPlaced = signal.new("Serial")
module.PropUpdated = signal.new("Serial")
module.PropRemoved = signal.new("Serial")

function module.RegisterProp(Object: PropObject.class<any>)
    Props[Object.id] = Object
    PropsByModel[Object.Model.Name] = Object
    Object.Model:SetAttribute("IsProp", true)
end

function module.RegisterRoom(Room: zone.class)
    Rooms[Room.GroupID] = Room
end

export type Check = (player: Player, ...any) -> (boolean, string?)

export type ClientProp = {
    Id: string,
    ModelName: string,
    Model: Model?,
    CFrame: CFrame,
    Scale: number,
    Attributes: { [string]: any }?,
    OriginalScale: number?,
    MinScale: number?,
    MaxScale: number?,
    CanScale: boolean?,
    GroupID: string?,
}

local GetChecks: { Check } = {}
local PlaceChecks: { Check } = {}
local UpdateChecks: { Check } = {}
local RemoveChecks: { Check } = {}

local function makeAdder(list: { Check })
    return function(check: Check): () -> ()
        table.insert(list, check)
        return function()
            local index = table.find(list, check)
            if index then
                table.remove(list, index)
            end
        end
    end
end

local function runChecks(list: { Check }, ...: any): (boolean, string?)
    for _, check in list do
        local allowed, reason = check(...)
        if not allowed then
            return false, reason
        end
    end
    return true
end

module.AddGetCheck = makeAdder(GetChecks)
module.AddPlaceCheck = makeAdder(PlaceChecks)
module.AddUpdateCheck = makeAdder(UpdateChecks)
module.AddRemoveCheck = makeAdder(RemoveChecks)

local function replicateIfAllowed(player: Player, object: PropObject.class<any>?): boolean
    if not object or not object.Model then
        return false
    end
    if not runChecks(GetChecks, player, object) then
        return false
    end
    if not Replication.IsReplicated(player, object.Model) then
        Replication.ReplicateAsset({ player }, object.Model)
    end
    return true
end

local function getOwnedRoom(player: Player): zone.class
    local room = PlayerRooms[player]
    if not room then
        room = zone.New(player)
        module.RegisterRoom(room)
        PlayerRooms[player] = room
    end
    return room
end

function module.GetPlayerRoom(player: Player): zone.class?
    return PlayerRooms[player]
end

function module.GetRooms(): { [string]: zone.class }
    return Rooms
end

local function spawnProp(id: string, player: Player, position: CFrame?)
    local object = Props[id]
    if not object then
        return nil
    end
    position = position or (player.Character and player.Character:GetPivot()) or CFrame.new()
    local prop = getOwnedRoom(player):SpawnObject(object, position)
    if prop then
        module.PropPlaced:Fire(player, prop)
        prop.Changed:Connect(function(property, value)
            module.PropUpdated:Fire(player, prop, property, value)
        end)
        prop.Destroying:Once(function()
            module.PropRemoved:Fire(player, prop)
        end)
    end
    return prop
end

function module.PlaceProp(id: string, player: Player, position: CFrame?)
    local object = Props[id]
    if not object then
        return nil, "unknown prop"
    end

    position = position or (player.Character and player.Character:GetPivot()) or CFrame.new()

    local allowed, reason = runChecks(PlaceChecks, player, object, position)
    if not allowed then
        return nil, reason or "blocked by a placement check"
    end

    return spawnProp(id, player, position)
end

function module.LoadProps(
    player: Player,
    list: { { id: string, cframe: CFrame?, scale: number? } },
    onLoaded: ((any, any) -> ())?
): { any }
    local loaded = {}
    for _, entry in list do
        local prop = spawnProp(entry.id, player, entry.cframe)
        if prop then
            if entry.scale then
                prop:SetScale(entry.scale)
            end
            table.insert(loaded, prop)
            if onLoaded then
                onLoaded(prop, entry)
            end
        end
    end
    return loaded
end

local ModelChecks: { [string]: (player: Player, ...any) -> ...any } = {}

function module.GetModelCheck(name: string, fn: (player: Player, ...any) -> ...any)
    ModelChecks[name] = fn
end

local function runModelCheck(player: Player, name: string, ...: any)
    local check = ModelChecks[name]
    if not check then
        return
    end
    for _, result in { check(player, ...) } do
        local object = if typeof(result) == "string" then Props[result] else result
        replicateIfAllowed(player, object)
    end
end

local function findProp(propId: string): (any, zone.class?)
    for _, room in Rooms do
        for _, child in room.Children do
            if child.id == propId then
                return child, room
            end
        end
    end
    return nil, nil
end

function module.UpdateProp(player: Player, propId: string, cframe: CFrame?, scale: number?): (boolean, string?)
    local prop, room = findProp(propId)
    if not prop or room.Owner ~= player then
        return false, "you do not own that prop"
    end
    local allowed, reason = runChecks(UpdateChecks, player, prop)
    if not allowed then
        return false, reason or "blocked by an update check"
    end
    if cframe then
        prop:SetCFrame(cframe)
    end
    if scale then
        prop:SetScale(scale)
    end
    return true
end

function module.RemoveProp(player: Player, propId: string): (boolean, string?)
    local prop, room = findProp(propId)
    if not prop or room.Owner ~= player then
        return false, "you do not own that prop"
    end
    local allowed, reason = runChecks(RemoveChecks, player, prop)
    if not allowed then
        return false, reason or "blocked by a remove check"
    end
    prop:Destroy()
    return true
end

function module.ForceRemoveProp(propId: string): boolean
    local prop = findProp(propId)
    if not prop then
        return false
    end
    prop:Destroy()
    return true
end

function module.GetPlayerProps(player: Player): { any }
    local room = PlayerRooms[player]
    local list = {}
    if room then
        for _, child in room.Children do
            table.insert(list, child)
        end
    end
    return list
end

function module.BootServer()
    Socket:On("RequestPropModels", function(Player: Player, Source: string)
        local Room = Rooms[Source]
        if not Room or not table.find(Room.Listeners, Player) then
            return
        end

        local queue = {}
        for Object, children in Room.prop_cache do
            if #children > 0 and not Replication.IsReplicated(Player, Object.Model) then
                table.insert(queue, Object)
            end
        end

        table.sort(queue, function(a, b)
            return a.Importance > b.Importance
        end)

        for _, Object in queue do
            replicateIfAllowed(Player, Object)
        end
    end)

    Socket:On("RequestModelCheck", function(player: Player, requests: { { name: string, args: { any }? } })
        if typeof(requests) ~= "table" then
            return
        end
        for _, request in requests do
            runModelCheck(player, request.name, table.unpack(request.args or {}))
        end
    end)

    Socket:On("RequestBuildModel", function(player: Player, id: string): string?
        local object = Props[id]
        if not object or not replicateIfAllowed(player, object) then
            return nil
        end
        return object.Model.Name
    end)

    Socket:On("PublishFrom", function(player: Player, payload: { { id: string?, place: string?, placeModel: string?, cframe: CFrame, scale: number? } }): boolean
        if typeof(payload) ~= "table" then
            return false
        end

        local placeCount = 0
        for _, item in payload do
            if item.place or item.placeModel then
                placeCount += 1
            end
        end
        if placeCount > 0 then
            local readyAt = PlaceCooldown[player]
            if readyAt and os.clock() < readyAt then
                return false
            end
            PlaceCooldown[player] = os.clock() + math.min(PLACE_COOLDOWN_MAX, placeCount * PLACE_COOLDOWN_PER)
        end

        local succeeded = 0
        for _, item in payload do
            local byModel = item.placeModel and PropsByModel[item.placeModel]
            local placeId = item.place or (byModel and byModel.id)
            if placeId then
                local placed = module.PlaceProp(placeId, player, item.cframe)
                if placed then
                    if item.scale then
                        placed:SetScale(item.scale)
                    end
                    succeeded += 1
                end
            elseif item.id then
                local ok = module.UpdateProp(player, item.id, item.cframe, item.scale)
                if ok then
                    succeeded += 1
                end
            end
        end
        return succeeded > 0
    end)

    Socket:On("RemoveProps", function(player: Player, ids: { string })
        if typeof(ids) ~= "table" then
            return
        end
        for _, id in ids do
            module.RemoveProp(player, id)
        end
    end)

    Players.PlayerRemoving:Connect(function(pl)
        for key, item in pairs(Rooms) do
            if item.Owner == pl then
                item:Destroy()
                Rooms[key] = nil
            end
        end
        PlayerRooms[pl] = nil
        PlaceCooldown[pl] = nil
    end)
end

function module.BootClient()
    local rendered = Instance.new("Folder")
    rendered.Name = "PropPlacer_Rendered"
    rendered.Parent = workspace

    local mastersFolder = Instance.new("Folder")
    mastersFolder.Name = "PropPlacer_Masters"
    mastersFolder.Parent = workspace

    local masters: { [string]: Model } = {}
    local clones: { [string]: Model } = {}
    local propData: { [string]: ClientProp } = {}
    local roomProps: { [string]: { [string]: boolean } } = {}
    local joined: { [string]: boolean } = {}
    local ownedRooms: { [string]: boolean } = {}
    local pendingUnload: { [string]: number } = {}
    local pendingRefresh: { [string]: number } = {}
    local loading: { [string]: boolean } = {}
    local modelReplicated: signal.Signal<string, Model> = signal.new("Serial")
    local propUnloaded: signal.Signal<string, Model> = signal.new("Serial")
    local needs: { [string]: { { fulfill: (Model) -> (), cancelled: boolean } } } = {}
    local propPlaced: signal.Signal<string, Model> = signal.new("Serial")
    local propAttribute: signal.Signal<ClientProp, string, any> = signal.new("Serial")
    local masterUsed: { [string]: number } = {}
    local MASTER_TTL = 120
    local propInfo: { [string]: { OriginalScale: number, MinScale: number?, MaxScale: number?, CanScale: boolean? } } = {}
    local reloadAt: { [string]: number } = {}

    local function touchMaster(modelName: string): Model?
        local master = masters[modelName]
        if master then
            masterUsed[modelName] = os.clock()
        end
        return master
    end

    local function cacheDetails(data)
        if data.OriginalScale == nil then
            return
        end
        local info = propInfo[data.ModelName]
        if not info then
            info = {}
            propInfo[data.ModelName] = info
        end
        info.OriginalScale = data.OriginalScale
        info.MinScale = data.MinScale
        info.MaxScale = data.MaxScale
        info.CanScale = data.CanScale
    end

    local function applyAttributes(clone: Instance, attributes)
        if not attributes then
            return
        end
        for key, value in attributes do
            pcall(clone.SetAttribute, clone, key, value)
        end
    end

    local function renderProp(data)
        cacheDetails(data)
        local base = propInfo[data.ModelName]
        local clone = clones[data.Id]
        if not clone then
            local master = touchMaster(data.ModelName)
            if not master then
                local last = reloadAt[data.ModelName]
                if data.GroupID and (not last or os.clock() - last > 1) then
                    reloadAt[data.ModelName] = os.clock()
                    Socket:Emit("RequestPropModels", data.GroupID)
                end
                return
            end
            clone = master:Clone()
            clone.Name = data.ModelName
            clone.Parent = rendered
            clones[data.Id] = clone
            data.Model = clone
            clone:PivotTo(data.CFrame)
            clone:ScaleTo(((base and base.OriginalScale) or master:GetScale()) * (data.Scale or 1))
            applyAttributes(clone, data.Attributes)
            clone:SetAttribute("PropId", data.Id)
            propPlaced:Fire(data.Id, clone)
            return
        end
        touchMaster(data.ModelName)
        data.Model = clone
        clone:PivotTo(data.CFrame)
        clone:ScaleTo(((base and base.OriginalScale) or clone:GetScale()) * (data.Scale or 1))
        applyAttributes(clone, data.Attributes)
    end

    local function removeProp(id: string)
        local clone = clones[id]
        if clone then
            propUnloaded:Fire(id, clone)
            clone:Destroy()
            clones[id] = nil
        end
        propData[id] = nil
    end

    local function unloadRoom(groupId: string)
        local set = roomProps[groupId]
        if set then
            for id in set do
                removeProp(id)
            end
            roomProps[groupId] = nil
        end
        ownedRooms[groupId] = nil
    end

    local function refreshRoom(groupId: string)
        if not joined[groupId] then
            return
        end
        local props = Socket:Call("GetProps", 5, groupId)
        if not joined[groupId] or typeof(props) ~= "table" then
            return
        end
        local fresh = {}
        for _, data in props do
            fresh[data.Id] = true
            data.GroupID = groupId
            propData[data.Id] = data
            renderProp(data)
        end
        local set = roomProps[groupId]
        if set then
            for id in set do
                if not fresh[id] then
                    removeProp(id)
                end
            end
        end
        roomProps[groupId] = fresh
        Socket:Emit("RequestPropModels", groupId)
    end

    Replication.OnReplication:Connect(function(Asset: Instance)
        if Asset:GetAttribute("IsProp") ~= true or not Asset:IsA("Model") then
            return
        end
        if masters[Asset.Name] then
            Asset:Destroy()
            return
        end
        Asset.Parent = mastersFolder
        Asset:PivotTo(CFrame.new(0, -100, 0))
        masters[Asset.Name] = Asset
        masterUsed[Asset.Name] = os.clock()
        local info = propInfo[Asset.Name]
        if not info then
            info = {}
            propInfo[Asset.Name] = info
        end
        info.OriginalScale = info.OriginalScale or Asset:GetScale()

        for _, data in propData do
            if data.ModelName == Asset.Name then
                renderProp(data)
            end
        end

        local waiting = needs[Asset.Name]
        if waiting then
            needs[Asset.Name] = nil
            for _, need in waiting do
                if not need.cancelled then
                    need.fulfill(Asset)
                end
            end
        end

        modelReplicated:Fire(Asset.Name, Asset)
    end)

    Socket:On("Entered_Room", function(groupId: string, owned: boolean?)
        joined[groupId] = true
        ownedRooms[groupId] = owned or nil

        if pendingUnload[groupId] then
            pendingUnload[groupId] = nil
            pendingRefresh[groupId] = os.clock() + 3
            return
        end
        if loading[groupId] then
            return
        end

        loading[groupId] = true
        local props = Socket:Call("GetProps", 5, groupId)

        local set = roomProps[groupId] or {}
        roomProps[groupId] = set
        if typeof(props) == "table" then
            for _, data in props do
                data.GroupID = groupId
                propData[data.Id] = data
                set[data.Id] = true
                renderProp(data)
            end
        end
        Socket:Emit("RequestPropModels", groupId)
        loading[groupId] = nil

        if not joined[groupId] and roomProps[groupId] then
            pendingUnload[groupId] = os.clock() + 5
        end
    end)

    Socket:On("ExitedRoom", function(groupId: string)
        joined[groupId] = nil
        pendingRefresh[groupId] = nil
        if loading[groupId] then
            return
        end
        if roomProps[groupId] then
            pendingUnload[groupId] = os.clock() + 5
        end
    end)

    local function inRoom(groupId: string, id: string): boolean
        if not joined[groupId] then
            warn(`[PropPlacer] update for room { groupId } we are not in (prop { id })`)
            return false
        end
        return true
    end

    Socket:On("Prop_Placed", function(groupId: string, data)
        if not joined[groupId] or typeof(data) ~= "table" then
            return
        end
        data.GroupID = groupId
        data.Scale = data.Scale or 1
        propData[data.Id] = data

        local set = roomProps[groupId] or {}
        roomProps[groupId] = set
        set[data.Id] = true

        renderProp(data)
        if not masters[data.ModelName] then
            Socket:Emit("RequestPropModels", groupId)
        end
    end)

    Socket:On("Prop_Moved", function(groupId: string, id: string, cframe: CFrame)
        if not inRoom(groupId, id) then
            return
        end
        if propData[id] then
            propData[id].CFrame = cframe
        end
        if clones[id] then
            clones[id]:PivotTo(cframe)
        end
    end)

    Socket:On("Prop_Scaled", function(groupId: string, id: string, absoluteScale: number)
        if not inRoom(groupId, id) then
            return
        end
        local data = propData[id]
        local info = data and propInfo[data.ModelName]
        local base = info and info.OriginalScale
        if data and base and base > 0 then
            data.Scale = absoluteScale / base
        end
        if clones[id] then
            clones[id]:ScaleTo(absoluteScale)
        end
    end)

    Socket:On("Prop_Attribute", function(groupId: string, id: string, name: string, value: any)
        if not inRoom(groupId, id) then
            return
        end
        local data = propData[id]
        if not data then
            return
        end
        data.Attributes = data.Attributes or {}
        data.Attributes[name] = value
        local clone = clones[id]
        if clone then
            pcall(clone.SetAttribute, clone, name, value)
        end
        propAttribute:Fire(data, name, value)
    end)

    Socket:On("Prop_Removed", function(groupId: string, id: string)
        if not inRoom(groupId, id) then
            return
        end
        if roomProps[groupId] then
            roomProps[groupId][id] = nil
        end
        removeProp(id)
    end)

    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        for groupId, deadline in pendingUnload do
            if now >= deadline then
                pendingUnload[groupId] = nil
                unloadRoom(groupId)
            end
        end
        for groupId, deadline in pendingRefresh do
            if now >= deadline then
                pendingRefresh[groupId] = nil
                task.spawn(refreshRoom, groupId)
            end
        end
        for modelName, master in masters do
            if now - (masterUsed[modelName] or now) > MASTER_TTL then
                master:Destroy()
                masters[modelName] = nil
                masterUsed[modelName] = nil
            end
        end
    end)

    local Prop = require("@self/Prop")
    local ScaleManager = require("@self/ScaleManager")

    local api = {}
    local editing = nil
    local placeReadyAt = 0

    local function awaitMaster(modelName: string, timeout: number?): Model?
        local master = masters[modelName]
        local deadline = os.clock() + (timeout or 5)
        while not master and os.clock() < deadline do
            task.wait()
            master = masters[modelName]
        end
        return master
    end

    local function makeEditProp(model: Model, modelName: string)
        touchMaster(modelName)
        local info = propInfo[modelName]
        local baseScale = (info and info.OriginalScale) or model:GetScale()
        local currentScale = if baseScale > 0 then model:GetScale() / baseScale else 1
        model:ScaleTo(baseScale)
        local scaling = {
            Min = (info and info.MinScale) or 0,
            Max = (info and info.MaxScale) or math.huge,
            CanScale = if info then info.CanScale ~= false else true,
        }
        local prop = Prop.New(model:GetPivot(), scaling, modelName, 1, model)
        prop:SetScale(currentScale)
        return prop
    end

    local function resolveId(thing: any): string?
        if typeof(thing) == "string" then
            return thing
        end
        if typeof(thing) ~= "Instance" then
            return nil
        end
        local inst = thing
        while inst and not inst:GetAttribute("PropId") do
            inst = inst.Parent
        end
        return inst and inst:GetAttribute("PropId")
    end

    local function teardown()
        if not editing then
            return
        end
        editing.manager:Destroy()
        for _, entry in editing.entries do
            if entry.unloadConn then
                entry.unloadConn:Disconnect()
            end
            if entry.clone then
                entry.clone:Destroy()
            end
            if entry.original then
                entry.original.Parent = rendered
            end
        end
        editing = nil
    end

    local function exitEditOnUnload(id: string)
        if not editing then
            return
        end
        local involved = false
        for _, entry in editing.entries do
            if entry.id == id then
                involved = true
                break
            end
        end
        if not involved then
            return
        end
        editing.manager:Destroy()
        for _, entry in editing.entries do
            if entry.unloadConn then
                entry.unloadConn:Disconnect()
            end
            if entry.clone then
                entry.clone:Destroy()
            end
            if entry.original and entry.id ~= id then
                entry.original.Parent = rendered
            end
        end
        editing = nil
    end

    function api.Edit(objects: any)
        api.Discard()
        local list = if typeof(objects) == "table" then objects else { objects }
        local entries = {}
        local props = {}
        local seen = {}
        for _, object in list do
            local id = resolveId(object)
            local data = id and propData[id]
            local original = id and clones[id]
            if original and data and ownedRooms[data.GroupID] and not seen[id] then
                seen[id] = true
                local clone = original:Clone()
                clone:SetAttribute("PropId", nil)
                clone.Parent = rendered
                original.Parent = nil
                local prop = makeEditProp(clone, data.ModelName)
                local entry = { id = id, original = original, clone = clone, prop = prop }
                entry.unloadConn = original.Destroying:Once(function()
                    exitEditOnUnload(id)
                end)
                table.insert(entries, entry)
                table.insert(props, prop)
            end
        end
        if #props == 0 then
            return nil
        end
        editing = { entries = entries, manager = ScaleManager.New(props) }
        return editing.manager
    end

    local function requireModel(modelName: string, fulfill: (Model) -> ()): () -> ()
        local master = touchMaster(modelName)
        if master then
            fulfill(master)
            return function() end
        end
        local list = needs[modelName]
        if not list then
            list = {}
            needs[modelName] = list
        end
        local need = { fulfill = fulfill, cancelled = false }
        table.insert(list, need)
        return function()
            need.cancelled = true
        end
    end

    local buildCancel: (() -> ())? = nil

    function api.Build(propId: string, onReady: ((any) -> ())?)
        api.Discard()
        local modelName = Socket:Call("RequestBuildModel", 5, propId)
        if typeof(modelName) ~= "string" then
            return
        end
        buildCancel = requireModel(modelName, function(master)
            local clone = master:Clone()
            clone.Parent = rendered
            local prop = makeEditProp(clone, modelName)
            editing = { entries = { { placeId = propId, clone = clone, prop = prop } }, manager = ScaleManager.New({ prop }) }
            if onReady then
                onReady(editing.manager)
            end
        end)
    end

    function api.BuildFrom(objects: any)
        api.Discard()
        local list = if typeof(objects) == "table" then objects else { objects }
        local entries = {}
        local props = {}
        for _, object in list do
            local id = resolveId(object)
            local data = id and propData[id]
            local source = id and clones[id]
            if source and data then
                local clone = source:Clone()
                clone:SetAttribute("PropId", nil)
                clone.Parent = rendered
                local prop = makeEditProp(clone, data.ModelName)
                table.insert(entries, { placeModel = data.ModelName, clone = clone, prop = prop })
                table.insert(props, prop)
            end
        end
        if #props == 0 then
            return nil
        end
        editing = { entries = entries, manager = ScaleManager.New(props) }
        return editing.manager
    end

    function api.Discard()
        if buildCancel then
            buildCancel()
            buildCancel = nil
        end
        teardown()
    end

    function api.PublishFrom(manager: any): boolean
        if not editing or editing.manager ~= manager then
            return false
        end
        local placeCount = 0
        for _, entry in editing.entries do
            if entry.placeId or entry.placeModel then
                placeCount += 1
            end
        end
        if placeCount > 0 and os.clock() < placeReadyAt then
            return false
        end

        local payload = {}
        for _, entry in editing.entries do
            if entry.clone then
                table.insert(payload, {
                    id = entry.id,
                    place = entry.placeId,
                    placeModel = entry.placeModel,
                    cframe = entry.clone:GetPivot(),
                    scale = entry.prop.Scale,
                })
            end
        end

        local ok = Socket:Call("PublishFrom", 5, payload)
        if not ok then
            return false
        end
        if placeCount > 0 then
            placeReadyAt = os.clock() + math.min(PLACE_COOLDOWN_MAX, placeCount * PLACE_COOLDOWN_PER)
        end
        teardown()
        return true
    end

    function api.Remove(objects: any)
        local list = if typeof(objects) == "table" then objects else { objects }
        local ids = {}
        for _, object in list do
            local id = resolveId(object)
            if id then
                table.insert(ids, id)
            end
        end
        if #ids > 0 then
            Socket:Emit("RemoveProps", ids)
        end
    end

    function api.GetModels(name: string, ...: any)
        Socket:Emit("RequestModelCheck", { { name = name, args = { ... } } })
    end

    function api.GetModelsBulk(requests: { { name: string, args: { any }? } })
        Socket:Emit("RequestModelCheck", requests)
    end

    function api.GetMaster(modelName: string): Model?
        return touchMaster(modelName)
    end

    function api.CloneModel(modelName: string): Model?
        local master = touchMaster(modelName)
        return master and master:Clone()
    end

    function api.AwaitMaster(modelName: string, timeout: number?): Model?
        return awaitMaster(modelName, timeout)
    end

    api.ModelReplicated = modelReplicated
    api.PropPlaced = propPlaced
    api.PropUnloaded = propUnloaded
    api.PropAttributeChanged = propAttribute

    propUnloaded:Connect(exitEditOnUnload)

    return api
end

return module
