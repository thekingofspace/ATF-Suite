# How Props Flow

Props are **owned by the server** and **rendered by the client**. The server never
sends a player props for a room they aren't standing in, and the client never
edits the real prop directly — it works on a clone and asks the server to commit.

These diagrams trace that path.

## Server → client: placing & rendering

A prop is registered and placed on the server. The player walks into its zone, the
client pulls the prop data, requests the model, and renders a clone.

```mermaid
flowchart TD
    subgraph server [Server]
        reg["RegisterProp / RegisterRoom"]
        place["PlaceProp(id, player)"]
        spawn["Zone:SpawnObject"]
        reg --> place --> spawn
    end

    subgraph client [Client]
        enter["Entered_Room"]
        getprops["GetProps — transform + attributes"]
        reqmodel["RequestPropModels"]
        onrep["OnReplication — cache master model"]
        render["renderProp"]
        cloned["clone on the map"]
        enter --> getprops --> render
        getprops --> reqmodel --> onrep --> render
        render --> cloned
    end

    spawn -->|walk into the zone| enter
    spawn -->|model via ReplicationPP| onrep
```

- **`GetProps`** carries the transform, scale limits, and **all the prop's
  attributes** — but only for rooms you're in.
- The **model** is replicated once via ReplicationPP and kept as a single hidden
  *master*; every rendered prop is a clone of it.
- `renderProp` waits for both the data and the master, then puts a clone on the map.

## Live updates

While you're in the room, the server broadcasts every change and the client
applies it to the matching clone.

```mermaid
flowchart TD
    change["server: SetCFrame / SetScale / SetAttribute"] --> bcast["BroadcastToRoom(GroupID)"]
    bcast --> moved["Prop_Moved"]
    bcast --> scaled["Prop_Scaled"]
    bcast --> attr["Prop_Attribute"]
    moved --> apply["client updates the clone"]
    scaled --> apply
    attr --> apply
    attr --> event["api.PropAttributeChanged fires"]
```

### How the zone scopes it

That broadcast is **room-scoped** — it only reaches players standing in the zone.
Each [Zone](/api/zone.md) runs a spatial observer that keeps the room roster:
walking in adds you, walking out drops you. `BroadcastToRoom` then delivers only to
whoever is currently on it.

```mermaid
flowchart TD
    obs["zone's spatial observer"]
    obs -->|player walks in| add["JoinRoom — added to the roster"]
    obs -->|player walks out| rem["LeaveRoom — removed from the roster"]
    add --> roster["room roster — players in the zone"]
    rem --> roster
    upd["a prop in the zone changes"] --> bc["BroadcastToRoom(GroupID)"]
    bc --> roster
    roster -->|on the roster| deliver["update delivered"]
    roster -->|off the roster| nothing["nothing sent"]
```

## Editing: client → server → back

Editing clones the rendered prop and hides the original. Nothing changes
server-side until you publish; the real prop only moves once the server confirms
and broadcasts the update back.

```mermaid
flowchart TD
    sel["click a prop you own"] --> edit["Build.Edit — clone, hide original"]
    edit --> handles["ScaleManager handles"]
    handles --> pub["Build.PublishFrom"]
    handles --> disc["Build.Discard"]
    pub --> upd["server UpdateProp — re-checks ownership"]
    upd --> bcast["Prop_Moved / Prop_Scaled"]
    bcast --> real["the real prop moves into place"]
    disc --> restore["original restored, nothing sent"]
```

`PublishFrom` returns `false` if the server dropped the request (cooldown, or a
check vetoed it) — and you stay in edit mode instead of losing your work.

## The prop lifecycle

```mermaid
stateDiagram-v2
    [*] --> Placed: PlaceProp / PublishFrom
    Placed --> Rendered: enter the room
    Rendered --> Rendered: Prop_Moved / Scaled / Attribute
    Rendered --> Editing: Build.Edit
    Editing --> Rendered: PublishFrom or Discard
    Rendered --> Grace: leave the room
    Grace --> Rendered: return within 5s
    Grace --> Unloaded: 5s grace elapses
    Rendered --> Removed: RemoveProp / ForceRemoveProp
    Unloaded --> [*]
    Removed --> [*]
```

- **Grace** — leaving a zone doesn't deload immediately. The clone is kept for 5
  seconds; come back and it stays (and re-syncs anything missed), otherwise it's
  destroyed.
- **Eviction** — separately, a master model nobody has cloned from for a while is
  dumped to free memory. The clones on the map stay; the model is re-requested if
  it's ever needed again.

See [PropPlacer](/api/propplacer.md) for the API behind each box.
