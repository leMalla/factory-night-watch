local prefix = "fnw-"
local function setting(kind, name, default, order, extra)
  local s = {type = kind, name = prefix .. name, setting_type = "runtime-global",
             default_value = default, order = order}
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
data:extend({
  setting("bool-setting", "enabled", true, "a"),
  setting("double-setting", "max-offline-hours", 168, "b", {minimum_value = 0, maximum_value = 8760}),
  setting("bool-setting", "research-pause", true, "c"),
  setting("double-setting", "research-idle-minutes", 5, "d", {minimum_value = 0.1, maximum_value = 1440}),
  setting("bool-setting", "destruction-pause", true, "e"),
  setting("bool-setting", "ignore-walls", true, "f"),
  setting("bool-setting", "ignore-robots", true, "g"),
  setting("bool-setting", "emergency-save", true, "j"),
  setting("string-setting", "forces", "player", "k", {allow_blank = false}),
  setting("string-setting", "excluded-surfaces", "sandbox", "l", {allow_blank = true})
})
