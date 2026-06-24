# Zone

A room: a logical group of props with spatial zones (built on QuickZone) and a
player listener list, used to replicate props to nearby players.

```lua
local Zone = require(PropPlacer.Zone)

local room = Zone.New("Lobby")
local prop = room:SpawnObject(crate, CFrame.new(0, 5, 0))
```

## Constructor

```lua
Zone.New(Owner: any?) -> Zone
```

Creates a room. `Owner` is optional and purely logical.

## Methods

| Method | Signature | Description |
|---|---|---|
| `SpawnObject` | `(self, Object: PropObject, Position: CFrame) -> Prop?` | Place a prop in the room — assigns it to (or grows) a nearby zone, registers the child, and broadcasts it to listeners. |
| `GenerateZone` | `(self, Position: CFrame, Size: Vector3) -> Zone` | Find / expand / create the spatial zone that covers a point (used internally by `SpawnObject`). |
| `Destroy` | `(self) -> ()` | Tear down the room and its zones. |

> Zone replicates over the network (Socket rooms / broadcasts), so it has no
> `Signal` events of its own — listen on the client via your Socket handlers
> (`Prop_Placed`, `Prop_Moved`, `Prop_Removed`, `Prop_Scaled`).

## Properties

| Property | Type | Notes |
|---|---|---|
| `GroupID` | `string` | Room id used for socket communication. |
| `Children` | `{Prop}` | Props currently in the room. |
| `Listeners` | `{Player}` | Players currently in the room. |
| `Zones` | `{QuickZone.Zone}` | The spatial zones backing the room. |
| `Linker` | `QuickZone.Observer` | Observer that tracks players entering/leaving. |
| `Owner` | `any` | Logical owner. |
