local Gui = require("gui")
local Circuits = require("circuits")
local function option(name) return settings.global["fnw-" .. name].value end
local function state()
  storage.guard = storage.guard or {emergency_slot = 0}
  return storage.guard
end
local function active() return option("enabled") and game.is_multiplayer() end
local function offline() return #game.connected_players == 0 end
local function words(text)
  local result = {}
  for word in string.gmatch(text, "[^,]+") do
    word = string.match(word, "^%s*(.-)%s*$")
    if word ~= "" then result[#result + 1] = word end
  end
  return result
end
local function monitored_force(force)
  if not force or not force.valid then return false end
  for _, name in ipairs(words(option("forces"))) do
    if force.name == name then return true end
  end
  return false
end
local function monitored_surface(surface)
  if not surface or not surface.valid then return false end
  local name = string.lower(surface.name)
  for _, part in ipairs(words(option("excluded-surfaces"))) do
    if string.find(name, string.lower(part), 1, true) then return false end
  end
  -- Blueprint Sandboxes creates synthetic surfaces, not actual planets/platforms.
  return surface.planet ~= nil or surface.platform ~= nil
end
local function protected(entity)
  return entity and entity.valid and monitored_force(entity.force)
    and monitored_surface(entity.surface)
end
local function location(entity)
  return {surface = entity.surface.name, x = entity.position.x, y = entity.position.y,
          entity = entity.name}
end
local function reason_text(alarm)
  if not alarm.place then return alarm.reason end
  local p=alarm.place
  return {"fnw-message.reason-place",alarm.reason,p.entity,p.surface,string.format("%.1f",p.x),string.format("%.1f",p.y)}
end
local function report(text, player)
  local message={"", "[Factory Night Watch] ", text}
  if player then player.print(message) else game.print(message) end
  log(helpers.table_to_json(message))
end
local function show_alarm(player)
  local alarm=state().alarm
  if alarm then report({"fnw-message.alarm",reason_text(alarm)},player) end
end
local function trip(reason, place)
  local s = state()
  if s.alarm then return end
  s.alarm = {reason = reason, place = place, tick = game.tick}
  s.last_alarm = s.alarm
  game.tick_paused = true
  show_alarm()
  Gui.refresh_all()
  if option("emergency-save") and game.is_multiplayer() then
    s.emergency_slot = (s.emergency_slot or 0) % 3 + 1
    local name = "factory-night-watch-emergency-" .. s.emergency_slot
    local ok, err = pcall(function() game.server_save(name) end)
    if not ok then log("[Factory Night Watch] Notfallspeicherung fehlgeschlagen: " .. tostring(err)) end
  end
end
local function sync_presence()
  local s=state()
  if not game.is_multiplayer() then return end
  if not offline() then
    if s.offline_since then s.last_offline_ticks=game.tick-s.offline_since end
    s.offline_since,s.research_idle_since=nil,nil
    Circuits.reset()
    if s.empty_pause and not s.alarm then game.tick_paused=false end
    s.empty_pause=nil
  elseif not option("enabled") then
    s.empty_pause=true
    game.tick_paused=true
  else
    if s.empty_pause and not s.alarm then game.tick_paused=false end
    s.empty_pause=nil
    if not s.offline_since then
      s.offline_since=game.tick
      s.research_idle_since=nil
      Circuits.reset()
      report({"fnw-message.started"})
    end
  end
  if s.alarm then game.tick_paused=true end
end
local function periodic()
  sync_presence()
  Gui.refresh_all()
  local s = state()
  if not s.alarm then
    Circuits.poll(s.circuits,active() and offline(),protected,trip)
  end
  if not active() or not offline() or s.alarm then return end
  local elapsed = game.tick - s.offline_since
  local hours = option("max-offline-hours")
  if hours > 0 and elapsed >= hours * 60 * 60 * 60 then
    trip({"fnw-message.time-limit",hours})
    return
  end
  if option("research-pause") then
    local count, busy = 0, false
    for _, force in pairs(game.forces) do
      if monitored_force(force) then
        count = count + 1
        if force.current_research or #(force.research_queue or {}) > 0 then busy = true end
      end
    end
    if count > 0 and not busy then
      s.research_idle_since = s.research_idle_since or game.tick
      if game.tick - s.research_idle_since >= option("research-idle-minutes") * 60 * 60 then
        trip({"fnw-message.research"})
      end
    else
      s.research_idle_since = nil
    end
  else
    s.research_idle_since = nil
  end
end

local reconcile = true
script.on_init(function() state(); sync_presence(); Gui.refresh_all() end)
script.on_configuration_changed(function() state(); sync_presence(); Gui.refresh_all(); reconcile = true end)
script.on_load(function() reconcile = true end)
script.on_event(defines.events.on_tick, function()
  if reconcile then sync_presence(); Gui.refresh_all(); reconcile = false end
  -- A saved protection latch survives reloads. Vanilla unpause alone is not an acknowledgement.
  local s = storage.guard
  if s and game.is_multiplayer() and (s.alarm or (offline() and not option("enabled"))) and not game.tick_paused then game.tick_paused = true end
end)
script.on_nth_tick(60, periodic)
script.on_event(defines.events.on_player_joined_game, function(event)
  sync_presence()
  Gui.ensure(game.get_player(event.player_index))
  Gui.refresh_all()
  if state().alarm then show_alarm(game.get_player(event.player_index)) end
end)
script.on_event(defines.events.on_player_left_game, function() sync_presence(); Gui.refresh_all() end)
script.on_event(defines.events.on_player_created, function(event) Gui.ensure(game.get_player(event.player_index)) end)
script.on_event(defines.events.on_player_promoted, function() Gui.refresh_all() end)
script.on_event(defines.events.on_player_demoted, function() Gui.refresh_all() end)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if string.sub(event.setting, 1, 4) ~= "fnw-" then return end
  local s = state()
  s.research_idle_since = nil
  Circuits.reset()
  sync_presence()
  Gui.refresh_all()
end)
script.on_event(defines.events.on_entity_died, function(event)
  if not active() or not offline() or state().alarm or not option("destruction-pause") then return end
  local entity = event.entity
  if not protected(entity) or not entity.has_flag("player-creation") then return end
  local kind = entity.type
  if kind == "character" or kind == "unit" then return end
  if option("ignore-walls") and (kind == "wall" or kind == "gate") then return end
  if option("ignore-robots") and (kind == "construction-robot" or kind == "logistic-robot"
      or kind == "combat-robot") then return end
  local attacker = event.force
  if not attacker and event.cause and event.cause.valid then attacker = event.cause.force end
  -- On platforms, asteroid destruction may have no enemy force attribution.
  if entity.surface.platform then
    trip({"fnw-message.platform-destroyed"}, location(entity))
  elseif attacker and attacker.valid and attacker.index ~= entity.force.index
      and not entity.force.get_friend(attacker) and not entity.force.get_cease_fire(attacker) then
    trip({"fnw-message.enemy-destroyed"}, location(entity))
  end
end)

local function authorised(command)
  if not command.player_index then return true end
  local player = game.get_player(command.player_index)
  if player and player.admin then return true end
  if player then player.print({"fnw-message.admin-only"}) end
  return false
end
commands.add_command("fnw-status", {"fnw-message.help-status"}, function(command)
  local player = command.player_index and game.get_player(command.player_index) or nil
  local s = state()
  local elapsed = s.offline_since and (game.tick - s.offline_since) / 216000 or 0
  report({"fnw-message.status",tostring(option("enabled")),string.format("%.2f",elapsed),option("max-offline-hours")},player)
  if s.alarm then show_alarm(player) end
end)
local function resume_guard()
  local s = state()
  s.alarm, s.offline_since, s.research_idle_since = nil, nil, nil
  game.tick_paused = false
  sync_presence()
  report({"fnw-message.resumed"})
  Gui.refresh_all()
end
commands.add_command("fnw-resume", {"fnw-message.help-resume"}, function(command)
  if not authorised(command) then return end
  resume_guard()
end)
commands.add_command("fnw-test-pause", {"fnw-message.help-test"}, function(command)
  if not authorised(command) then return end
  trip({"fnw-message.test"})
end)
commands.add_command("fnw-set", {"fnw-message.help-set"}, function(command)
  if not authorised(command) then return end
  local key, raw = string.match(command.parameter or "", "^(%S+)%s+(.+)$")
  local item = key and settings.global["fnw-" .. key] or nil
  local player = command.player_index and game.get_player(command.player_index) or nil
  if not item then report({"fnw-message.unknown-setting"}, player); return end
  local value = raw
  if type(item.value) == "number" then value = tonumber(raw)
  elseif type(item.value) == "boolean" then
    if raw == "true" then value = true elseif raw == "false" then value = false else value = nil end
  end
  if value == nil then report({"fnw-message.invalid-setting",key}, player); return end
  local ok, err = pcall(function() settings.global["fnw-" .. key] = {value = value} end)
  if not ok then report({"fnw-message.setting-failed",tostring(err)}, player); return end
  report(key .. " = " .. tostring(settings.global["fnw-" .. key].value), player)
end)
commands.add_command("fnw-gui", {"fnw-message.help-gui"}, function(command)
  if command.player_index then Gui.open(game.get_player(command.player_index)) end
end)
Gui.configure({resume=resume_guard, test=function() trip({"fnw-message.test"}) end, eligible=protected})
remote.add_interface("factory-night-watch", {
  status = function()
    local s = state()
    return {enabled = option("enabled"), paused = game.tick_paused,
      offline = offline(), offline_since = s.offline_since, circuits = Circuits.status(),
      elapsed_hours = s.offline_since and (game.tick - s.offline_since) / 216000 or 0,
      alarm = s.alarm and {reason = s.alarm.reason, tick = s.alarm.tick, place = s.alarm.place} or nil}
  end
})
