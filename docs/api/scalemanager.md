# ScaleManager

A client-side editor that wraps one or more props in a handle-driven container
for moving, rotating and (single-prop) resizing.

```lua
local ScaleManager = require(PropPlacer.ScaleManager)

local editor = ScaleManager.New(prop) -- or a list: ScaleManager.New({ propA, propB })
editor:SetMode("Rotate")
editor:SetSmoothness("Rotation", 90) -- rotation snaps to 15 / 90 / 180 / 360 only
```

## Constructor

```lua
ScaleManager.New(props: Prop | { Prop }) -> ScaleManager
```

Cradles the prop(s) in an editable container with Move/Rotate/Resize handles and
a highlight. One prop can be resized; multiple props can only be moved/rotated.

## Methods

| Method | Signature | Description |
|---|---|---|
| `SetMode` | `(self, mode) -> ScaleManager` | Switch the active handle set — `"Move"`, `"Resize"` or `"Rotate"`. `Resize` is rejected for multi-prop selections. |
| `GetMode` | `(self) -> Mode` | Current mode. |
| `SetSmoothness` | `(self, kind, value: number) -> ScaleManager` | Grid snapping per axis — `kind` is `"Position"`, `"Rotation"` or `"Scale"`. `Rotation` is coerced to the nearest of `15 / 90 / 180 / 360`. |
| `Reflow` | `(self) -> ()` | Re-fit the handles/highlight to the props' current bounds. |
| `Restore` | `(self) -> ()` | Reset every prop to the position/scale it had when editing began. |
| `Destroy` | `(self) -> ()` | Bake the final transforms back into the props (for saving) and remove the container/handles. |

> ScaleManager drives the props directly and has no `Signal` events.

## Properties

| Property | Type | Notes |
|---|---|---|
| `Container` | `Model` | The temporary container holding the edited models. |
| `Props` | `{Prop}` | The props being edited. |
| `Mode` | `Mode` | Current handle mode. |
| `CanResize` | `boolean` | True only when editing a single prop. |
| `Smoothness` | `{Position, Rotation, Scale}` | Current snap increments. |
