local G={}
local C=require("circuits")
local A=require("areas")
local E=require("exclusions")
local callbacks={}
local ROOT="fnw_window"
local PREVIEW="fnw_area_preview"
local LAYOUT=4
-- Suppress only synchronous close notifications caused by our own teardown.
local internal_close={}
local build
local keys={"enabled","max-offline-hours","research-pause","research-idle-minutes","destruction-pause","ignore-walls","ignore-robots","emergency-save","forces","excluded-surfaces"}
local function tr(key,...) return {"fnw-gui."..key,...} end
local function opt(key) return settings.global["fnw-"..key].value end
local function state() storage.fnw_ui=storage.fnw_ui or {};return storage.fnw_ui end
local function ui(p)
  local all=state(); all[p.index]=all[p.index] or {tab=1}; return all[p.index]
end
local function window(p) return p.gui.screen[ROOT] end
local function find(e,name)
  if not e then return end
  if e.name==name then return e end
  for _,child in pairs(e.children) do local r=find(child,name);if r then return r end end
end
local function duration(ticks)
  local sec=math.max(0,math.floor(ticks/60))
  return string.format("%dd %02dh %02dm",math.floor(sec/86400),math.floor(sec/3600)%24,math.floor(sec/60)%60)
end
local function settings_changed(d)
  if not d.baseline then return true end
  for _,key in ipairs(keys) do
    if d.baseline[key]~=opt(key) then return true end
  end
  return false
end
local function stop_preview(p)
  local d=ui(p)
  if d.preview then A.clear(d.preview.objects);d.preview=nil end
  local panel=p.gui.screen[PREVIEW]
  if panel then panel.destroy() end
end
local function preview_panel(p)
  local d=ui(p)
  if not d.preview then return end
  local panel=p.gui.screen[PREVIEW]
  if not panel then
    panel=p.gui.screen.add{type="frame",name=PREVIEW,direction="vertical"}
    panel.style.width=400;panel.location={x=20,y=80}
    local title=panel.add{type="label",caption=tr("area-preview"),style="frame_title"}
    title.style.single_line=false;title.style.width=360
    local status=panel.add{type="label",name="fnw_preview_status",caption=""}
    status.style.single_line=false;status.style.width=360
    local back=panel.add{type="button",name="fnw_preview_return",caption=tr("preview-return")}
    back.style.width=360
    local save=panel.add{type="button",name="fnw_preview_save",caption=tr("preview-save")}
    save.style.width=360;save.tooltip=tr("preview-save-help")
  end
  local stale=settings_changed(d) or d.revision~=((storage.guard or {}).circuit_revision or 0)
  panel.fnw_preview_status.caption=tr(stale and "preview-stale" or d.dirty and "preview-unsaved" or "preview-saved")
  panel.fnw_preview_save.visible=d.dirty
  panel.fnw_preview_save.enabled=p.admin and d.dirty
  -- Do not assign player.opened: this panel must not intercept map interaction.
end
local function load(p)
  local d=ui(p);d.values={};d.baseline={}
  for _,k in ipairs(keys) do d.values[k]=opt(k);d.baseline[k]=opt(k) end
  local hours=opt("max-offline-hours")
  d.limit=hours>0;d.unit=hours%24==0 and 2 or 1;d.time=tostring(hours>0 and hours/(d.unit==2 and 24 or 1) or 7)
  d.excluded_entities=E.list((storage.guard or {}).excluded_entities)
  d.areas=A.copy((storage.guard or {}).excluded_areas)
  d.circuits=C.copy((storage.guard or {}).circuits)
  d.revision=(storage.guard or {}).circuit_revision or 0
  d.dirty=false;d.confirm=nil;d.feedback=nil
end
local function destroy(p)
  local f=window(p)
  if f then
    ui(p).position=f.location
    local tabs=find(f,"fnw_tabs");if tabs then ui(p).tab=tabs.selected_tab_index end
    internal_close[p.index]=true
    if p.opened==f then p.opened=nil end
    if f.valid then f.destroy() end
    internal_close[p.index]=nil
  end
end
local function label(parent,text)
  local e=parent.add{type="label",caption=text}
  e.style.single_line=false;e.style.width=520
  return e
end
local function button(parent,name,key,edit)
  return parent.add{type="button",name=name,caption=tr(key),tags={fnw_edit=edit or false}}
end
local function row(parent,key,element)
  local f=parent.add{type="flow",direction="horizontal"}
  local l=f.add{type="label",caption=tr(key)};l.style.width=280;l.style.single_line=false
  local e=f.add(element);e.tags={fnw_edit=true};if element.type=="textfield" then e.style.width=190 end
  return e
end
local function checkbox(parent,p,key)
  return parent.add{type="checkbox",name="fnw_v_"..key,caption={"mod-setting-name.fnw-"..key},state=ui(p).values[key],tags={fnw_edit=true},tooltip={"mod-setting-description.fnw-"..key}}
end
local function network_caption(r)
  if not r.entity then return tr("no-network") end
  local network,err=C.network(r,callbacks.eligible)
  if not network then return tr(err) end
  return tr("network-label",network.network_id,tr(r.wire==2 and "green" or "red"),tr(C.port(r),C.connector_id(r)),r.entity.surface.name)
end
local function network_option(r)
  local network,err=C.network(r,callbacks.eligible)
  if not network then return tr(err) end
  return tr("network-option",tr(r.wire==2 and "green" or "red"),tr(C.port(r),C.connector_id(r)),network.network_id,r.entity.surface.name)
end
local function choices(r)
  if not r.choices then r.choices=C.candidates(r.entity and r.entity.valid and {r.entity} or {},callbacks.eligible,r) or {} end
  local items={tr("choose-network")};local selected=1
  for i,option in ipairs(r.choices) do
    items[#items+1]=network_option(option)
    if option.entity==r.entity and C.connector_id(option)==C.connector_id(r) then selected=i+1 end
  end
  return items,selected
end
local function choose(r,option)
  r.entity=option and option.entity or nil
  r.connector=option and option.connector or nil
  r.wire=option and option.wire or 1
  r.place=option and C.location(option) or nil
end
local function excluded_caption(name)
  if name=="" then return tr("choose-building") end
  local prototype=prototypes.entity[name]
  return prototype and prototype.localised_name or tr("missing-building",name)
end
local function circuit_editor(parent,p,i,r)
  local box=parent.add{type="frame",direction="vertical",style="inside_shallow_frame"}
  local head=box.add{type="flow",direction="horizontal"}
  head.add{type="checkbox",name="fnw_c_enabled_"..i,caption=tr("rule",i),state=r.enabled,tags={fnw_edit=true}}
  button(head,"fnw_remove_"..i,"remove",true)
  row(box,"name",{type="textfield",name="fnw_c_name_"..i,text=r.name})
  local source=box.add{type="flow",direction="horizontal"}
  button(source,"fnw_select_"..i,"select-network",true)
  local l=source.add{type="label",name="fnw_c_network_"..i,caption=network_caption(r)}
  l.style.width=330;l.style.single_line=false
  local items,selected=choices(r)
  local network_row=box.add{type="flow",direction="vertical"}
  network_row.add{type="label",caption=tr("network")}
  local selector=network_row.add{type="drop-down",name="fnw_c_connection_"..i,items=items,selected_index=selected,tags={fnw_edit=true}}
  selector.style.width=520
  row(box,"signal",{type="choose-elem-button",name="fnw_c_signal_"..i,elem_type="signal",signal=r.signal})
  row(box,"operator",{type="drop-down",name="fnw_c_op_"..i,items=C.operators,selected_index=(function() for n,v in ipairs(C.operators) do if v==r.op then return n end end return 6 end)()})
  row(box,"threshold",{type="textfield",name="fnw_c_threshold_"..i,text=tostring(r.threshold)})
  row(box,"delay",{type="textfield",name="fnw_c_delay_"..i,text=tostring(r.delay)})
  local status=label(box,"");status.name="fnw_c_status_"..i
end
function G.configure(c) callbacks=c end
function G.close_preview(p)
  if p and p.valid then stop_preview(p) end
end
function G.remove_player(index)
  local d=storage.fnw_ui and storage.fnw_ui[index]
  if d and d.preview then A.clear(d.preview.objects) end
  if storage.fnw_ui then storage.fnw_ui[index]=nil end
  internal_close[index]=nil
end
function G.ensure(p)
  if not p or not p.valid then return end
  local legacy=p.gui.top.fnw_toggle;if legacy then legacy.destroy() end
  local d=ui(p)
  if not d.excluded_entities then d.excluded_entities=E.list((storage.guard or {}).excluded_entities) end
  if not d.areas then d.areas=A.copy((storage.guard or {}).excluded_areas) end
  local old=window(p)
  if old and (old.tags.fnw_layout~=LAYOUT or not find(old,"fnw_tabs") or not find(old,"fnw_jump") or not find(old,"fnw_confirm_panel")) then destroy(p);state()[p.index]=nil end
  p.set_shortcut_available("fnw-open",true)
end
function G.refresh(p)
  local f=window(p);if not f then preview_panel(p);return end
  local s=storage.guard or {};local d=ui(p)
  -- Clean forms track server changes. Dirty drafts retain their inputs and are
  -- checked against the captured baseline before they may change server state.
  if not d.dirty and (settings_changed(d) or d.revision~=(s.circuit_revision or 0)) then
    load(p);build(p);return
  end
  local status=s.alarm and "alarm" or game.tick_paused and "paused" or #game.connected_players>0 and "online" or "offline"
  find(f,"fnw_status").caption=tr("status",tr("status-"..status))
  find(f,"fnw_elapsed").caption=tr(s.offline_since and "elapsed" or "last-elapsed",duration(s.offline_since and game.tick-s.offline_since or s.last_offline_ticks or 0))
  local limit=opt("max-offline-hours")
  find(f,"fnw_remaining").caption=limit==0 and tr("unlimited") or tr("remaining",duration(limit*216000-(s.offline_since and game.tick-s.offline_since or 0)))
  local last=s.alarm or s.last_alarm
  local alarm=last and last.reason or tr("no-alarm")
  if last and last.place then local l=last.place;alarm={"",alarm,"\n",l.surface,string.format(" · %.1f, %.1f",l.x,l.y)} end
  find(f,"fnw_alarm").caption=alarm
  local jump=find(f,"fnw_jump")
  jump.visible=last~=nil and last.place~=nil
  local place=last and last.place
  local surface=place and game.surfaces[place.surface]
  jump.enabled=surface~=nil and surface.valid
  local resume=find(f,"fnw_resume");resume.visible=s.alarm~=nil;resume.enabled=p.admin
  find(f,"fnw_permissions").caption=tr(p.admin and "admin" or "read-only")
  find(f,"fnw_apply").enabled=p.admin and d.dirty
  find(f,"fnw_reload").enabled=d.dirty
  -- A previous save confirmation must never describe a newly edited draft.
  if d.dirty and d.feedback and d.feedback[1]=="fnw-gui.saved" then d.feedback=nil end
  find(f,"fnw_feedback").caption=d.feedback or ""
  find(f,"fnw_changes").caption=tr(d.dirty and "unsaved" or "clean")
  find(f,"fnw_confirm_panel").visible=d.confirm~=nil
  find(f,"fnw_confirmation_text").caption=tr(d.confirm=="test" and "test-warning" or "discard-warning")
  local function permissions(e)
    if e.tags.fnw_edit then e.enabled=p.admin end
    for _,c in pairs(e.children) do permissions(c) end
  end
  permissions(f)
  for i,name in ipairs(d.excluded_entities) do
    find(f,"fnw_e_caption_"..i).caption=excluded_caption(name)
  end
  for i,r in ipairs(d.circuits) do
    find(f,"fnw_c_network_"..i).caption=network_caption(r)
    local items,selected=choices(r)
    local dropdown=find(f,"fnw_c_connection_"..i)
    dropdown.items=items;dropdown.selected_index=selected;dropdown.enabled=p.admin and #items>1
    local value,problem=C.read(r,callbacks.eligible)
    local live=(s.circuits or {})[i]
    local text
    if not r.enabled then text=tr("circuit-disabled")
    elseif not r.signal then text=tr("signal-required")
    elseif problem then text=tr(problem)
    elseif not tonumber(r.threshold) then text=tr("invalid-rule")
    else
      local matching=C.matches(value,r.op,tonumber(r.threshold))
      text=tr("circuit-status",value,tr(matching and "condition-true" or "condition-false"))
      if not d.dirty and live and live.since and not s.alarm then
        text={"",text," · ",tr("delay-progress",math.floor((game.tick-live.since)/60),r.delay)}
      end
    end
    find(f,"fnw_c_status_"..i).caption=text
  end
end
function G.refresh_all()
  for _,p in pairs(game.players or {}) do G.ensure(p);G.refresh(p) end
end
build=function(p)
  local old=window(p)
  if old then
    local pane=find(old,"fnw_tabs");ui(p).tab=pane.selected_tab_index
    destroy(p)
  end
  local d=ui(p)
  local f=p.gui.screen.add{type="frame",name=ROOT,direction="vertical",tags={fnw_layout=LAYOUT}};f.style.width=620
  local title=f.add{type="flow",direction="horizontal"}
  title.add{type="label",caption="Factory Night Watch",style="frame_title"}
  local drag=title.add{type="empty-widget",style="draggable_space_header"};drag.style.horizontally_stretchable=true;drag.style.height=24;drag.drag_target=f
  title.add{type="sprite-button",name="fnw_close",sprite="utility/close",style="frame_action_button",tooltip=tr("close")}
  local tabs=f.add{type="tabbed-pane",name="fnw_tabs"}
  local pages={}
  for i,k in ipairs({"overview","rules","advanced"}) do
    local tab=tabs.add{type="tab",caption=tr(k)}
    local pane=tabs.add{type="scroll-pane"}
    pane.style.width=580;pane.style.height=460
    tabs.add_tab(tab,pane);pages[i]=pane.add{type="flow",direction="vertical"}
  end
  tabs.selected_tab_index=d.tab or 1
  local overview=pages[1]
  label(overview,"").name="fnw_status";label(overview,"").name="fnw_elapsed";label(overview,"").name="fnw_remaining"
  row(overview,"mode",{type="drop-down",name="fnw_mode",items={tr("mode-protected"),tr("mode-pause")},selected_index=d.values.enabled and 1 or 2})
  label(overview,tr("mode-help"));label(overview,tr("last-alarm"))
  label(overview,"").name="fnw_alarm";button(overview,"fnw_jump","jump",false);button(overview,"fnw_resume","resume",false)
  local rules=pages[2]
  checkbox(rules,p,"destruction-pause");label(rules,tr("destruction-help"))
  checkbox(rules,p,"research-pause")
  row(rules,"research-delay",{type="textfield",name="fnw_v_research-idle-minutes",text=tostring(d.values["research-idle-minutes"])})
  label(rules,tr("research-help"))
  rules.add{type="checkbox",name="fnw_limit",caption=tr("time-limit"),state=d.limit,tags={fnw_edit=true}}
  local time=rules.add{type="flow",direction="horizontal"}
  local input=time.add{type="textfield",name="fnw_time",text=d.time,tags={fnw_edit=true}};input.style.width=100
  time.add{type="drop-down",name="fnw_unit",items={tr("hours"),tr("days")},selected_index=d.unit,tags={fnw_edit=true}}
  label(rules,tr("simulation-help"))
  local adv=pages[3]
  label(adv,tr("exceptions"));checkbox(adv,p,"ignore-walls");checkbox(adv,p,"ignore-robots")
  label(adv,tr("excluded-buildings"));label(adv,tr("excluded-buildings-help"))
  if #d.excluded_entities==0 then label(adv,tr("no-excluded-buildings")) end
  for i,name in ipairs(d.excluded_entities) do
    local line=adv.add{type="flow",direction="horizontal"}
    line.add{type="choose-elem-button",name="fnw_e_entity_"..i,elem_type="entity",
      entity=prototypes.entity[name] and name or nil,elem_filters={{filter="flag",flag="player-creation"}},tags={fnw_edit=true}}
    local caption=line.add{type="label",name="fnw_e_caption_"..i,caption=excluded_caption(name)}
    caption.style.width=300;caption.style.single_line=false
    button(line,"fnw_e_remove_"..i,"remove",true)
  end
  button(adv,"fnw_e_add","add-excluded-building",true)
  label(adv,tr("areas"));label(adv,tr("areas-help"))
  if #d.areas==0 then label(adv,tr("no-areas")) end
  for i,a in ipairs(d.areas) do
    local box=adv.add{type="frame",direction="vertical",style="inside_shallow_frame"}
    box.add{type="checkbox",name="fnw_a_enabled_"..i,caption=tr("area",i),state=a.enabled,tags={fnw_edit=true}}
    row(box,"name",{type="textfield",name="fnw_a_name_"..i,text=a.name})
    local surface=a.surface and a.surface.valid and a.surface.name or a.surface_name
    label(box,tr("area-bounds",surface,string.format("%.1f, %.1f",a.left,a.top),string.format("%.1f, %.1f",a.right,a.bottom)))
    local actions=box.add{type="flow",direction="horizontal"}
    local view=button(actions,"fnw_area_view_"..i,"view-area",false)
    view.enabled=a.surface~=nil and a.surface.valid
    button(actions,"fnw_area_remove_"..i,"remove",true)
  end
  button(adv,"fnw_area_add","add-area",true)
  checkbox(adv,p,"emergency-save")
  label(adv,tr("circuits"));label(adv,tr("circuits-help"))
  if #d.circuits==0 then label(adv,tr("no-circuits")) end
  for i,r in ipairs(d.circuits) do circuit_editor(adv,p,i,r) end
  button(adv,"fnw_add","add-circuit",true)
  button(adv,"fnw_compatibility","compatibility",false)
  if d.compatibility then
    row(adv,"forces",{type="textfield",name="fnw_v_forces",text=d.values.forces})
    row(adv,"excluded-surfaces",{type="textfield",name="fnw_v_excluded-surfaces",text=d.values["excluded-surfaces"]})
    label(adv,tr("compatibility-help"))
  end
  button(adv,"fnw_test","test",true)
  label(f,"").name="fnw_permissions"
  local feedback=label(f,d.feedback or "");feedback.name="fnw_feedback"
  -- Keep confirmation widgets in place. Native close events must never open
  -- another GUI: the engine may immediately close that replacement again.
  local panel=f.add{type="flow",name="fnw_confirm_panel",direction="vertical",visible=false}
  label(panel,"").name="fnw_confirmation_text"
  local confirm=panel.add{type="flow",direction="horizontal"}
  button(confirm,"fnw_confirm","confirm",false);button(confirm,"fnw_cancel","cancel",false)
  local footer=f.add{type="flow",direction="horizontal"}
  button(footer,"fnw_apply","apply",false);button(footer,"fnw_reload","discard",false)
  footer.add{type="label",name="fnw_changes",caption=""}
  if d.position then f.location=d.position else f.force_auto_center() end
  p.opened=f
  G.refresh(p)
end
function G.open(p)
  stop_preview(p)
  G.ensure(p)
  if not ui(p).values or (not window(p) and not ui(p).selecting and not ui(p).selecting_area and not ui(p).dirty) then load(p) end
  build(p)
end
local function jump_to_alarm(p)
  local s=storage.guard or {}
  local alarm=s.alarm or s.last_alarm
  local place=alarm and alarm.place
  local surface=place and game.surfaces[place.surface]
  if not surface or not surface.valid then p.print(tr("jump-unavailable"));return end
  -- Close only the window, retaining the draft. Remote view leaves the character in place.
  destroy(p)
  local ok=pcall(function()
    p.set_controller{type=defines.controllers.remote,surface=surface,position={x=place.x,y=place.y}}
    p.zoom=0.75
  end)
  if not ok then G.open(p);p.print(tr("jump-failed")) end
end
local function owned(e) return e and e.valid and e.get_mod()=="factory-night-watch" end
local function feedback(p,key,...)
  ui(p).feedback=tr(key,...);local f=window(p);if f then find(f,"fnw_feedback").caption=ui(p).feedback end
end
local function numeric(raw) return tonumber((tostring(raw):gsub(",","."))) end
local function apply(p)
  local d=ui(p);local values={}
  if settings_changed(d) then feedback(p,"settings-conflict");return end
  -- Runtime settings are flat booleans, numbers and strings.
  for key,value in pairs(d.values) do values[key]=value end
  local minutes=numeric(values["research-idle-minutes"])
  local t=numeric(d.time)
  if not minutes or minutes~=minutes or minutes<0.1 or minutes>1440 or (d.limit and (not t or t~=t or t<=0 or t*(d.unit==2 and 24 or 1)>8760)) then feedback(p,"invalid-number");return end
  values["research-idle-minutes"]=minutes
  values["max-offline-hours"]=d.limit and t*(d.unit==2 and 24 or 1) or 0
  local count=0
  for name in tostring(values.forces):gmatch("[^,]+") do
    name=name:match("^%s*(.-)%s*$")
    if not game.forces[name] then feedback(p,"unknown-force",name);return end
    count=count+1
  end
  if count==0 then feedback(p,"empty-force");return end
  local excluded,exclusion_error=E.compile(d.excluded_entities,(storage.guard or {}).excluded_entities)
  if not excluded then feedback(p,exclusion_error);return end
  local areas=A.copy(d.areas)
  if not A.validate(areas) then feedback(p,"invalid-area");return end
  local rules=C.copy(d.circuits)
  for i,r in ipairs(rules) do
    r.threshold=numeric(r.threshold);r.delay=numeric(r.delay)
    local err=C.validate(r,callbacks.eligible)
    if err then feedback(p,"rule-error",i,tr(err));return end
  end
  local s=storage.guard
  if d.revision~=(s.circuit_revision or 0) then feedback(p,"conflict");return end
  -- All fields and rules have been validated before modifying server state.
  for _,k in ipairs(keys) do if values[k]~=opt(k) then settings.global["fnw-"..k]={value=values[k]} end end
  s.excluded_entities=excluded
  s.excluded_areas=areas
  s.circuits=rules;s.circuit_revision=(s.circuit_revision or 0)+1
  load(p);d.feedback=tr("saved");build(p)
  -- A safety pause stops periodic refreshes, so publish the new revision to
  -- other open clean forms immediately after the complete apply transaction.
  G.refresh_all()
end
local function request_close(p)
  if ui(p).dirty then ui(p).confirm="close";G.refresh(p) else destroy(p) end
end
local function changed(event)
  if not owned(event.element) then return end
  local p=game.get_player(event.player_index)
  if not p or not p.admin or not window(p) then return end
  local d=ui(p);local e=event.element;local name=e.name
  local key=name:match("^fnw_v_(.+)$")
  if key then if e.type=="checkbox" then d.values[key]=e.state else d.values[key]=e.text end
  elseif name=="fnw_mode" then d.values.enabled=e.selected_index==1
  elseif name=="fnw_limit" then d.limit=e.state
  elseif name=="fnw_time" then d.time=e.text
  elseif name=="fnw_unit" then
    local t=numeric(d.time)
    if t then d.time=tostring(t*(d.unit==2 and 24 or 1)/(e.selected_index==2 and 24 or 1));find(window(p),"fnw_time").text=d.time end
    d.unit=e.selected_index
  elseif name:match("^fnw_e_entity_(%d+)$") then
    local index=tonumber(name:match("(%d+)$"))
    if not d.excluded_entities[index] then return end
    if e.elem_value and not prototypes.entity[e.elem_value] then feedback(p,"invalid-building");return end
    d.excluded_entities[index]=e.elem_value or ""
  elseif name:match("^fnw_a_") then
    local field,index=name:match("^fnw_a_([a-z]+)_(%d+)$");index=tonumber(index)
    local area=index and d.areas[index]
    if not area then return end
    if field=="name" then area.name=e.text
    elseif field=="enabled" then area.enabled=e.state
    else return end
  else
    local field,index=name:match("^fnw_c_([a-z]+)_(%d+)$");index=tonumber(index)
    if not field or not d.circuits[index] then return end
    local r=d.circuits[index]
    if field=="enabled" then r.enabled=e.state
    elseif field=="connection" then
      local option=(r.choices or {})[e.selected_index-1]
      if option and not C.network(option,callbacks.eligible) then feedback(p,"network-lost");G.refresh(p);return end
      choose(r,option)
    elseif field=="signal" then r.signal=e.elem_value
    elseif field=="op" then r.op=C.operators[e.selected_index]
    else r[field]=e.text end
  end
  d.dirty=true;d.feedback=nil;G.refresh(p)
end
for _,event in ipairs({defines.events.on_gui_text_changed,defines.events.on_gui_checked_state_changed,defines.events.on_gui_selection_state_changed,defines.events.on_gui_elem_changed}) do script.on_event(event,changed) end
script.on_event(defines.events.on_lua_shortcut,function(e)
  if e.prototype_name~="fnw-open" then return end
  local p=game.get_player(e.player_index)
  if window(p) then request_close(p) else G.open(p) end
end)
script.on_event(defines.events.on_gui_click,function(event)
  if not owned(event.element) then return end
  local p=game.get_player(event.player_index);if not p then return end
  local d=ui(p);local name=event.element.name
  if name=="fnw_preview_return" or name=="fnw_preview_save" then
    if not d.preview then return end
    local save=name=="fnw_preview_save"
    if save and not p.admin then return end
    d.tab=3;G.open(p)
    if save then apply(p) end
    return
  end
  if not window(p) then return end
  if name=="fnw_jump" then jump_to_alarm(p);return
  elseif name=="fnw_close" then request_close(p);return
  elseif name=="fnw_cancel" then d.confirm=nil;build(p);return
  elseif name=="fnw_reload" then load(p);build(p);return
  elseif name=="fnw_compatibility" then d.compatibility=not d.compatibility;build(p);return
  elseif name=="fnw_confirm" then
    local action=d.confirm;d.confirm=nil
    if action=="close" then load(p);destroy(p);return end
    if action=="test" and p.admin then callbacks.test() end
    build(p);return
  end
  local area_index=tonumber(name:match("^fnw_area_view_(%d+)$"))
  if area_index then
    local a=d.areas[area_index]
    if not a or not a.surface or not a.surface.valid then feedback(p,"jump-unavailable");return end
    stop_preview(p);destroy(p)
    local ok=pcall(function()
      p.set_controller{type=defines.controllers.remote,surface=a.surface,position={x=(a.left+a.right)/2,y=(a.top+a.bottom)/2}}
      p.zoom=math.max(0.03125,math.min(0.75,32/math.max(a.right-a.left,a.bottom-a.top)))
      d.preview={objects=A.draw(a,p)}
      preview_panel(p)
    end)
    if not ok then G.open(p);p.print(tr("jump-failed")) end
    return
  end
  if not p.admin then return end
  if name=="fnw_e_add" then
    if #d.excluded_entities>=E.limit then feedback(p,"building-limit");return end
    d.excluded_entities[#d.excluded_entities+1]="";d.dirty=true;d.feedback=nil;build(p)
  elseif name:match("^fnw_e_remove_(%d+)$") then
    local index=tonumber(name:match("(%d+)$"))
    if not d.excluded_entities[index] then return end
    table.remove(d.excluded_entities,index);d.dirty=true;d.feedback=nil;build(p)
  elseif name=="fnw_area_add" then
    if #d.areas>=A.limit then feedback(p,"area-limit");return end
    if not p.clear_cursor() then feedback(p,"cursor-busy");return end
    d.selecting=nil;d.selecting_area=true;destroy(p)
    p.cursor_stack.set_stack{name="fnw-select-area",count=1}
    p.print(tr("area-select-help"))
  elseif name:match("^fnw_area_remove_(%d+)$") then
    table.remove(d.areas,tonumber(name:match("(%d+)$")));d.dirty=true;d.feedback=nil;build(p)
  elseif name=="fnw_apply" then apply(p)
  elseif name=="fnw_resume" then callbacks.resume();G.refresh_all()
  elseif name=="fnw_test" then d.confirm="test";build(p)
  elseif name=="fnw_add" then
    if #d.circuits>=32 then feedback(p,"rule-limit");return end
    d.circuits[#d.circuits+1]={name="",wire=1,op=">",threshold=0,delay=30,enabled=true};d.dirty=true;build(p)
  else
    local index=tonumber(name:match("^fnw_remove_(%d+)$"))
    if index then table.remove(d.circuits,index);d.dirty=true;build(p);return end
    index=tonumber(name:match("^fnw_select_(%d+)$"))
    if index then
      if not p.clear_cursor() then feedback(p,"cursor-busy");return end
      d.selecting_area=nil;d.selecting=index;destroy(p);p.cursor_stack.set_stack{name="fnw-select-network",count=1}
      p.print(tr("select-help"))
    end
  end
end)
script.on_event(defines.events.on_gui_closed,function(e)
  if internal_close[e.player_index] then return end
  if owned(e.element) and e.element.name==ROOT then request_close(game.get_player(e.player_index)) end
end)
script.on_event(defines.events.on_player_removed,function(e)
  G.remove_player(e.player_index)
end)
local function selected(e)
  if e.item=="fnw-select-area" then
    local p=game.get_player(e.player_index)
    if not p or not p.valid then return end
    local d=ui(p)
    if not p.admin or not d.selecting_area then return end
    local a=A.create(e.surface,e.area)
    if not a then p.print(tr("invalid-area"));return end
    if #d.areas>=A.limit then p.print(tr("area-limit"));return end
    d.areas[#d.areas+1]=a;d.dirty=true;d.feedback=nil;d.selecting_area=nil
    p.clear_cursor();build(p);return
  end
  if e.item~="fnw-select-network" then return end
  local p=game.get_player(e.player_index);local d=ui(p)
  if not p.admin or not d.selecting or not d.circuits[d.selecting] then return end
  local options,err=C.candidates(e.entities,callbacks.eligible)
  if not options then p.print(tr(err));return end
  if #options==0 then p.print(tr("no-cable"));return end
  local r=d.circuits[d.selecting]
  r.choices=options
  choose(r,#options==1 and options[1] or nil)
  d.dirty=true;d.selecting=nil
  d.feedback=#options>1 and tr("multiple-networks",#options) or nil
  p.clear_cursor();build(p)
end
script.on_event(defines.events.on_player_selected_area,selected)
script.on_event(defines.events.on_player_alt_selected_area,selected)
script.on_event(defines.events.on_player_cursor_stack_changed,function(e)
  local p=game.get_player(e.player_index);local d=(storage.fnw_ui or {})[p.index]
  local expected=d and (d.selecting_area and "fnw-select-area" or d.selecting and "fnw-select-network")
  if expected and (not p.cursor_stack or not p.cursor_stack.valid_for_read or p.cursor_stack.name~=expected) then
    d.selecting=nil;d.selecting_area=nil;G.open(p)
  end
end)
return G
