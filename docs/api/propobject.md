# PropObject

A reusable prop *template*. It owns a source `Model` and spawns `Prop` instances
(children) from it.

```lua
local PropObject = require(PropPlacer.PropObject)

local crate = PropObject.New(crateModel, "crate")
crate.MinScale, crate.MaxScale = 0.5, 4

local prop = crate:RegisterChild(CFrame.new(0, 5, 0))
```

## Constructor

```lua
PropObject.New(Model: Model, id: string) -> PropObject
```

Creates a template from a source model.

## Methods

| Method | Signature | Description |
|---|---|---|
| `RegisterChild` | `(self, Position: CFrame?) -> Prop` | Spawn a child `Prop`, stamped with this template's model name, importance and scale policy. |
| `FindFirstChild` | `(self, id: string) -> Prop?` | Find a spawned child by id. |
| `GetChildren` | `(self) -> {Prop}` | All currently spawned children. |
| `GetAbstract` | `(self) -> {Importance: number, ModelName: string}` | Lightweight summary of the template. |
| `SetStat` | `(self, key, value) -> ()` | Store template-level data. |
| `GetStat` | `(self, key) -> value` | Read template-level data. |
| `SetStats` | `(self, stats) -> ()` | Set several stats at once. |

## Events

See [Events](/api/events.md) for how to connect, disconnect and await.

| Event | Fires with | When |
|---|---|---|
| `ChildAdded` | `(prop)` | A child prop was registered. |
| `ChildRemoved` | `(prop)` | A child prop was destroyed/removed. |

```lua
crate.ChildAdded:Connect(function(prop)
    print("spawned", prop.Id)
end)
```

## Properties

| Property | Type | Notes |
|---|---|---|
| `id` | `string` | Template id. |
| `Model` | `Model` | Source model. |
| `Importance` | `number` | Copied onto each child. |
| `CanScale` | `boolean` | Whether children may be scaled. |
| `MinScale` / `MaxScale` | `number` | Scale range copied onto each child. |
