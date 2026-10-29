-- Exact entity prototype exclusions, independent of quality and surface.
local E={limit=128}
function E.list(lookup)
  local names={}
  for name,enabled in pairs(lookup or {}) do if enabled then names[#names+1]=name end end
  table.sort(names)
  return names
end
function E.compile(names,existing)
  if #names>E.limit then return nil,"building-limit" end
  local lookup={}
  for _,name in ipairs(names) do
    if type(name)~="string" or #name>200 then return nil,"invalid-building" end
    if name~="" then
      -- Preserve exclusions for temporarily removed mods. They are harmless
      -- while absent and can still be removed through the GUI.
      if not prototypes.entity[name] and not (existing or {})[name] then return nil,"invalid-building",name end
      lookup[name]=true
    end
  end
  return lookup
end
function E.contains(lookup,entity) return (lookup or {})[entity.name]==true end
return E
