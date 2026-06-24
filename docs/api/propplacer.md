# PropPlacer

PropPlacer is the prop / room toolkit. The **server** owns the props (placing,
updating, removing, persistence) and the **client** renders them and drives the
in-game build/edit experience. Props live in **rooms** (zones); a player only ever
receives the props for rooms they're standing in.

```lua
local PropPlacer = require(ReplicatedStorage.Modules.PropPlacer)
```

## Setup

```lua
-- server
PropPlacer.BootServer()

-- client
local Build = PropPlacer.BootClient() -- returns the client build API (see below)
```

`BootServer` wires up the server request handlers. `BootClient` starts the render
engine and returns the **client API** table used for building and editing.

---

# Server API

## Registering

### RegisterProp

```lua
PropPlacer.RegisterProp(object: PropObject)
```

Registers a [PropObject](/api/propobject.md) so its model can be replicated and
placed. Do this once per prop type at startup.

### RegisterRoom

```lua
PropPlacer.RegisterRoom(room: Zone)
```

Registers a [Zone](/api/zone.md) so requests can resolve it. Player-owned rooms are
created automatically the first time a player places a prop — you only call this
for rooms you build yourself.

## Placing

### PlaceProp

```lua
PropPlacer.PlaceProp(id: string, player: Player, position: CFrame?) -> (Prop?, string?)
```

Places prop `id` for `player` after every [place check](#checks) passes. Defaults
`position` to the player's pivot. Returns the new [Prop](/api/prop.md), or `nil` +
a reason if a check vetoed it. Fires [`PropPlaced`](#server-events).

```lua
local prop, reason = PropPlacer.PlaceProp("crate", player, hitCFrame)
if not prop then warn("couldn't place:", reason) end
```

### LoadProps

```lua
PropPlacer.LoadProps(
    player: Player,
    list: { { id: string, cframe: CFrame?, scale: number? } },
    onLoaded: ((prop, entry) -> ())?
) -> { Prop }
```

Bulk-places saved props for a player. **Bypasses the place checks** (the data is
server-authoritative). `onLoaded` runs for each placed prop with the prop and its
source entry — handy for mapping a new prop id back to a save row. Returns the
list of loaded props.

```lua
PropPlacer.LoadProps(player, saved, function(prop, entry)
    entry.liveId = prop.id
end)
```

## Updating & removing

### UpdateProp

```lua
PropPlacer.UpdateProp(player, propId: string, cframe: CFrame?, scale: number?) -> (boolean, string?)
```

Moves and/or scales a prop the player owns. Returns `false` + a reason if they
don't own it, the id is unknown, or an [update check](#checks) vetoes it.

### RemoveProp

```lua
PropPlacer.RemoveProp(player, propId: string) -> (boolean, string?)
```

Removes a prop the player owns (subject to [remove checks](#checks)).

### ForceRemoveProp

```lua
PropPlacer.ForceRemoveProp(propId: string) -> boolean
```

Removes a placed prop with **no ownership or checks** — the normal removal events
still fire. Returns `true` if a prop was removed.

## Queries

| Function | Returns |
|---|---|
| `GetPlayerProps(player)` | every prop the player currently has placed |
| `GetPlayerRoom(player)` | the [Zone](/api/zone.md) the player owns, if any |
| `GetRooms()` | all registered rooms, keyed by GroupID |

## Checks

Checks are guards that run before an action. Register as many as you like; the
first one to return `false` blocks the action (and its optional reason is
returned to the caller).

```lua
PropPlacer.AddGetCheck(check)    -- (player, object)            before a model replicates
PropPlacer.AddPlaceCheck(check)  -- (player, object, position)  before PlaceProp
PropPlacer.AddUpdateCheck(check) -- (player, prop)              before UpdateProp
PropPlacer.AddRemoveCheck(check) -- (player, prop)              before RemoveProp
```

Each returns a function that removes the check.

```lua
local remove = PropPlacer.AddPlaceCheck(function(player, object)
    if not owns(player, object.id) then
        return false, "you don't own that prop"
    end
    return true
end)
```

## Custom model requests

### GetModelCheck

```lua
PropPlacer.GetModelCheck(name: string, fn: (player, ...) -> ...)
```

Registers a named, variadic resolver the client can invoke (via
[`api.GetModels`](#getting-models)). Validate the request and return the prop
object(s) / ids to replicate, or nothing to reject it.

```lua
PropPlacer.GetModelCheck("GetStandProps", function(player, standId)
    if not ownsStand(player, standId) then return end
    return crateObject, barrelObject
end)
```

## Server events

Connect with `:Connect` / `:Once` (see [Events](/api/events.md)).

| Event | Fires with |
|---|---|
| `PropPlaced` | `(player, prop)` |
| `PropUpdated` | `(player, prop, property, value)` |
| `PropRemoved` | `(player, prop)` |

```lua
PropPlacer.PropPlaced:Connect(function(player, prop)
    prop:SetAttribute("Color", Color3.new(math.random(), math.random(), math.random()))
end)
```

---

# Client API

`local Build = PropPlacer.BootClient()` returns the build API. Editing works on a
**clone** of the rendered prop — the original is hidden until you `PublishFrom`
(commit) or `Discard` (cancel), so nothing changes server-side until confirmed.

## Building & editing

### Build

```lua
Build.Build(propId: string, onReady: ((ScaleManager) -> ())?)
```

Starts placing a **new** prop. Lazy: the [ScaleManager](/api/scalemanager.md) is
handed to `onReady` once the model has replicated in. `Discard` before it loads
and the pending wait is skipped.

```lua
Build.Build("crate", function(manager)
    manager:SetMode("Move")
end)
```

### Edit

```lua
Build.Edit(objects) -> ScaleManager?
```

Edits one or more **rendered props you own** (pass ids or clicked instances).
Returns a ScaleManager over the clones. Props in rooms you don't own are ignored.

### BuildFrom

```lua
Build.BuildFrom(objects) -> ScaleManager?
```

Bulk-places **copies** of existing rendered props. Clones each one and returns a
ScaleManager over all the copies; `PublishFrom` places them as new props in your
room. The sources are untouched.

### PublishFrom

```lua
Build.PublishFrom(manager) -> boolean
```

Commits the current edit/placement to the server. Returns `true` on success.
Returns `false` (and **keeps you in edit mode**) if the server dropped it — e.g. a
placement still on cooldown, or every change was vetoed by a check.

### Discard

```lua
Build.Discard()
```

Throws away the edit clones and restores the originals unchanged (also cancels a
`Build` still waiting on its model).

### Remove

```lua
Build.Remove(objects)
```

Removes one prop or many on the server (ids or instances). The server re-checks
ownership.

## Getting models

For custom flows you can fetch a model's data directly.

| Function | Purpose |
|---|---|
| `GetModels(name, ...)` | invoke a [`GetModelCheck`](#custom-model-requests) by name |
| `GetModelsBulk(requests)` | invoke several at once: `{ { name, args? }, ... }` |
| `GetMaster(modelName)` | the replicated source model, if it has arrived |
| `CloneModel(modelName)` | a fresh clone of a replicated model (or `nil`) |
| `AwaitMaster(modelName, timeout?)` | yield until a model replicates in (default 5s) |

## Client events

| Event | Fires with |
|---|---|
| `ModelReplicated` | `(modelName, master)` as models replicate in |
| `PropPlaced` | `(id, model)` when a prop loads in |
| `PropUnloaded` | `(id, model)` when a rendered prop unloads |
| `PropAttributeChanged` | `(prop, name, value)` — `prop` is a [`ClientProp`](#clientprop) |

```lua
Build.PropAttributeChanged:Connect(function(prop, name, value)
    if name == "Color" and prop.Model then
        for _, part in prop.Model:GetDescendants() do
            if part:IsA("BasePart") then part.Color = value end
        end
    end
end)
```

## ClientProp

The object passed to `PropAttributeChanged` — a rendered prop as the client sees
it, including **all** its replicated attributes.

```lua
type ClientProp = {
    Id: string,
    ModelName: string,
    Model: Model?,              -- the rendered clone (nil until its model loads)
    CFrame: CFrame,
    Scale: number,
    Attributes: { [string]: any }?,
}
```

---

## Classes

| Class | Summary |
|---|---|
| [Prop](/api/prop.md) | A single placed prop — transform, scale, attributes. |
| [PropObject](/api/propobject.md) | A reusable template that spawns `Prop` instances. |
| [Zone](/api/zone.md) | A room that groups props and replicates them to players. |
| [ScaleManager](/api/scalemanager.md) | A client editor: move / rotate / resize handles. |

## Conventions

Each class page lists its members as one of:

- **Method** — a function you call on an instance with `:`, e.g. `prop:SetScale(2)`.
- **Event** — a [Signal](/api/events.md) you subscribe to.
- **Property** — a field you read on the instance, e.g. `prop.Position`.
