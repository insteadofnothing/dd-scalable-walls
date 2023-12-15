# Scalable Walls
#
# This mod lets you scale walls using the Select Tool.


var script_class = "tool"

var mod_id = "insteadofnothing.ScalableWalls"
var texture_cache = {}

var select_tool = null
var select_panel = null
var scale_children = null
var select_x_scale = null
var select_y_scale = null
var scales_added = false
var lock_dimensions = false

var scale_map = []


func get_selected_walls():
  """
  Returns all walls currently selected by the Select Tool.
  """
  var objects = []
  # Selectables will crash if the user has shift-clicked and selected the same
  # object twice. Use RawSelectables instead and skip duplicates.
  for raw in select_tool.RawSelectables:
    if raw.Type != 1 or raw.Thing in objects:
      continue
    objects.append(raw.Thing)
  return objects


func get_last_added(tool_panel):
  """
  Gets the last item added to the tool panel.

  This is needed because some of the UI methods don't return the newly created
  objects.
  """
  return tool_panel.Align.get_children()[len(tool_panel.Align.get_children()) - 1]


func load_texture(path: String) -> Texture:
  """
  Loads a texture based on the path, either internal or external.
  """
  if path.begins_with("res://packs"):
    var tex_file = File.new()
    tex_file.open(path, File.READ)

    var image_data = tex_file.get_buffer(tex_file.get_len())
    var img = Image.new()
    img.load_png_from_buffer(image_data)

    var img_tex = ImageTexture.new()
    img_tex.create_from_image(img)
    tex_file.close()

    return img_tex
  else:
    return load(path)


func cache_textures(wall):
  """
  Caches a wall's textures for retrieval during scaling.
  """
  var path = wall.Texture.resource_path
  if path and not texture_cache.has(path):
    texture_cache[path] = wall.Texture.get_data().duplicate()

  var end_path = wall.EndTexture.resource_path
  if end_path and not texture_cache.has(end_path):
    texture_cache[end_path] = wall.EndTexture.get_data().duplicate()


func create_scale_entry(wall, scale: Array):
  """
  Creates a new scale entry to record a wall's scaling data.

  Scale entry schema:
  {
    "scale": Array[int]
    "texture": String,
    "end_texture": String,
  }
  """
  var entry = {}
  entry["scale"] = scale
  entry["texture"] = wall.Texture.resource_path
  entry["end_texture"] = wall.EndTexture.resource_path

  return entry


func get_scaled_texture(path: String, scale: Array) -> ImageTexture:
  """
  Returns a new texture adjusted to the appropriate scale.
  """
  var tex = load_texture(path)
  var img = tex.get_data()

  # Ensure the dimensions are within the required range [1, 16384].
  var width = max(1, min(img.get_width() * scale[0], 16384))
  var height = max(1, min(img.get_height() * scale[1], 16384))

  img.resize(width, height)
  var scaled_texture = ImageTexture.new()
  scaled_texture.create_from_image(img)

  return scaled_texture


func scale_wall(wall, scale: Array):
  """
  Scales a wall to the target length (x) and width (y) and redraws it.
  """
  var node_id = String(wall.get_meta("node_id"))
  var scale_cache = get_scale_cache()

  # Add a new entry to the cache if the wall hasn't been stored yet.
  if not (node_id in scale_cache):
    print("[Scalable Walls]: New wall with id [", node_id,
          "] found. Creating new scale entry.")
    scale_cache[node_id] = create_scale_entry(wall, scale)
    save_scale_cache(scale_cache)

  # Scale the wall's textures and redraw to update the UI.
  var entry = scale_cache[node_id]
  wall.Texture = get_scaled_texture(entry["texture"], scale)
  wall.EndTexture = get_scaled_texture(entry["end_texture"], scale)
  wall.RemakeLines()

  scale_cache[node_id]["scale"] = scale
  save_scale_cache(scale_cache)

var correcting = false
func on_scale_change(is_x: bool):
  """
  Adds a scale request to the scale map, which will be performed in update().
  """
  if correcting:
    correcting = false
    return

  var walls = get_selected_walls()
  for wall in walls:
    var scale = [select_x_scale.value, select_y_scale.value]

    var scale_cache = get_scale_cache()
    var node_id = String(wall.get_meta("node_id"))
    if not scale_cache.has(node_id):
      scale_cache[node_id] = create_scale_entry(wall, [1, 1])
      save_scale_cache()
    var entry = scale_cache[node_id]
    var ratio = 1

    if lock_dimensions:
      ratio = entry["scale"][0] / entry["scale"][1]
      correcting = true
      if is_x:
        scale[1] = scale[0] / ratio
      else:
        scale[0] = scale[1] * ratio
    else:
      if is_x:
        scale[1] = entry["scale"][1]
      else:
        scale[0] = entry["scale"][0]

    scale_map[wall.get_meta("node_id")] = scale


func on_x_change(value: float):
  on_scale_change(true)


func on_y_change(value: float):
  on_scale_change(false)


func on_reset_pressed():
  """
  Resets the scale of each selected wall, removing it from the scale cache.
  """
  var scale_cache = get_scale_cache()
  var pruned_ids = []

  # Reset the texture of each modified wall.
  for wall in get_selected_walls():
    var node_id = String(wall.get_meta("node_id"))
    if scale_cache.has(node_id):
      var entry = scale_cache[node_id]
      wall.Texture = load(entry["texture"])
      wall.EndTexture = load(entry["end_texture"])
      wall.RemakeLines()

      pruned_ids.append(node_id)

  # Remove the reset walls from the cache.
  for node_id in pruned_ids:
    scale_cache.erase(node_id)

  save_scale_cache(scale_cache)
  select_tool.DeselectAll()


func on_lock_pressed():
  """
  Toggles the flag which locks the X and Y scale to the same value.
  """
  lock_dimensions = not lock_dimensions


func add_scales():
  """
  Adds the scale UI to the Select Tool panel.
  """
  for child in scale_children:
    select_panel.Align.add_child(child)
    select_panel.Align.move_child(child, 13)


func remove_scales():
  """
  Removes the scale UI from the Select Tool panel.
  """
  for child in scale_children:
    select_panel.Align.remove_child(child)


func init_select_scales():
  """
  Initializes and stores the Select Tool panel UI elements.
  """
  scale_children = []
  # Add the x scale and connect it to the scaling function.
  select_panel.CreateLabel("X Scale")
  scale_children.append(get_last_added(select_panel))
  select_x_scale = select_panel.CreateSlider(
      "XSliderID", 1, 0.1, 25, 0.01, true)
  select_x_scale.connect("value_changed", self, "on_x_change")
  scale_children.append(get_last_added(select_panel))

  # Add the y scale and connect it to the scaling function.
  select_panel.CreateLabel("Y Scale")
  scale_children.append(get_last_added(select_panel))
  select_y_scale = select_panel.CreateSlider(
      "YSliderID", 1, 0.1, 25, 0.01, true)
  select_y_scale.connect("value_changed", self, "on_y_change")
  scale_children.append(get_last_added(select_panel))

  var lock_toggle = select_panel.CreateToggle(
      "LockRatioID", false, "Unlock Ratio", Global.Root + "icons/unlock.png",
      "Lock Ratio", Global.Root +"icons/lock.png")
  lock_toggle.connect("pressed", self, "on_lock_pressed")
  scale_children.append(lock_toggle)

  var reset_button = select_panel.CreateButton(
      "Reset Scale", Global.Root +"icons/reset.png")
  reset_button.connect("pressed", self, "on_reset_pressed")
  scale_children.append(reset_button)

  select_panel.CreateSeparator()
  scale_children.append(get_last_added(select_panel))

  # Invert the children so that they will be re-added in the proper order.
  scale_children.invert()
  remove_scales()


func get_data_text():
  """
  Gets or creates a Text object used to store mod data within the map file.
  """
  # Cycle through each level to find any existing data text object.
  for level in Global.World.levels:
    for text in level.Texts.get_children():
      if text.text.begins_with(mod_id):
        return text

  # Create a new data text if no existing text was found.
  print("[Scalable Walls]: Data text not found. Creating new text object.")
  var level = Global.World.levels[Global.World.CurrentLevelId]
  var data_text = level.Texts.CreateText()
  data_text.text = mod_id + ": {}"

  # This id is a placeholder. Dungeondraft will fill in an appropriate id.
  data_text.set_meta("node_id", 9999)
  data_text.fontName = "Libre Baskerville"

  # Move the data text off screen to hide it from the user.
  data_text.rect_global_position = Vector2(-100, -200)

  level.Texts.Save()

  return data_text


func get_scale_cache() -> Dictionary:
  """
  Retrieves the scale cache from a hidden text field and parses it as JSON.
  """
  var data_text = get_data_text()
  return JSON.parse(data_text.text.trim_prefix(mod_id + ": ")).result


func save_scale_cache(scale_cache: Dictionary):
  """
  Saves the cache of scale data as JSON in a hidden text field.
  """
  var data_text = get_data_text()
  data_text.text = mod_id + ": " + JSON.print(scale_cache)
  data_text.Save()


func init_wall_scaling():
  """
  Scales each wall according to the scale cache for the initial map load.
  """
  print("[Scalable Walls]: Scaling walls from cached data.")
  var scale_cache = get_scale_cache()
  var pruned_ids = []
  for node_id in scale_cache:
    var wall = Global.World.GetNodeByID(int(node_id))
    if not wall:
      pruned_ids.append(node_id)
      continue
    var entry = scale_cache[node_id]
    wall.Texture = load_texture(entry["texture"])
    wall.EndTexture = load_texture(entry["end_texture"])
    scale_wall(wall, scale_cache[node_id]["scale"])

  # Erase any entries for deleted walls.
  for node_id in pruned_ids:
    scale_cache.erase(node_id)


func update(delta: float):
  """
  Scales any pending walls, updates the sliders, and synchronizes the wall
  cache.
  """
  # Process any pending wall scales. This is done here to reduce the from the
  # rapid-fire events dispatched to the scale slider as it's dragged.
  var local_scale_map = scale_map.duplicate(true)
  for node_id in local_scale_map:
    var wall = Global.World.GetNodeByID(node_id)
    if not wall:
      continue
    scale_wall(wall, local_scale_map[node_id])
  scale_map = {}

  # Only show the scales when walls are selected.
  var walls = get_selected_walls()
  if not walls and scales_added:
    remove_scales()
    scales_added = false
    return

  if walls and not scales_added:
    add_scales()
    scales_added = true

  if walls:
    # Update the scale values to match the current wall.
    var wall = walls[0]
    var node_id = String(wall.get_meta("node_id"))
    var scale_cache = get_scale_cache()
    if not scale_cache.has(node_id):
      select_x_scale.value = 1
      select_y_scale.value = 1
    else:
      var entry = scale_cache[node_id]
      select_x_scale.value = entry["scale"][0]
      select_y_scale.value = entry["scale"][1]

  # Synchronize the scale cache with the current wall data.
  var scale_cache = get_scale_cache()
  var pruned_ids = []
  for node_id in scale_cache:
    var wall = Global.World.GetNodeByID(int(node_id))
    if not wall:
      pruned_ids.append(node_id)
      continue

    var entry = scale_cache[node_id]
    var path = wall.Texture.resource_path
    if path and path != entry["texture"]:
      print("[Scalable Walls]: Wall texture changed. Scaling the new texture.")
      scale_cache[node_id]["texture"] = path
      scale_cache[node_id]["end_texture"] = wall.EndTexture.resource_path
      save_scale_cache(scale_cache)
      scale_wall(wall, scale_cache[node_id]["scale"])

  # Prune any deleted walls from the cache.
  for node_id in pruned_ids:
    scale_cache.erase(node_id)
  save_scale_cache(scale_cache)


func start():
  """
  Initializes the scale sliders to control wall scale.
  """
  select_tool = Global.Editor.Tools["SelectTool"]
  select_panel = Global.Editor.Toolset.GetToolPanel("SelectTool")
  init_select_scales()

  # Walls won't be scaled on the initial load. Scale them using the cache.
  init_wall_scaling()
