--!nonstrict
-- Replication test (server) using PropPlacer's built-in (ReplicationPP) replication.
-- Rooms are entered/exited by walking into their zones (the spatial observer drives
-- it); a prop renders on entry and is cleaned up on exit. Every rendered prop is a
-- clone of ONE shared model parked under the map.
--   * 2 overlapping rooms near spawn (HomeA / HomeB)
--   * 1 "active" room whose props move + resize
--   * 60 rooms scattered far apart
-- Nothing renders until you walk into a room.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PropPlacer")
local PropPlacer = require(Modules)
local Zone = require(Modules:WaitForChild("Zone"))
local PropObject = require(Modules:WaitForChild("PropObject"))

PropPlacer.BootServer()

-- one prop model, reused (and replicated once) for every room
local function buildFakeModel(): Model
    local model = Instance.new("Model")
    model.Name = "FakeProp"

    local part = Instance.new("Part")
    part.Name = "Body"
    part.Size = Vector3.new(8, 12, 8)
    part.Color = Color3.fromRGB(230, 120, 60)
    part.Anchored = true
    part.Parent = model

    model.PrimaryPart = part
    return model
end

local source = buildFakeModel()
source.Parent = ServerStorage

local object = PropObject.New(source, "fake_crate")
object.CanScale = true
object.MinScale = 0.5
object.MaxScale = 3
PropPlacer.RegisterProp(object)

-- a custom get-check so the client can request this model by name (api.GetModels)
PropPlacer.GetModelCheck("GetFakeProp", function()
    return object
end)

-- give every placed prop a random colour attribute; the client applies it on load
local function randomColor(): Color3
    return Color3.fromRGB(math.random(0, 255), math.random(0, 255), math.random(0, 255))
end
local objectAny: any = object
objectAny.ChildAdded:Connect(function(child: any)
    child:SetAttribute("Color", randomColor())
end)

-- ===== rooms (registered so requests resolve; entry is driven by the observer) =====
local allRooms = {}

local function makeRoom(name: string, position: Vector3)
    local room = Zone.New(name)
    PropPlacer.RegisterRoom(room)
    local child = room:SpawnObject(object, CFrame.new(position))
    table.insert(allRooms, room)
    return room, child
end

-- two overlapping rooms (centres closer than the zone size -> zones overlap)
makeRoom("HomeA", Vector3.new(0, 6, -80))
makeRoom("HomeB", Vector3.new(30, 6, -80))

-- the active room: several props that all move + resize
local activeRoom = Zone.New("Active")
PropPlacer.RegisterRoom(activeRoom)
table.insert(allRooms, activeRoom)

local activeChildren = {}
for i = 1, 5 do
    table.insert(activeChildren, activeRoom:SpawnObject(object, CFrame.new(-150 + (i - 1) * 22, 6, -80)))
end

-- 60 rooms scattered apart (still far enough that their zones stay separate)
for i = 0, 59 do
    makeRoom("Scattered_" .. i, Vector3.new(200 + (i % 10) * 150, 6, 200 + math.floor(i / 10) * 150))
end

print(`[ReplTest][Server] { #allRooms } rooms ready — walk into a room to render its props`)

-- continuously move + resize every prop in the active room
task.spawn(function()
    local bases = {}
    for i, child in activeChildren do
        bases[i] = child.Position.Position
    end
    local t = 0
    while true do
        t += 0.4
        for i, child in activeChildren do
            if child and not child.Destroyed then
                local phase = t + i
                child:SetCFrame(CFrame.new(bases[i] + Vector3.new(math.sin(phase) * 12, math.sin(phase * 0.6) * 6, 0)))
                child:SetScale(1.5 + math.sin(phase * 0.7))
            end
        end
        task.wait(0.4)
    end
end)

-- ===== debug: render every room's zone bounds =====
local debugFolder = Instance.new("Folder")
debugFolder.Name = "ReplTest_RoomDebug"
debugFolder.Parent = workspace

local boxes: { [any]: Part } = {}
local SYSTEM_COLOR = Color3.fromRGB(0, 170, 255) -- system / test rooms (blue)
local PLAYER_COLOR = Color3.fromRGB(60, 230, 90) -- player-made rooms (green)
RunService.Heartbeat:Connect(function()
    local seen = {}
    for _, room in PropPlacer.GetRooms() do
        local color = if typeof(room.Owner) == "Instance" then PLAYER_COLOR else SYSTEM_COLOR
        for _, z in room.Zones do
            seen[z] = true
            local box = boxes[z]
            if not box then
                box = Instance.new("Part")
                box.Anchored = true
                box.CanCollide = false
                box.CanQuery = false
                box.CanTouch = false
                box.CastShadow = false
                box.Material = Enum.Material.ForceField
                box.Transparency = 0.7
                box.Parent = debugFolder
                boxes[z] = box
            end
            box.Color = color
            box.Size = z:getSize()
            box.CFrame = z:getCFrame()
        end
    end

    for z, box in boxes do
        if not seen[z] then
            box:Destroy()
            boxes[z] = nil
        end
    end
end)
