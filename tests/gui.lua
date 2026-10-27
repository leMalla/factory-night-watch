local root=assert(os.getenv("FNW_MOD_ROOT"),"FNW_MOD_ROOT required").."/"
package.path=root.."?.lua;"..package.path
local checks=0
local function check(value,label) assert(value,label);checks=checks+1;print("PASS: "..label) end
local handlers,registered={},{}
defines={events={}}
for _,name in ipairs({"on_tick","on_player_joined_game","on_player_left_game","on_runtime_mod_setting_changed",
  "on_entity_damaged","on_entity_died", "on_gui_text_changed", "on_gui_checked_state_changed", "on_gui_selection_state_changed", "on_gui_elem_changed", "on_lua_shortcut", "on_player_selected_area", "on_player_alt_selected_area", "on_player_cursor_stack_changed","on_player_removed","on_gui_click","on_gui_closed","on_player_created","on_player_promoted","on_player_demoted"}) do defines.events[name]=name end
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
defines.wire_connector_id={circuit_red=1,circuit_green=2,combinator_input_red=1,combinator_input_green=2,combinator_output_red=3,combinator_output_green=4,pole_copper=16}
defines.wire_type={red=1,green=2,copper=3}
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
pole.get_wire_connectors=function()
  local out={}
  for i=1,2 do if pole.get_circuit_network(i) then out[i]={valid=true,wire_type=i} end end
  return out
end
click('fnw_select_1');check(not frame() and storage.fnw_ui[1].selecting==1,"selection tool preserves draft while window closed")
handlers.on_player_selected_area{player_index=1,item='fnw-select-network',entities={pole}}
check(storage.fnw_ui[1].circuits[1].entity==nil,'two networks require an explicit choice without selecting a default')
change('fnw_c_connection_1',2,'select')
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
change('fnw_c_connection_1',2,'select')
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
check(find(frame(),'fnw_changes').caption[1]=='fnw-gui.clean','successful save shows clean state alongside its confirmation')
click('fnw_add')
check(find(frame(),'fnw_feedback').caption=='' and find(frame(),'fnw_changes').caption[1]=='fnw-gui.unsaved','adding a circuit clears previous save confirmation immediately')
click('fnw_reload')
check(find(frame(),'fnw_feedback').caption=='' and not storage.fnw_ui[1].dirty,'discard clears stale feedback and restores clean state')
change('fnw_c_name_1','Saved circuit regression');click('fnw_apply')
click('fnw_remove_1')
check(find(frame(),'fnw_feedback').caption=='' and storage.fnw_ui[1].dirty,'removing a circuit cannot display a stale save confirmation')
click('fnw_reload')
change('fnw_c_name_1','Uncommitted circuit draft')
check(storage.guard.circuits[1].name=='Saved circuit regression','unsaved circuit edits do not mutate installed rules')
local source_caption=find(frame(),'fnw_c_network_1').caption
check(source_caption[1]=='fnw-gui.network-label' and source_caption[2]==42,'source display uses actual red circuit network ID instead of coordinates')
change('fnw_c_connection_1',3,'select')
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
-- Server changes must refresh clean forms without overwriting dirty drafts.
storage.guard.circuits={}
storage.guard.circuit_revision=(storage.guard.circuit_revision or 0)+1
registered['fnw-gui']{player_index=1}
registered['fnw-set']{parameter='research-idle-minutes 6'}
check(find(frame(),'fnw_v_research-idle-minutes').text=='6','clean form refreshes when server settings change through a command')
local changed_walls=not backing['fnw-ignore-walls'].value
change('fnw_v_ignore-walls',changed_walls,'check');click('fnw_apply')
check(backing['fnw-research-idle-minutes'].value==6 and backing['fnw-ignore-walls'].value==changed_walls,'unrelated GUI save preserves the current server setting')
change('fnw_time','11')
registered['fnw-set']{parameter='research-idle-minutes 7'}
check(find(frame(),'fnw_time').text=='11' and storage.fnw_ui[1].dirty,'external settings changes preserve dirty draft inputs')
click('fnw_apply')
check(find(frame(),'fnw_feedback').caption[1]=='fnw-gui.settings-conflict' and backing['fnw-research-idle-minutes'].value==7,'dirty stale settings draft is rejected without overwriting new server values')
click('fnw_reload')
check(find(frame(),'fnw_v_research-idle-minutes').text=='7' and not storage.fnw_ui[1].dirty,'discard loads current settings after a settings conflict')
local version_before=storage.fnw_ui[1].revision
storage.guard.circuit_revision=storage.guard.circuit_revision+1
handlers.on_player_promoted()
check(storage.fnw_ui[1].revision==version_before+1 and not storage.fnw_ui[1].dirty,'clean form refreshes after another admin changes circuit revision')
-- Removing a player must clear drafts before the engine can reuse their index.
change('fnw_time','13')
handlers.on_player_removed{player_index=1}
check(storage.fnw_ui[1]==nil,'removed player draft is deleted')
player.opened=nil
player.gui={top=element{type='flow'},screen=element{type='flow'}}
registered['fnw-gui']{player_index=1}
check(not storage.fnw_ui[1].dirty and find(frame(),'fnw_time').text~='13','reused player index starts with current server values instead of the previous draft')
-- An independently existing manual pause is not owned by empty-server mode.
click('fnw_reload');change('fnw_mode',2,'select');click('fnw_apply')
game.tick_paused=true;storage.guard.alarm=nil;storage.guard.empty_pause=nil
game.connected_players={};handlers.on_player_left_game()
check(game.tick_paused and not storage.guard.empty_pause,'empty-server mode does not claim an existing manual pause')
game.connected_players={player};handlers.on_player_joined_game{player_index=1}
check(game.tick_paused,'player joining does not release an independently existing manual pause')
-- Paused worlds have no periodic tick: applying must refresh another viewer now.
local other={valid=true,index=2,admin=true,print=function() end,
  set_shortcut_available=function() end,
  gui={top=element{type='flow'},screen=element{type='flow'}}}
local previous_get_player=game.get_player
game.get_player=function(index) if index==2 then return other else return player end end
game.players={player,other};game.connected_players={player,other}
require('gui').open(other)
click('fnw_add');local added=#storage.fnw_ui[1].circuits
change('fnw_c_name_'..added,'Second viewer')
change('fnw_c_signal_'..added,{type='item',name='iron-plate'},'signal')
change('fnw_c_enabled_'..added,false,'check');click('fnw_apply')
local other_frame=other.gui.screen.fnw_window
check(game.tick_paused and storage.fnw_ui[2].revision==storage.guard.circuit_revision and find(other_frame,'fnw_c_name_'..added).text=='Second viewer','successful circuit apply refreshes another clean GUI immediately while paused')
local other_name=find(other_frame,'fnw_c_name_'..added);other_name.text='Other admin draft'
handlers.on_gui_text_changed{player_index=2,element=other_name}
change('fnw_v_ignore-walls',not backing['fnw-ignore-walls'].value,'check');click('fnw_apply')
check(storage.fnw_ui[2].dirty and find(other.gui.screen.fnw_window,'fnw_c_name_'..added).text=='Other admin draft','apply refresh preserves another admins dirty GUI while paused')
game.get_player=previous_get_player;game.players={player};game.connected_players={player}
local function device(kind,networks)
  local e={valid=true,type=kind,name=kind,position={x=25,y=26},force=game.forces.player,surface={valid=true,name='nauvis',planet={}}}
  e.get_circuit_network=function(id) local n=networks[id];return n and {network_id=n.id} end
  e.get_wire_connectors=function()
    local out={};for id,n in pairs(networks) do out[id]={valid=true,wire_type=n.wire or (id%2==1 and defines.wire_type.red or defines.wire_type.green)} end;return out
  end
  e.get_signal=function(_,id) assert(networks[id],'wrong connector');return networks[id].value or 50 end
  return e
end
local chest=device('container',{[1]={id=501}})
local inserter=device('inserter',{[1]={id=501}})
local comb_networks={[1]={id=501,value=50},[2]={id=502,value=60},[3]={id=503,value=200},[4]={id=504,value=300}}
local comb=device('arithmetic-combinator',comb_networks)
check(#Circuits.candidates({chest},nil)==1,'container with one circuit network is selectable')
check(#Circuits.candidates({chest,inserter},nil)==1,'area selection deduplicates the same network across box and inserter')
local four=Circuits.candidates({chest,inserter,comb},nil)
check(#four==4,'combinator input/output red/green remain four explicit network choices')
check(Circuits.port(four[3])=='port-output' and Circuits.port(four[1])~='port-output','connector labels distinguish combinator outputs')
local power=device('electric-pole',{[16]={id=777,wire=defines.wire_type.copper}})
check(#Circuits.candidates({power},nil)==0,'copper power network is never offered as a circuit network')
local empty=device('container',{})
check(#Circuits.candidates({empty},nil)==0,'unwired objects produce no circuit choices')
local forbidden=Circuits.candidates({chest},function() return false end)
check(#forbidden==0,'unmonitored entities are excluded from network selection')
local huge={};for i=1,1025 do huge[i]=chest end
local too_many,selection_error=Circuits.candidates(huge,nil)
check(too_many==nil and selection_error=='selection-too-large','large selections are bounded with a clear error')
click('fnw_add');local index=#storage.fnw_ui[1].circuits
change('fnw_c_name_'..index,'Combinator output')
change('fnw_c_signal_'..index,{type='item',name='iron-plate'},'signal')
click('fnw_select_'..index)
handlers.on_player_selected_area{player_index=1,item='fnw-select-network',entities={chest,inserter,comb}}
check(frame() and storage.fnw_ui[1].circuits[index].entity==nil,'ambiguous range does not silently select any endpoint')
local before_count=#storage.guard.circuits;click('fnw_apply')
check(#storage.guard.circuits==before_count and storage.fnw_ui[1].dirty,'unresolved network choice cannot be saved as an active rule')
local option_index
for i,r in ipairs(storage.fnw_ui[1].circuits[index].choices) do if r.entity==comb and r.connector==3 then option_index=i+1 end end
change('fnw_c_connection_'..index,option_index,'select');click('fnw_apply')
check(storage.guard.circuits[index].connector==3 and storage.guard.circuits[index].entity==comb,'explicit output choice stores the exact entity and connector')
click('fnw_close');registered['fnw-gui']{player_index=1}
check(storage.fnw_ui[1].circuits[index].connector==3,'saved output connector survives GUI close/reopen and copying')
comb_networks[3]=nil
local missing,problem=Circuits.read(storage.guard.circuits[index])
check(missing==nil and problem=='network-lost','lost output never silently switches to a still-connected input')
local legacy={entity=chest,wire=1,signal={type='item',name='iron-plate'}}
check(Circuits.read(legacy)==50 and Circuits.copy({legacy})[1].connector==1,'legacy pole-style red/green rules migrate to their original connector')
local feedback_loop=device('decider-combinator',{[1]={id=900},[3]={id=900}})
check(#Circuits.candidates({feedback_loop},nil)==1,'feedback loop shared input/output is one physical network')
local retained=Circuits.candidates({feedback_loop},nil,{entity=feedback_loop,connector=3,wire=1})
check(#retained==1 and retained[1].connector==3,'deduplication retains an already selected output endpoint')
local r=storage.fnw_ui[1].circuits[index]
local input_choice,output_choice
for i,option in ipairs(r.choices) do if option.connector==1 then input_choice=i+1 elseif option.connector==3 then output_choice=i+1 end end
change('fnw_c_connection_'..index,input_choice,'select')
change('fnw_c_connection_'..index,output_choice,'select')
check(r.connector==1 and find(frame(),'fnw_c_connection_'..index).selected_index==input_choice,'choosing a disconnected option restores the previous explicit selection instead of displaying a different binding')
-- Area GUI transactions, boundary rules and alarm integration.
local Areas=require('areas')
storage.guard.circuits={};storage.guard.circuit_revision=(storage.guard.circuit_revision or 0)+1
click('fnw_reload')
player.admin=false;handlers.on_player_demoted()
click('fnw_area_add')
check(frame() and not storage.fnw_ui[1].selecting_area,'non-admin cannot start area selection')
player.admin=true;handlers.on_player_promoted()
local before_areas=#(storage.guard.excluded_areas or {})
click('fnw_area_add')
check(not frame() and storage.fnw_ui[1].selecting_area,'area tool closes window and preserves draft')
player.cursor_stack.valid_for_read=false
handlers.on_player_cursor_stack_changed{player_index=1}
check(frame() and not storage.fnw_ui[1].selecting_area and not storage.fnw_ui[1].dirty,'cancelled area selection restores clean draft')
local surface={valid=true,name='nauvis',index=1,planet={}}
local function select_area(box,alternate)
  handlers[alternate and 'on_player_alt_selected_area' or 'on_player_selected_area']{player_index=1,item='fnw-select-area',surface=surface,area=box,entities={}}
end
click('fnw_area_add')
select_area({left_top={x=1,y=1},right_bottom={x=1,y=5}})
check(not frame() and storage.fnw_ui[1].selecting_area,'zero-width area rejected without abandoning tool')
select_area({left_top={x=10,y=10},right_bottom={x=-10,y=-10}},true)
check(frame() and #storage.fnw_ui[1].areas==1 and storage.fnw_ui[1].areas[1].left==-10,'empty reversed selection normalizes bounds and returns to GUI')
check(#(storage.guard.excluded_areas or {})==before_areas,'unsaved area does not change alarm protection')
change('fnw_a_name_1','Test perimeter')
click('fnw_apply')
check(storage.guard.excluded_areas[1].name=='Test perimeter' and not storage.fnw_ui[1].dirty,'named area saves through normal apply transaction')
change('fnw_a_name_1','Unsaved rename')
check(storage.guard.excluded_areas[1].name=='Test perimeter','area draft copy does not mutate saved exclusion')
click('fnw_reload')
check(find(frame(),'fnw_a_name_1').text=='Test perimeter','discard restores saved area name')
local a=storage.guard.excluded_areas[1]
local function contained(x,y,s) return Areas.contains({a},{surface=s or surface,position={x=x,y=y}}) end
check(contained(0,0) and contained(-10,-10),'area includes interior and top-left boundary')
check(not contained(10,0) and not contained(0,10),'area excludes right and bottom boundary')
check(not contained(-10.01,0) and not contained(0,-10.01),'positions just outside rectangle stay protected')
check(not contained(0,0,{valid=true,name='gleba',index=2}),'same coordinates on another planet do not match')
surface.name='renamed-nauvis'
check(contained(0,0),'surface rename preserves exclusion identity')
a.enabled=false;check(not contained(0,0),'disabled exclusion never suppresses alarms');a.enabled=true
surface.valid=false
check(not contained(0,0) and not contained(0,0,{valid=true,name='renamed-nauvis',index=1}),'deleted surface cannot transfer exclusion to replacement surface')
surface.valid=true
local original_controller=player.set_controller;local viewed
local outline
rendering={draw_rectangle=function(spec) outline=spec;return {valid=true} end}
player.set_controller=function(spec) viewed=spec end
player.admin=false;handlers.on_player_demoted();click('fnw_area_view_1')
check(viewed and viewed.surface==surface and viewed.position.x==0,'read-only player can inspect excluded area in remote view')
check(outline and outline.players[1]==player and outline.time_to_live==600 and outline.left_top[1]==-10,'area view highlights exact bounds for the viewing player only')
player.set_controller=original_controller;player.admin=true
registered['fnw-gui']{player_index=1}
change('fnw_a_enabled_1',false,'check');click('fnw_apply')
check(not storage.guard.excluded_areas[1].enabled,'area can be disabled and saved')
change('fnw_a_enabled_1',true,'check')
storage.guard.circuit_revision=storage.guard.circuit_revision+1
click('fnw_apply')
check(not storage.guard.excluded_areas[1].enabled and find(frame(),'fnw_feedback').caption[1]=='fnw-gui.conflict','stale area draft cannot overwrite another admin configuration')
click('fnw_reload');click('fnw_area_remove_1')
check(#storage.guard.excluded_areas==1 and #storage.fnw_ui[1].areas==0,'area removal remains a draft until saved')
click('fnw_reload')
check(#storage.fnw_ui[1].areas==1,'discard undoes area removal')
click('fnw_area_remove_1');click('fnw_apply')
check(#storage.guard.excluded_areas==0,'saved area removal restores protection')
-- Forged selection events must not create exclusions without admin + pending tool.
select_area({left_top={x=0,y=0},right_bottom={x=4,y=4}})
check(#storage.fnw_ui[1].areas==0,'unsolicited area selection event ignored')
click('fnw_area_add');player.admin=false
select_area({left_top={x=0,y=0},right_bottom={x=4,y=4}})
check(#storage.fnw_ui[1].areas==0,'demotion during selection prevents creating exclusion')
player.admin=true;player.cursor_stack.valid_for_read=false
handlers.on_player_cursor_stack_changed{player_index=1}
-- Structure-loss handler skips excluded building centres only.
backing['fnw-enabled']={value=true};backing['fnw-destruction-pause']={value=true}
game.connected_players={};storage.guard.alarm=nil;game.tick_paused=false
local force=game.forces.player
force.get_friend=function() return false end;force.get_cease_fire=function() return false end
local enemy={valid=true,index=2}
local entity={valid=true,name='stone-furnace',type='furnace',surface=surface,force=force,position={x=0,y=0},has_flag=function() return true end}
storage.guard.excluded_areas={Areas.create(surface,{left_top={x=-10,y=-10},right_bottom={x=10,y=10}})}
handlers.on_entity_died{entity=entity,force=enemy}
check(not storage.guard.alarm,'real destruction handler ignores excluded furnace')
entity.type='assembling-machine';entity.name='assembling-machine-3'
handlers.on_entity_died{entity=entity,force=enemy}
check(not storage.guard.alarm,'exclusion is independent of building type')
entity.position={x=10,y=0};handlers.on_entity_died{entity=entity,force=enemy}
check(storage.guard.alarm and game.tick_paused,'building outside exclusion still triggers protection pause')
storage.guard.alarm=nil;game.tick_paused=false;entity.position={x=0,y=0};storage.guard.excluded_areas[1].enabled=false
handlers.on_entity_died{entity=entity,force=enemy}
check(storage.guard.alarm,'disabled area restores destruction alarm')
storage.guard.alarm=nil;game.tick_paused=false;storage.guard.excluded_areas[1].enabled=true
surface.platform={};surface.planet=nil
handlers.on_entity_died{entity=entity}
check(not storage.guard.alarm,'platform losses inside exclusion do not pause')
entity.position={x=12,y=0};handlers.on_entity_died{entity=entity}
check(storage.guard.alarm,'platform losses outside exclusion still pause')
local adjacent=Areas.create(surface,{left_top={x=10,y=-10},right_bottom={x=20,y=10}})
check(Areas.contains({storage.guard.excluded_areas[1],adjacent},entity),'overlapping and adjacent exclusions use union of rectangles')
check(not Areas.validate({{name='',enabled=true,left=0,top=0,right=0,bottom=5}}),'invalid area geometry is rejected before save')
local many={};for i=1,Areas.limit+1 do many[i]=adjacent end
check(not Areas.validate(many),'area list has bounded size')
game.connected_players={player};surface.platform=nil;surface.planet={};storage.guard.excluded_areas={}
storage.guard.alarm=nil;game.tick_paused=false

print('ALL '..checks..' GUI CHECKS PASSED')
