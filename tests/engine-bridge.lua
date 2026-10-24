-- Test bridge present only in this isolated engine-test copy, never in the release.
commands.add_command("fnw-it-rule", "Integration test only", function(cmd)
  local args=helpers.json_to_table(cmd.parameter)
  if args.clear then state().circuits={};return end
  local r={name="Engine circuit",entity=game.surfaces.nauvis.find_entities_filtered{type="electric-pole"}[1],
    wire=args.wire or 1,signal=args.signal or {type="virtual",name="signal-A"},op=args.op or ">",threshold=args.threshold or 0,delay=args.delay or 0,enabled=true}
  local err=Circuits.validate(r,protected)
  if err then rcon.print("INVALID:"..err);return end
  local copied=Circuits.copy({r})
  assert(copied[1]~=r and copied[1].signal~=r.signal)
  assert(copied[1].entity==r.entity)
  local old=r.signal.name
  r.signal.name="signal-everything"
  assert(copied[1].signal.name==old)
  state().circuits=copied
  rcon.print("COPIED")
end)
