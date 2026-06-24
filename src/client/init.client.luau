--!nonstrict
-- Public API test (client). PropPlacer.BootClient() returns the build API.
--   N            = Build a new prop ("fake_crate") -- lazy: ScaleManager arrives in a callback
--   Shift+RClick = add the clicked rendered prop to the selection
--   E            = Edit the selection
--   1 / 2 / 3    = Move / Rotate / Resize
--   F            = PublishFrom (commit the edit/placement)
--   C            = Discard
--   R            = Remove the selection
--   G            = GetModels("GetFakeProp") -- request a model via a custom get-check
--   H            = report GetMaster / CloneModel for "FakeProp"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

ReplicatedStorage:WaitForChild("Prop_Common") -- socket RemoteEvent must exist before we require it

local Modules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PropPlacer")
local PropPlacer = require(Modules)

local api = PropPlacer.BootClient()
local mouse = Players.LocalPlayer:GetMouse()

local manager = nil
local selection = {}

-- paint a rendered prop with its replicated "Color" attribute
local function applyColor(model)
    local color = model:GetAttribute("Color")
    if not color then
        return
    end
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.Color = color
        end
    end
end

api.ModelReplicated:Connect(function(modelName)
    print(`[API] model replicated: { modelName }`)
end)

api.PropPlaced:Connect(function(id, model)
    print(`[API] prop placed: { id }`)
    applyColor(model) -- colour it as soon as it loads in
end)

api.PropAttributeChanged:Connect(function(prop, name)
    if name == "Color" and prop.Model then
        applyColor(prop.Model) -- re-colour when the attribute arrives/changes
    end
end)

api.PropUnloaded:Connect(function(id)
    print(`[API] prop unloaded: { id }`)
end)

print("[API] N build | B copy | Shift+RClick select | E edit | 1/2/3 mode | F publish | C discard | R remove | G get | H master")

UserInputService.InputBegan:Connect(function(input, processed)
    -- shift + right-click adds whatever rendered prop is under the mouse to the selection
    if
        input.UserInputType == Enum.UserInputType.MouseButton2
        and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
    then
        if mouse.Target then
            table.insert(selection, mouse.Target)
            print(`[API] selection: { #selection }`)
        end
        return
    end

    if processed then
        return
    end

    local key = input.KeyCode
    if key == Enum.KeyCode.N then
        api.Build("fake_crate", function(builtManager)
            manager = builtManager -- lazy: arrives once the model has replicated in
            print("[API] build ready")
        end)
    elseif key == Enum.KeyCode.B then
        manager = api.BuildFrom(selection) -- bulk-place copies of the selected props
        table.clear(selection)
    elseif key == Enum.KeyCode.E then
        manager = api.Edit(selection)
    elseif key == Enum.KeyCode.One and manager then
        manager:SetMode("Move")
    elseif key == Enum.KeyCode.Two and manager then
        manager:SetMode("Rotate")
    elseif key == Enum.KeyCode.Three and manager then
        manager:SetMode("Resize")
    elseif key == Enum.KeyCode.F then
        if api.PublishFrom(manager) then -- false = still on cooldown; stay in edit mode
            manager = nil
            table.clear(selection)
        end
    elseif key == Enum.KeyCode.C then
        api.Discard()
        manager = nil
        table.clear(selection)
    elseif key == Enum.KeyCode.R then
        api.Remove(selection)
        table.clear(selection)
    elseif key == Enum.KeyCode.G then
        api.GetModels("GetFakeProp")
        print("[API] requested GetFakeProp")
    elseif key == Enum.KeyCode.H then
        print(`[API] FakeProp master loaded: { api.GetMaster("FakeProp") ~= nil }`)
        local clone = api.CloneModel("FakeProp")
        if clone then
            clone:Destroy() -- just proving we can pull a usable copy
        end
    end
end)
