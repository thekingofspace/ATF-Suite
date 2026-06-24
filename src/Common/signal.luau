local module = {}

export type Connection = {
    Disconnect:(self:Connection) -> (),
    src:(...any) -> ...any
}

export type Signal<t...> = {
    Mode:"Deffered" | "Serial", -- deffered means the threads are run via task.defer. serial means they run one after another this can lead to hi wait times
    Connect:(self:Signal<t...>, sink:(t...) -> ...any) -> Connection,
    Once:(self:Signal<t...>, sink:(t...) -> ...any) -> Connection,

    Attatch:(self:Signal<t...>, sink:( {[string]:any}, t...) -> ...any) -> Connection, 

    Fire:(self:Signal<t...>, t...) -> (),
    FireWith:(self:Signal<t...>, Tuples:{any}, Meta:{[string]:any}) -> (), 

    Invoke:(self:Signal<t...>, t...) -> ...any,
    InvokePersitent:(self:Signal<t...>, t...) -> {{any}},

    InvokeWith:(self:Signal<t...>, Tuples:{any}, Meta:{[string]:any}) -> ...any,
    InvokeWithPersitent:(self:Signal<t...>, Tuples:{any}, Meta:{[string]:any}) -> {{any}},

    ---@yields
    Await:(self:Signal<t...>) -> ...any,

    Destroy:(self:Signal<t...>) -> (),
}

type ConnectionObject = {
    Disconnect:(self:ConnectionObject) -> (),
    src:(...any) -> ...any,
    _signal:SignalObject,
    _meta:boolean,
    _once:boolean,
    _connected:boolean,
    _next:ConnectionObject?,
}

type SignalObject = {
    Mode:"Deffered" | "Serial",
    _head:ConnectionObject?,
    _metaHead:ConnectionObject?,
    _waiting:{thread},
}

local Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self:ConnectionObject)
    if not self._connected then
        return
    end
    self._connected = false

    local signal = self._signal
    local head = if self._meta then signal._metaHead else signal._head

    if head == self then
        if self._meta then
            signal._metaHead = self._next
        else
            signal._head = self._next
        end
    else
        local prev = head
        while prev and prev._next ~= self do
            prev = prev._next
        end
        if prev then
            prev._next = self._next
        end
    end
end

local function createConnection(signal:SignalObject, sink:(...any) -> ...any, meta:boolean, once:boolean):ConnectionObject
    local node = setmetatable({
        src = sink,
        _signal = signal,
        _meta = meta,
        _once = once,
        _connected = true,
        _next = if meta then signal._metaHead else signal._head,
    }, Connection)

    if meta then
        signal._metaHead = node :: any
    else
        signal._head = node :: any
    end

    return node :: any
end

local function collectLast(head:ConnectionObject?, args:{any}, argc:number):{any}?
    local last:{any}? = nil
    local node = head
    while node do
        local nextNode = node._next
        if node._connected then
            local returns = table.pack(node.src(table.unpack(args, 1, argc)))
            if returns.n > 0 then
                last = returns
            end
            if node._once then
                node:Disconnect()
            end
        end
        node = nextNode
    end
    return last
end

local function collectAll(head:ConnectionObject?, args:{any}, argc:number):{{any}}
    local results = {}
    local node = head
    while node do
        local nextNode = node._next
        if node._connected then
            local returns = table.pack(node.src(table.unpack(args, 1, argc)))
            if returns.n > 0 then
                table.insert(results, returns)
            end
            if node._once then
                node:Disconnect()
            end
        end
        node = nextNode
    end
    return results
end

local function metaArgs(Tuples:{any}, Meta:{[string]:any}):({any}, number)
    local args = {Meta}
    table.move(Tuples, 1, #Tuples, 2, args)
    return args, #Tuples + 1
end


local Signal = {}
Signal.__index = Signal

function Signal.Connect(self:SignalObject, sink:(...any) -> ...any)
    return createConnection(self, sink, false, false)
end

function Signal.Once(self:SignalObject, sink:(...any) -> ...any)
    return createConnection(self, sink, false, true)
end

function Signal.Attatch(self:SignalObject, sink:(...any) -> ...any)
    return createConnection(self, sink, true, false)
end

function Signal.Fire(self:SignalObject, ...)
    local node = self._head
    while node do
        local nextNode = node._next
        if node._connected then
            if node._once then
                node:Disconnect()
            end
            if self.Mode == "Deffered" then
                task.defer(node.src, ...)
            else
                local ok, err = pcall(node.src, ...)
                if not ok then
                    task.spawn(error, err)
                end
            end
        end
        node = nextNode
    end

    if #self._waiting > 0 then
        local waiting = self._waiting
        self._waiting = {}
        for _, thread in waiting do
            task.spawn(thread, ...)
        end
    end
end

function Signal.FireWith(self:SignalObject, Tuples:{any}, Meta:{[string]:any})
    local node = self._metaHead
    while node do
        local nextNode = node._next
        if node._connected then
            if node._once then
                node:Disconnect()
            end
            if self.Mode == "Deffered" then
                task.defer(node.src, Meta, table.unpack(Tuples))
            else
                local ok, err = pcall(node.src, Meta, table.unpack(Tuples))
                if not ok then
                    task.spawn(error, err)
                end
            end
        end
        node = nextNode
    end
end

function Signal.Invoke(self:SignalObject, ...)
    local args = table.pack(...)
    local last = collectLast(self._head, args, args.n)
    if last then
        return table.unpack(last, 1, last.n)
    end
    return
end

function Signal.InvokePersitent(self:SignalObject, ...)
    local args = table.pack(...)
    return collectAll(self._head, args, args.n)
end

function Signal.InvokeWith(self:SignalObject, Tuples:{any}, Meta:{[string]:any})
    local args, argc = metaArgs(Tuples, Meta)
    local last = collectLast(self._metaHead, args, argc)
    if last then
        return table.unpack(last, 1, last.n)
    end
    return
end

function Signal.InvokeWithPersitent(self:SignalObject, Tuples:{any}, Meta:{[string]:any})
    local args, argc = metaArgs(Tuples, Meta)
    return collectAll(self._metaHead, args, argc)
end

function Signal.Await(self:SignalObject)
    table.insert(self._waiting, coroutine.running())
    return coroutine.yield()
end

-- Disconnects every connection (both normal and meta) and clears the signal.
-- Held Connection references will report as disconnected afterwards.
function Signal.Destroy(self:SignalObject)
    local node = self._head
    while node do
        local nextNode = node._next
        node._connected = false
        node._next = nil
        node = nextNode
    end
    self._head = nil

    node = self._metaHead
    while node do
        local nextNode = node._next
        node._connected = false
        node._next = nil
        node = nextNode
    end
    self._metaHead = nil
end

function module.new(Mode:("Deffered" | "Serial")?):Signal<...any>
    local self = setmetatable({
        Mode = Mode or "Serial",
        _head = nil,
        _metaHead = nil,
        _waiting = {},
    }, Signal)

    return (self :: any) :: Signal<...any>
end

return module
