-- Rectangular exclusions apply only to structure-loss alarms.
-- Bind to surface identity as well as index: renames keep exclusions, deleted
-- surfaces cannot transfer an exclusion to a newly created surface.
local A={limit=64}
function A.copy(areas)
  local result={}
  for i,a in ipairs(areas or {}) do
    result[i]={name=a.name,enabled=a.enabled,surface=a.surface,surface_name=a.surface_name,
      left=a.left,top=a.top,right=a.right,bottom=a.bottom}
  end
  return result
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function A.create(surface,box)
  if not surface or not surface.valid or not box then return nil end
  local l,r=box.left_top,box.right_bottom
  if not l or not r or not finite(l.x) or not finite(l.y) or not finite(r.x) or not finite(r.y) then return nil end
  local left,right=math.min(l.x,r.x),math.max(l.x,r.x)
  local top,bottom=math.min(l.y,r.y),math.max(l.y,r.y)
  if left==right or top==bottom then return nil end
  return {name="",enabled=true,surface=surface,surface_name=surface.name,
    left=left,top=top,right=right,bottom=bottom}
end
function A.validate(areas)
  if #areas>A.limit then return false end
  for _,a in ipairs(areas) do
    if type(a.name)~="string" or #a.name>200 or type(a.enabled)~="boolean"
      or not finite(a.left) or not finite(a.top) or not finite(a.right) or not finite(a.bottom)
      or a.left>=a.right or a.top>=a.bottom then return false end
    -- A deleted surface is allowed in saved lists but can never match anything.
  end
  return true
end
function A.contains(areas,entity)
  for _,a in ipairs(areas or {}) do
    if a.enabled and a.surface and a.surface.valid and a.surface==entity.surface then
      local p=entity.position
      if p.x>=a.left and p.x<a.right and p.y>=a.top and p.y<a.bottom then return true end
    end
  end
  return false
end
function A.draw(a,player)
  return rendering.draw_rectangle{surface=a.surface,left_top={a.left,a.top},right_bottom={a.right,a.bottom},
    color={r=0.2,g=0.8,b=1,a=1},width=3,filled=false,time_to_live=600,
    players=player and {player} or nil}
end
return A
