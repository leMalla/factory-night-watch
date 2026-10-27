data:extend({
  {
    type="shortcut", name="fnw-open", action="lua", order="z[factory-night-watch]",
    icon="__base__/graphics/icons/radar.png", icon_size=64,
    small_icon="__base__/graphics/icons/radar.png", small_icon_size=64,
    localised_name={"fnw-gui.open"}
  },
  {
    type="selection-tool", name="fnw-select-network", stack_size=1,
    icon="__base__/graphics/icons/shortcut-toolbar/mip/new-red-wire-x56.png", icon_size=56,
    flags={"only-in-cursor", "not-stackable", "spawnable"}, hidden=true,
    select={border_color={1,0.7,0}, mode={"any-entity"}, cursor_box_type="entity"},
    alt_select={border_color={1,0.7,0}, mode={"any-entity"}, cursor_box_type="entity"},
    localised_name={"fnw-gui.select-network"},
    localised_description={"fnw-gui.select-help"}
  } ,
  {
    type="selection-tool", name="fnw-select-area", stack_size=1,
    icon="__base__/graphics/icons/radar.png", icon_size=64,
    flags={"only-in-cursor", "not-stackable", "spawnable"}, hidden=true,
    select={border_color={0.2,0.8,1}, mode={"nothing"}, cursor_box_type="entity"},
    alt_select={border_color={0.2,0.8,1}, mode={"nothing"}, cursor_box_type="entity"},
    localised_name={"fnw-gui.add-area"},
    localised_description={"fnw-gui.area-select-help"}
  }
})
