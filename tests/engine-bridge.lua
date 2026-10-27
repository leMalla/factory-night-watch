-- Test bridge present only in this isolated engine-test copy, never in the release.
-- Many prototypes lack get-by-unit-number: use the test map's actual entities.
local function test_entity(unit)
  for _,e in pairs(game.surfaces.nauvis.find_entities_filtered{force="player"}) do
    if e.unit_number==unit then return e end
  end
end
commands.add_command("fnw-it-rule", "Integration test only", function(cmd)
  local args=helpers.json_to_table(cmd.parameter)
  if args.clear then state().circuits={};return end
  local r={name="Engine circuit",entity=args.unit and test_entity(args.unit) or game.surfaces.nauvis.find_entities_filtered{type="electric-pole"}[1],connector=args.connector,
    wire=args.wire or 1,signal=args.signal or {type="virtual",name="signal-A"},op=args.op or ">",threshold=args.threshold or 0,delay=args.delay or 0,enabled=true}
  local err=Circuits.validate(r,protected)
  if err then rcon.print("INVALID:"..err);return end
  local copied=Circuits.copy({r})
  assert(copied[1]~=r and copied[1].signal~=r.signal)
  assert(copied[1].entity==r.entity)
  local old=r.signal.name
  r.signal.name="signal-everything"
  assert(copied[1].signal.name==old)
  local rules={}
  for i=1,(args.count or 1) do rules[i]=Circuits.copy(copied)[1] end
  state().circuits=rules
  rcon.print("COPIED")
end)
commands.add_command('fnw-it-networks','Integration test only',function(cmd)
  local args=helpers.json_to_table(cmd.parameter)
  local entities={}
  for _,id in ipairs(args.entities) do local e=test_entity(id);if e then entities[#entities+1]=e end end
  local options,err=Circuits.candidates(entities,protected)
  local out={}
  for _,r in ipairs(options or {}) do
    r.signal={type='virtual',name='signal-A',quality='normal'}
    out[#out+1]={id=Circuits.network(r).network_id,connector=r.connector,wire=r.wire,port=Circuits.port(r),value=Circuits.read(r)}
  end
  rcon.print(helpers.table_to_json({options=out,error=err}))
end)
commands.add_command('fnw-it-areas','Integration test only',function(cmd)
  local args=helpers.json_to_table(cmd.parameter)
  if args.clear then state().excluded_areas={};return end
  if args.draw then local objects=Areas.draw(state().excluded_areas[1]);rcon.print(tostring(#objects==2 and objects[1].valid and objects[2].valid and objects[1].render_mode=="game" and objects[2].render_mode=="chart" and objects[1].time_to_live==0 and objects[2].time_to_live==0));Areas.clear(objects);return end
  if args.probe then rcon.print(tostring(Areas.contains(state().excluded_areas,{surface=game.surfaces[args.surface],position={x=args.x,y=args.y}})));return end
  if args.status then
    local out={}
    for _,a in ipairs(state().excluded_areas or {}) do
      out[#out+1]={name=a.name,enabled=a.enabled,surface=a.surface and a.surface.valid and a.surface.name or a.surface_name,left=a.left,right=a.right,top=a.top,bottom=a.bottom}
    end
    rcon.print(helpers.table_to_json(out));return
  end
  local surface=game.surfaces[args.surface or 'nauvis']
  local a=assert(Areas.create(surface,{left_top={x=args.left,y=args.top},right_bottom={x=args.right,y=args.bottom}}))
  a.name=args.name or 'Engine exclusion';a.enabled=args.enabled~=false
  state().excluded_areas=state().excluded_areas or {}
  table.insert(state().excluded_areas,a)
end)
