# Prop

A single placed prop. Holds a transform, a scale, a reference `Model`, and an
open-ended bag of attributes for game data.

```lua
local Prop = require(PropPlacer.Prop)

local prop = Prop.New(CFrame.new(0, 5, 0), { Min = 0.5, Max = 4, CanScale = true }, "Crate", 1, model)
```

## Constructor

```lua
Prop.New(
    Position: CFrame?,
    Scaling: { Original: number?, Min: number?, Max: number?, CanScale: boolean? }?,
    ModelName: string?,
    Importance: number?,
    Model: Model?
) -> Prop
```

Creates a prop. If a `Model` is given, its current scale becomes the baseline
(Scale `1`) and the model is pivoted to `Position`.

## Methods

| Method | Signature | Description |
|---|---|---|
| `SetCFrame` | `(self, cframe: CFrame) -> ()` | Move the prop. Pivots `Model` (if any) and fires `Changed("Position", cframe)`. |
| `SetScale` | `(self, scale: number) -> ()` | Set the scale multiplier (`1` = original). Clamped to `MinScale`/`MaxScale`; ignored when `CanScale` is false. Scales `Model` via `ScaleTo` and fires `Changed("Scale", scale)`. |
| `SetAttribute` | `(self, attribute, value) -> ()` | Store a game-data value on the prop. |
| `GetAttribute` | `(self, attribute) -> value` | Read an attribute. |
| `SetAttributes` | `(self, attributes: {[string]: any}) -> ()` | Set several attributes at once. |
| `GetAttributes` | `(self) -> {[string]: any}` | Get the whole attribute table. |
| `GetAttributeChanged` | `(self, attribute) -> Signal` | Returns an [event](/api/events.md) that fires whenever that one attribute changes. |
| `Destroy` | `(self) -> ()` | Tear down the prop, fire `Destroying`, and destroy `Model` if present. |

> Set `Position` and `Scale` through `SetCFrame` / `SetScale`, not by assigning the
> fields directly — direct assignment will not fire `Changed`.

## Events

See [Events](/api/events.md) for how to connect, disconnect and await.

| Event | Fires with | When |
|---|---|---|
| `Changed` | `(property: string, value: any)` | A tracked property (`Position`, `Scale`, …) changed. |
| `AttributeChanged` | `(name: string, value: any)` | Any attribute changed (via `SetAttribute`/`SetAttributes`). |
| `Destroying` | `(prop)` | The prop is being destroyed. |

```lua
prop.Changed:Connect(function(property, value)
    if property == "Position" then
        print("moved to", value)
    end
end)
```

## Properties

| Property | Type | Notes |
|---|---|---|
| `Id` | `string` | Unique id. |
| `Position` | `CFrame` | Current transform (set via `SetCFrame`). |
| `Scale` | `number` | Current multiplier (set via `SetScale`). |
| `OriginalScale` | `number` | The model's scale at creation = Scale `1`. |
| `MinScale` / `MaxScale` | `number` | Allowed scale range. |
| `CanScale` | `boolean` | When false, `Scale` is locked at `1`. |
| `ModelName` | `string` | Source model name. |
| `Importance` | `number` | Used for ordering. |
| `Model` | `Model?` | The rendered model this prop drives, if any. |
| `Destroyed` | `boolean` | True once destroyed. |
