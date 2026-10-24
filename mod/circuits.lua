local C = {}
C.operators = {"<", "≤", "=", "≠", "≥", ">"}
local compare = {
  ["<"]=function(a,b) return a<b end, ["≤"]=function(a,b) return a<=b end,
  ["="]=function(a,b) return a==b end, ["≠"]=function(a,b) return a~=b end,
  ["≥"]=function(a,b) return a>=b end, [">"]=function(a,b) return a>b end
}
function C.matches(value, op, threshold) return compare[op](value, threshold) end
function C.location(r)
  local e=r.entity
  if e and e.valid then
    return {surface=e.surface.name,x=e.position.x,y=e.position.y,entity=e.name}
  end
  local p=r.place
  if p then return {surface=p.surface,x=p.x,y=p.y,entity=p.entity} end
end
function C.copy(rules)
  local out={}
  for i,r in ipairs(rules or {}) do
    local signal=r.signal and {type=r.signal.type,name=r.signal.name,quality=r.signal.quality}
    out[i]={name=r.name, entity=r.entity, wire=r.wire, signal=signal,place=C.location(r),
      op=r.op, threshold=r.threshold, delay=r.delay, enabled=r.enabled}
  end
  return out
end
local function connector(wire)
  return wire==2 and defines.wire_connector_id.circuit_green or defines.wire_connector_id.circuit_red
end
function C.network(r, eligible)
  local e=r.entity
  if not e or not e.valid or e.type~="electric-pole" or (eligible and not eligible(e)) then
    return nil,"source-lost"
  end
  local id=connector(r.wire)
  local network=e.get_circuit_network(id)
  if not network then return nil,"network-lost" end
  return network
end
function C.read(r, eligible)
  local network,err=C.network(r,eligible)
  if not network then return nil,err end
  local e=r.entity
  local id=connector(r.wire)
  if not r.signal then return nil,"signal-required" end
  local ok,value=pcall(function() return e.get_signal(r.signal,id) end)
  if not ok then return nil,"signal-required" end
  return value
end
function C.validate(r, eligible)
  if type(r.name)~="string" or not r.name:match("%S") or #r.name>100 then return "invalid-rule" end
  if not r.signal or not r.signal.name or not ({item=true,fluid=true,virtual=true})[r.signal.type or "item"] then return "signal-required" end
  local proto = r.signal.type=="fluid" and prototypes.fluid[r.signal.name]
    or r.signal.type=="virtual" and prototypes.virtual_signal[r.signal.name]
    or (r.signal.type==nil or r.signal.type=="item") and prototypes.item[r.signal.name]
  if not proto or (r.signal.quality and not prototypes.quality[r.signal.quality]) then return "signal-required" end
  if not compare[r.op] or (r.wire~=1 and r.wire~=2) then return "invalid-rule" end
  for _,key in ipairs({"threshold","delay"}) do
    local v=r[key]
    if type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return "invalid-rule" end
  end
  if r.threshold%1~=0 or r.threshold< -2147483648 or r.threshold>2147483647 or r.delay<0 or r.delay>604800 then return "invalid-rule" end
  -- Disabled broken rules may be saved, allowing admins to disable a lost source.
  if r.enabled then local _,err=C.read(r,eligible); if err then return err end end
end
function C.poll(rules, offline, eligible, trip)
  for _,r in ipairs(rules or {}) do
    if r.enabled then
      r.place=C.location(r)
      local value,err=C.read(r,eligible)
      r.value,r.problem=value,err
      r.match=not err and C.matches(value,r.op,r.threshold) or false
      if offline and err then
        r.since=nil
        trip({"fnw-message.circuit-lost",r.name},C.location(r))
        return
      elseif offline and r.match then
        r.since=r.since or game.tick
        if game.tick-r.since>=r.delay*60 then
          trip({"fnw-message.circuit",r.name,value,r.op,r.threshold},C.location(r))
          return
        end
      else r.since=nil end
    else r.since,r.value,r.problem,r.match=nil,nil,nil,false end
  end
end
function C.status()
  local out={}
  for i,r in ipairs((storage.guard or {}).circuits or {}) do
    out[i]={name=r.name,enabled=r.enabled,value=r.value,problem=r.problem,match=r.match,since=r.since}
  end
  return out
end
function C.reset()
  for _,r in ipairs((storage.guard or {}).circuits or {}) do r.since=nil end
end
return C
