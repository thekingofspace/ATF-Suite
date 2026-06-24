--==============================================================================
-- Services & Dependencies
--==============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local sc = require(script.sc)
local sig = require(script.sig)

--==============================================================================
-- Module State
--==============================================================================
local module = {}
local IsClient = RunService:IsClient()
local Replication_Target:Folder = nil
local Replication_Reciever:Folder = nil
local Target_event:RemoteEvent = nil
local Staged_Models:{[Instance]:string} = {}
local Pending_Models:{[string]:{thread}} = {}

--==============================================================================
-- Per-Player Cache (server-side)
--==============================================================================
local Player_Cache:{[Player]:{
    Target_Folder:Folder,
    Sigs:{RBXScriptConnection},
    Validated_Assets:{[Instance]:string}, -- keyed by original instance once client confirms
    Pending_Replications:{[string]:{Original:Instance, Staged:Instance}}
}} = {}

--==============================================================================
-- Helpers
--==============================================================================
local function generateFolders(Target:Player?):(...Folder)
    if IsClient then
        local Replicator = ReplicatedStorage:FindFirstChild("Replication_Target_PlusPLus") or Instance.new("Folder")
        Replicator.Name = "Replication_Target_PlusPLus"
        Replicator.Parent = ReplicatedStorage

        return Players.LocalPlayer.PlayerGui:WaitForChild("ReplicationPlusPlus_Assets", 500), Replicator
    else
        local Folder = Target.PlayerGui:FindFirstChild("ReplicationPlusPlus_Assets") or Instance.new("Folder")
        Folder.Name = "ReplicationPlusPlus_Assets"
        Folder.Parent = Target.PlayerGui

        return Folder
    end
end

local function Decompile_Config(Config:Configuration):{id:string}
    local configs = {
        id = Config:GetAttribute("id")
    }
    Config:Destroy()
    return configs
end

local function RegisterModel(Model:Instance, Id:string)
    local New_Model = Model:Clone()
    New_Model.Parent = Replication_Target
    local Aray = Pending_Models[New_Model.Name]

    if Aray then
        for _, item in ipairs(Aray) do
            coroutine.resume(item, New_Model)
        end
    end
    Staged_Models[New_Model] = Id
    New_Model.Destroying:Once(function()
        Target_event:FireServer("unregister_item", Id)
        Staged_Models[New_Model] = nil
    end)
    Target_event:FireServer("register_item", Id)
    module.OnReplication:Fire(New_Model)
end

--==============================================================================
-- Client: receive models from server, register & re-parent them locally
--==============================================================================
if IsClient then
    local Player = Players.LocalPlayer
    Target_event = ReplicatedStorage:WaitForChild("Replication_PLUSPLUS_EVENT", 500)::RemoteEvent

    local Receiver_Connection:RBXScriptConnection? = nil

    local function onReceiverChild(Child:Instance)
        local config = Child:WaitForChild("Config_Replication", 5)
        if not config then return end
        local config_info = Decompile_Config(config :: Configuration)
        RegisterModel(Child, config_info.id)
    end

    local function bindReceiver()
        if Receiver_Connection then
            Receiver_Connection:Disconnect()
        end
        Replication_Reciever, Replication_Target = generateFolders()
        Receiver_Connection = Replication_Reciever.ChildAdded:Connect(onReceiverChild)
        for _, child in ipairs(Replication_Reciever:GetChildren()) do
            onReceiverChild(child)
        end
    end

    bindReceiver()
    Player.CharacterAdded:Connect(bindReceiver)
    local switch = sc({
        unregister_item = function(id:string)
            for item, key in pairs(Staged_Models) do
                if key == id then
                    item:Destroy()
                end
            end
        end
    })

    Target_event.OnClientEvent:Connect(function(event:string, data:any)
        switch(event, data)
    end)
--==============================================================================
-- Server: track per-player caches and validate client registrations
--==============================================================================
else
    Players.PlayerAdded:Connect(function(Player:Player)
        local Cache = {
            Target_Folder = generateFolders(Player),
            Sigs = {},
            Validated_Assets = {},
            Pending_Replications = {}
        }

        table.insert(Cache.Sigs, Player.CharacterAdded:Connect(function() -- used for replication Update
            table.clear(Cache.Pending_Replications)
            Cache.Target_Folder = generateFolders(Player)
        end))

        Player_Cache[Player] = Cache
    end)

    Players.PlayerRemoving:Connect(function(Player)
        local Cache = Player_Cache[Player]
        if Cache then
            for _, item in ipairs(Cache.Sigs) do
                item:Disconnect()
            end
        end

        Player_Cache[Player] = nil
    end)

    for _, Player in ipairs(Players:GetPlayers()) do
        local Cache = {
            Target_Folder = generateFolders(Player),
            Sigs = {},
            Validated_Assets = {},
            Pending_Replications = {}
        }

        table.insert(Cache.Sigs, Player.CharacterAdded:Connect(function() -- used for replication Update
            table.clear(Cache.Pending_Replications)
            Cache.Target_Folder = generateFolders(Player)
        end))

        Player_Cache[Player] = Cache
    end

    Target_event = Instance.new("RemoteEvent")
    Target_event.Name = "Replication_PLUSPLUS_EVENT"
    Target_event.Parent = ReplicatedStorage
    local switch = sc({
        unregister_item = function(player:Player, id:string)
            local player_data = Player_Cache[player]
            if not player_data then return end

            for inst, item in pairs(player_data.Validated_Assets) do
                if id == item then
                    player_data.Validated_Assets[inst] = nil
                end
            end

            local pending = player_data.Pending_Replications[id]
            if pending then
                pending.Staged:Destroy()
                player_data.Pending_Replications[id] = nil
            end
        end,

        register_item = function(player:Player, id:string)
            local player_data = Player_Cache[player]
            if not player_data then return end

            local pending = player_data.Pending_Replications[id]
            if pending then
                player_data.Validated_Assets[pending.Original] = id
                player_data.Pending_Replications[id] = nil
                pending.Staged:Destroy() -- staged object cleanup once client confirms it has its local copy
            end
        end
    })
    Target_event.OnServerEvent:Connect(function(player, event:string, data:any)
        switch(event, player, data)
    end)
end

function module.ReplicateAsset(Targets:{Player}, Object:Instance)
    if IsClient then return end
    
    for _, player in ipairs(Targets) do
        local cache = Player_Cache[player]
        if not cache or module.IsReplicated(player, Object) then continue end

        local id = HttpService:GenerateGUID(false)
        local Staged_Object = Object:Clone()

        local config = Instance.new("Configuration")
        config.Name = "Config_Replication"
        config:SetAttribute("id", id)
        config.Parent = Staged_Object

        cache.Pending_Replications[id] = {Original = Object, Staged = Staged_Object}
        Staged_Object.Parent = cache.Target_Folder
    end
end

function module.IsReplicated(Target:Player, Inst:Instance):boolean
    local cache = Player_Cache[Target]
    if not cache then return false end
    return cache.Validated_Assets[Inst] ~= nil
end

function module.UnReplicate(Targets:{Player}, Object:Instance)
    if IsClient then return end

    for _, player in ipairs(Targets) do
        local cache = Player_Cache[player]
        if not cache then continue end
        local ID = cache.Validated_Assets[Object]
        if ID then
            Target_event:FireClient(player, "unregister_item", ID)
        end
    end
end

function module.AwaitAsset(Id:string):Instance
    if not IsClient then return end
    if Replication_Target:FindFirstChild(Id) then
        return Replication_Target:FindFirstChild(Id)
    end
    Pending_Models[Id] = Pending_Models[Id] or {}
    table.insert(Pending_Models[Id], coroutine.running())
    return coroutine.yield()
end

module.OnReplication = sig()::sig.Signaler<Instance>

return module