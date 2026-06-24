export type switch = (Case:string, ...any) -> ...any
return function(Cases:{[any]:(...any) -> any}):switch
    return setmetatable(Cases, {
    __call = function(self, Case:string, ...)
        local NewCase:any = rawget(self, Case) or rawget(self, "default")
        if NewCase then
            return NewCase(...)
        end
        return
    end
})
end
