# Events

Anything in ATF Suite that notifies you — a prop moving, a child spawning, an
object being destroyed — does it through an **event**. Every event is a `Signal`,
so the same handful of methods work everywhere.

> An event is a *property* that holds a `Signal`. You don't call it like a method —
> you **subscribe** to it.

## Listening

### Connect

```lua
event:Connect(callback) -> Connection
```

Runs `callback` every time the event fires.

```lua
local connection = prop.Changed:Connect(function(property, value)
    print(property, "changed to", value)
end)
```

### Once

```lua
event:Once(callback) -> Connection
```

Runs `callback` the next time the event fires, then disconnects itself.

```lua
prop.Destroying:Once(function()
    print("prop is gone")
end)
```

### Await

```lua
event:Await() -> ...
```

Yields the calling thread until the event fires, then returns the fired values.
Run it inside a coroutine (e.g. `task.spawn`).

```lua
task.spawn(function()
    local property, value = prop.Changed:Await()
    print("first change:", property, value)
end)
```

### Disconnecting

`Connect` and `Once` return a `Connection`. Call `:Disconnect()` on it to stop
listening.

```lua
local connection = crate.ChildAdded:Connect(onChild)
-- later…
connection:Disconnect()
```

## Where events are used

### Instance events

| Event | Found on | Fires with |
|---|---|---|
| `Changed` | [Prop](/api/prop.md) | `(property, value)` |
| `Destroying` | [Prop](/api/prop.md) | `(prop)` |
| `AttributeChanged` | [Prop](/api/prop.md) | `(name, value)` — any attribute change |
| `GetAttributeChanged(name)` | [Prop](/api/prop.md) | `(value)` — a per-attribute event |
| `ChildAdded` | [PropObject](/api/propobject.md) | `(prop)` |
| `ChildRemoved` | [PropObject](/api/propobject.md) | `(prop)` |

### Server events — `PropPlacer`

| Event | Fires with |
|---|---|
| `PropPlaced` | `(player, prop)` |
| `PropUpdated` | `(player, prop, property, value)` |
| `PropRemoved` | `(player, prop)` |

### Client events — `PropPlacer.BootClient()`

| Event | Fires with |
|---|---|
| `ModelReplicated` | `(modelName, master)` |
| `PropPlaced` | `(id, model)` |
| `PropUnloaded` | `(id, model)` |
| `PropAttributeChanged` | `(prop, name, value)` — `prop` is a [`ClientProp`](/api/propplacer.md#clientprop) |

See [PropPlacer](/api/propplacer.md) for the full server and client API.
