local root=assert(os.getenv("FNW_MOD_ROOT"),"FNW_MOD_ROOT required").."/"
package.path=root.."?.lua;"..package.path
local checks=0
local function check(value,label) assert(value,label);checks=checks+1;print("PASS: "..label) end
local handlers,registered={},{}
defines={events={}}
for _,name in ipairs({"on_tick","on_player_joined_game","on_player_left_game","on_runtime_mod_setting_changed",
  "on_entity_damaged","on_entity_died", "on_gui_text_changed", "on_gui_checked_state_changed", "on_gui_selection_state_changed", "on_gui_elem_changed", "on_lua_shortcut", "on_player_selected_area", "on_player_alt_selected_area", "on_player_cursor_stack_changed","on_gui_click","on_gui_closed","on_player_created","on_player_promoted","on_player_demoted"}) do defines.events[name]=name end
script={on_init=function(f) handlers.init=f end,on_load=function(f) handlers.load=f end,
  on_configuration_changed=function(f) handlers.configuration=f end,
  on_event=function(e,f) handlers[e]=f end,on_nth_tick=function(_,f) handlers.periodic=f end}
commands={add_command=function(name,_,f) registered[name]=f end}
remote={add_interface=function() end}
storage={};log=function() end
local backing={}
settings={global=setmetatable({},{__index=backing,__newindex=function(_,key,value)
  backing[key]=value
  if handlers.on_runtime_mod_setting_changed then handlers.on_runtime_mod_setting_changed({setting=key}) end
end})}
data={extend=function(_,defs) for _,d in ipairs(defs) do backing[d.name]={value=d.default_value} end end}
dofile(root.."settings.lua")

local function element(spec,parent)
  local e={valid=true,children={},style={},tags={},name=spec.name or "",type=spec.type,parent=parent,enabled=spec.enabled~=false}
  for k,v in pairs(spec) do if k~="style" then e[k]=v end end
  local named={}
  setmetatable(e,{__index=function(_,key) return named[key] end})
  e.add=function(childspec)
    assert(childspec.type~="scroll-pane" or not childspec.direction,"scroll-pane direction unsupported")
    assert(not childspec.name or not named[childspec.name],"Gui element with name "..tostring(childspec.name).." already present in the parent element.")
    local child=element(childspec,e);e.children[#e.children+1]=child
    if child.name~="" then named[child.name]=child end
    return child
  end
  e.add_tab=function() end
  e.get_mod=function() return "factory-night-watch" end
  e.force_auto_center=function() e.centered=true end
  e.destroy=function()
    if not e.valid then return end
    e.valid=false
    for _,child in pairs(e.children) do child.valid=false end
    if parent then
      for i,child in ipairs(parent.children) do if child==e then table.remove(parent.children,i);break end end
      -- Parent child lookup must no longer expose destroyed elements.
      parent.remove_name(e.name)
    end
  end
  e.remove_name=function(name) named[name]=nil end
  return e
end
assert(table.deepcopy==nil,"runtime tests must not inject table.deepcopy")
helpers={table_to_json=function() return "message" end}
prototypes={item={["iron-plate"]={}},fluid={},virtual_signal={},quality={normal={}}}
defines.wire_connector_id={circuit_red=1,circuit_green=2}
defines.controllers={remote=9}
local player={valid=true,index=1,admin=false,print=function() end,
  set_shortcut_available=function() end,clear_cursor=function() return true end,cursor_stack={set_stack=function() end},
  gui={top=element{type="flow"},screen=element{type="flow"}}}
-- Native-style opened assignments synchronously close the previous GUI. The old
-- element still exists during on_gui_closed; named siblings must stay unique.
local opened_gui=nil
local close_events=0
setmetatable(player,{
  __index=function(_,key) if key=="opened" then return opened_gui end end,
  __newindex=function(t,key,value)
    if key~="opened" then rawset(t,key,value);return end
    local previous=opened_gui
    opened_gui=value
    if previous and previous~=value and previous.valid and handlers.on_gui_closed then
      close_events=close_events+1
      handlers.on_gui_closed{player_index=1,element=previous}
      -- A native request to close/open another GUI wins over nested opened writes.
      opened_gui=value
    end
  end
})
local saves=0
game={tick=100,tick_paused=false,connected_players={player},players={player},surfaces={},
  forces={player={name="player",valid=true,index=1,research_queue={}}},
  is_multiplayer=function() return true end,print=function() end,get_player=function() return player end,
  server_save=function() saves=saves+1 end}
dofile(root.."control.lua")
handlers.init()
local function find(e,name)
  if e.name==name then return e end
  for _,c in pairs(e.children) do local r=find(c,name);if r then return r end end
end
local function frame() return player.gui.screen.fnw_window end
local function click(name) assert(find(frame(),name),name);handlers.on_gui_click{player_index=1,element=find(frame(),name)} end
local function change(name,value,typ)
  local e=find(frame(),name);assert(e,name)
  local property=typ=="check" and "state" or typ=="select" and "selected_index" or typ=="signal" and "elem_value" or "text"
  e[property]=value
  handlers[typ=="check" and "on_gui_checked_state_changed" or typ=="select" and "on_gui_selection_state_changed" or typ=="signal" and "on_gui_elem_changed" or "on_gui_text_changed"]{player_index=1,element=e}
end
registered['fnw-gui']{player_index=1}
check(frame() and not player.gui.top.fnw_toggle,"native shortcut replaces top-left button")
check(not find(frame(),"fnw_mode").enabled,"non-admin controls disabled")
click('fnw_add');check(#storage.fnw_ui[1].circuits==0,"forged non-admin add rejected")
player.admin=true;handlers.on_player_promoted()
check(not find(frame(),'fnw_apply').enabled,"save disabled with clean draft")
change('fnw_v_ignore-walls',false,'check')
check(storage.fnw_ui[1].values['ignore-walls']==false,"unchecked boxes retain false")
click('fnw_apply');check(not backing['fnw-ignore-walls'].value,"unchecked setting saved")
change('fnw_time','abc');click('fnw_apply');check(find(frame(),'fnw_feedback').caption[1]=='fnw-gui.invalid-number',"invalid time rejected")
click('fnw_reload');change('fnw_time','3');change('fnw_unit',1,'select')
check(find(frame(),'fnw_time').text=='72.0',"switching days to hours converts duration")
click('fnw_apply');check(backing['fnw-max-offline-hours'].value==72,"converted duration saved")
change('fnw_v_research-idle-minutes','2,5');click('fnw_apply');check(backing['fnw-research-idle-minutes'].value==2.5,"decimal comma accepted")
change('fnw_time','5');handlers.periodic();check(find(frame(),'fnw_time').text=='5',"live refresh preserves draft")
click('fnw_close');check(frame() and storage.fnw_ui[1].confirm=='close',"dirty close asks before discarding")
click('fnw_cancel');check(frame() and storage.fnw_ui[1].dirty,"cancel close preserves draft")
click('fnw_reload');click('fnw_add')
change('fnw_c_name_1','Munition');change('fnw_c_signal_1',{type='item',name='iron-plate'},'signal')
local pole={valid=true,type='electric-pole',name='small-electric-pole',position={x=1,y=2},force=game.forces.player,
 surface={valid=true,name='nauvis',planet={}},get_circuit_network=function(id) return {network_id=id==1 and 42 or 43} end,get_signal=function() return 50 end}
click('fnw_select_1');check(not frame() and storage.fnw_ui[1].selecting==1,"selection tool preserves draft while window closed")
handlers.on_player_selected_area{player_index=1,item='fnw-select-network',entities={pole}}
check(frame() and storage.fnw_ui[1].circuits[1].entity==pole,"pole selection returns to draft")
change('fnw_c_op_1',1,'select');change('fnw_c_threshold_1','100');change('fnw_c_delay_1','60');click('fnw_apply')
check(#storage.guard.circuits==1 and storage.guard.circuits[1].threshold==100,"circuit rule saved after validation")
check(find(frame(),'fnw_c_status_1').caption[2]==50,"live circuit value displayed")
click('fnw_test');check(not storage.guard.alarm,"test requires explicit confirmation")
click('fnw_confirm');check(storage.guard.alarm and saves==1,"confirmed test pauses and saves")
player.admin=false;click('fnw_resume');check(storage.guard.alarm~=nil,"non-admin cannot acknowledge")
player.admin=true;click('fnw_resume');check(not storage.guard.alarm,"admin acknowledges pause")
change('fnw_mode',2,'select');click('fnw_apply');check(not backing['fnw-enabled'].value and not game.tick_paused,"pause-when-empty mode does not stop online players")
game.connected_players={};handlers.on_player_left_game();check(game.tick_paused,"pause-when-empty stops immediately")
game.connected_players={player};handlers.on_player_joined_game{player_index=1};check(not game.tick_paused,"normal empty-server pause resumes on join")
click('fnw_test');click('fnw_confirm');handlers.on_player_joined_game{player_index=1};check(game.tick_paused,"join does not release safety latch")
click('fnw_resume');click('fnw_remove_1');click('fnw_apply');check(#storage.guard.circuits==0,"circuit removal saved")
click('fnw_close');check(not frame(),"clean close works")
registered['fnw-gui']{player_index=1}
click('fnw_add');change('fnw_c_name_1','Munitionsvorrat');change('fnw_c_signal_1',{type='item',name='iron-plate'},'signal')
click('fnw_select_1');player.cursor_stack.valid_for_read=false
handlers.on_player_cursor_stack_changed{player_index=1}
check(frame() and storage.fnw_ui[1].circuits[1].name=='Munitionsvorrat',"cancelling selection restores draft")
click('fnw_select_1');handlers.on_player_selected_area{player_index=1,item='fnw-select-network',entities={pole}}
click('fnw_apply');check(#storage.guard.circuits==1,"second circuit created")
change('fnw_c_threshold_1','-5');storage.guard.circuit_revision=storage.guard.circuit_revision+1;click('fnw_apply')
check(find(frame(),'fnw_feedback').caption[1]=='fnw-gui.conflict',"stale circuit draft cannot overwrite another admin")
click('fnw_reload');pole.valid=false;change('fnw_c_enabled_1',false,'check');click('fnw_apply')
check(not storage.guard.circuits[1].enabled,"lost source can be disabled and saved")
pole.valid=true
change('fnw_c_enabled_1',true,'check');change('fnw_c_threshold_1','-5');change('fnw_c_delay_1','2');change('fnw_mode',1,'select');click('fnw_apply')
for i=1,5 do game.tick=game.tick+60;handlers.periodic() end
check(not game.tick_paused and not storage.guard.circuits[1].since,"online matching signal does not pause or collect delay")
game.connected_players={};handlers.on_player_left_game();game.tick=game.tick+60;handlers.periodic()
check(storage.guard.circuits[1].since~=nil and not game.tick_paused,"offline signal starts fresh delay")
game.connected_players={player};handlers.on_player_joined_game{player_index=1}
check(storage.guard.circuits[1].since==nil,"player join resets circuit wait")
click('fnw_reload');find(frame(),'fnw_tabs').selected_tab_index=3;click('fnw_close');registered['fnw-gui']{player_index=1}
check(find(frame(),'fnw_tabs').selected_tab_index==3,'selected tab survives close/reopen')
click('fnw_test');click('fnw_confirm')
check(not find(frame(),'fnw_jump').visible,'location button hidden for alarms without coordinates')
local destination={valid=true,name='vulcanus'};game.surfaces.vulcanus=destination
storage.guard.alarm.place={surface='vulcanus',x=827.5,y=-463.5,entity='foundry'}
handlers.on_player_promoted()
check(find(frame(),'fnw_jump').visible and find(frame(),'fnw_jump').enabled,'stored alarm location enables view button')
local controller
player.set_controller=function(spec) controller=spec end
player.admin=false
click('fnw_jump')
check(controller and controller.type==defines.controllers.remote and controller.surface==destination and controller.position.x==827.5,'read-only player can open exact remote alarm location')
check(game.tick_paused and storage.guard.alarm~=nil,'viewing alarm does not acknowledge or unpause')
registered['fnw-gui']{player_index=1};player.admin=true
change('fnw_time','9');click('fnw_jump');registered['fnw-gui']{player_index=1}
check(find(frame(),'fnw_time').text=='9' and storage.fnw_ui[1].dirty,'jump preserves unsaved draft when reopened')
destination.valid=false;handlers.on_player_promoted()
check(not find(frame(),'fnw_jump').enabled,'deleted surface disables location jump')
click('fnw_jump');check(frame()~=nil and game.tick_paused,'unavailable location safely leaves GUI and pause intact')
destination.valid=true;player.set_controller=function() error('remote view unavailable') end
click('fnw_jump')
check(frame()~=nil and storage.fnw_ui[1].dirty and game.tick_paused,'remote view failure restores draft and keeps safety pause')
find(frame(),'fnw_jump').destroy();handlers.configuration()
check(not frame(),'GUI from earlier tabbed version is rebuilt safely on upgrade')
registered['fnw-gui']{player_index=1}
local baseline=#storage.fnw_ui[1].circuits
local function window_count()
  local n=0;for _,e in ipairs(player.gui.screen.children) do if e.valid and e.name=='fnw_window' then n=n+1 end end;return n
end
local before_events=close_events
click('fnw_add')
check(#storage.fnw_ui[1].circuits==baseline+1 and window_count()==1,'add circuit survives synchronous native close event with unique root')
check(close_events>before_events and storage.fnw_ui[1].confirm==nil,'internal teardown does not invoke user close confirmation')
for i=1,5 do click('fnw_add');click('fnw_remove_'..#storage.fnw_ui[1].circuits) end
check(window_count()==1 and #storage.fnw_ui[1].circuits==baseline+1,'repeated add/remove rebuilds leave exactly one window')
local previous=frame();local expected_text=find(frame(),'fnw_time').text
player.opened=nil
check(frame()==previous and storage.fnw_ui[1].confirm=='close' and find(frame(),'fnw_confirm_panel').visible,'native Escape shows confirmation in existing frame without rebuilding')
check(player.opened==nil and find(frame(),'fnw_time').text==expected_text,'native close handler does not reopen a GUI or discard draft')
click('fnw_cancel')
check(player.opened==frame() and storage.fnw_ui[1].dirty,'cancelling native-close confirmation restores normal opened GUI')
player.opened=nil;click('fnw_confirm')
check(not frame() and window_count()==0,'confirming discard after native close destroys root safely')
registered['fnw-gui']{player_index=1};local clean_frame=frame();player.opened=nil
check(not frame() and not clean_frame.valid,'clean native close destroys window without replacement')
registered['fnw-gui']{player_index=1};change('fnw_time','8')
local foreign=player.gui.screen.add{type='frame',name='foreign_gui'}
player.opened=foreign
check(player.opened==foreign and storage.fnw_ui[1].confirm=='close','opening another GUI keeps its focus and preserves dirty draft')
click('fnw_confirm')
check(not frame() and foreign.valid and player.opened==foreign,'discarding Night Watch draft leaves the other GUI intact')
local Circuits=require('circuits')
local original={name='Copy test',entity=pole,wire=2,signal={type='item',name='iron-plate',quality='legendary'},op='≤',threshold=-10,delay=0,enabled=false}
local copied=Circuits.copy({original})
check(copied[1]~=original and copied[1].signal~=original.signal,'rule and signal tables are independent without runtime table extensions')
check(copied[1].entity==pole and copied[1].signal.quality=='legendary','copy retains entity reference and exact signal quality')
copied[1].signal.name='copper-plate'
check(original.signal.name=='iron-plate','editing a copied signal cannot mutate the active signal')
check(copied[1].enabled==false and copied[1].delay==0 and copied[1].threshold==-10,'copy preserves false, zero and negative values')
check(#Circuits.copy(nil)==0,'absent circuit list copies safely')
registered['fnw-gui']{player_index=1}
change('fnw_v_research-idle-minutes','4,25');click('fnw_apply')
check(backing['fnw-research-idle-minutes'].value==4.25 and not storage.fnw_ui[1].dirty,'settings save succeeds without table.deepcopy')
change('fnw_c_name_1','Saved circuit regression');click('fnw_apply')
check(storage.guard.circuits[1].name=='Saved circuit regression' and find(frame(),'fnw_feedback').caption[1]=='fnw-gui.saved','circuit save and reload succeed without table.deepcopy')
change('fnw_c_name_1','Uncommitted circuit draft')
check(storage.guard.circuits[1].name=='Saved circuit regression','unsaved circuit edits do not mutate installed rules')
local source_caption=find(frame(),'fnw_c_network_1').caption
check(source_caption[1]=='fnw-gui.network-label' and source_caption[2]==42,'source display uses actual red circuit network ID instead of coordinates')
change('fnw_c_wire_1',2,'select')
check(find(frame(),'fnw_c_network_1').caption[2]==43,'switching wire colour immediately shows the other network ID')
pole.get_circuit_network=function() return {network_id=99} end;handlers.on_player_promoted()
check(find(frame(),'fnw_c_network_1').caption[2]==99,'network ID display follows current topology instead of a cached ID')
pole.get_circuit_network=function(id) if id==2 then return {network_id=101} end end
click('fnw_select_1');handlers.on_player_selected_area{player_index=1,item='fnw-select-network',entities={pole}}
check(storage.fnw_ui[1].circuits[1].wire==2 and find(frame(),'fnw_c_network_1').caption[2]==101,'network selection chooses the connected wire when the other colour is absent')
frame().tags={};handlers.configuration()
check(not frame(),'older GUI layouts rebuild before refreshing newly added network labels')
local snapshot=Circuits.copy({original})[1]
check(snapshot.place and snapshot.place.x==1 and snapshot.place.y==2 and snapshot.place.surface=='nauvis','circuit copy persists coordinates separately from the entity reference')
local saved_place=snapshot.place
pole.valid=false;local alarm_place
snapshot.enabled=true
Circuits.poll({snapshot},true,nil,function(_,place) alarm_place=place end)
check(alarm_place and alarm_place.x==1 and alarm_place.y==2,'lost-source alarm retains saved coordinates for map jump')
local snapshot2=Circuits.copy({snapshot})[1]
check(snapshot2.place~=saved_place and snapshot2.place.x==1,'invalid source location survives copying without shared mutable tables')
pole.valid=true
print('ALL '..checks..' GUI CHECKS PASSED')
