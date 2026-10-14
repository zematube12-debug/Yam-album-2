extends Node3D
## YAM Picture - 3D Digital Album
## Step 1: pick photos from the phone's file manager and show them in 3D.

const MAX_PHOTOS := 40
const MAX_TEX := 1280

var photos: Array[Node3D] = []
var pos: float = 0.0 : set = _set_pos

var cam: Camera3D
var status: Label
var counter: Label
var hint: Label
var pick_btn: Button
var tween: Tween
var dragging := false
var loading := false
var vel := 0.0
var start_pos := 0.0
var t := 0.0


func _ready() -> void:
	_setup_world()
	_setup_ui()


# ---------------------------------------------------------------- world ----
func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.045, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.93, 0.82)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 20, 0)
	light.light_energy = 1.1
	light.light_color = Color(1.0, 0.9, 0.75)
	add_child(light)

	cam = Camera3D.new()
	cam.fov = 45.0
	cam.position = Vector3(0, 0.3, 6.5)
	add_child(cam)

	# floating golden dust
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(6, 3, 3)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.85, 0.5, 0.6)
	q.material = m
	p.mesh = q
	add_child(p)


# ------------------------------------------------------------------- UI ----
func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	hint = _make_label(34)
	hint.text = "YAM Picture\n3D Digital Album\n\nTap \"Pick Photos\" to begin"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	counter = _make_label(26)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(counter)
	counter.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	counter.position.y += 16

	status = _make_label(20)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(700, 0)
	root.add_child(status)
	status.position = Vector2(20, 16)

	pick_btn = Button.new()
	pick_btn.text = "Pick Photos"
	pick_btn.custom_minimum_size = Vector2(280, 72)
	pick_btn.add_theme_font_size_override("font_size", 28)
	root.add_child(pick_btn)
	pick_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE)
	pick_btn.position.y -= 28
	pick_btn.pressed.connect(_pick)


# ----------------------------------------------------------- file picker ----
func _pick() -> void:
	if loading:
		return
	var err := DisplayServer.file_dialog_show(
		"Select photos", "", "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILES,
		PackedStringArray(["image/*"]),
		_on_files_selected)
	if err != OK:
		status.text = "File dialog error: %d" % err


func _on_files_selected(ok: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if ok and paths.size() > 0:
		_load_photos.call_deferred(paths)


func _load_photos(paths: PackedStringArray) -> void:
	loading = true
	pick_btn.disabled = true
	if tween:
		tween.kill()
	for n in photos:
		n.queue_free()
	photos.clear()

	var total := mini(paths.size(), MAX_PHOTOS)
	var failed := 0
	var last_error := ""
	for k in total:
		status.text = "Loading %d / %d ..." % [k + 1, total]
		await get_tree().process_frame
		var img := _load_image(paths[k])
		if img == null:
			failed += 1
			last_error = paths[k]
			continue
		photos.append(_make_photo(img))
		await get_tree().process_frame

	loading = false
	pick_btn.disabled = false
	if photos.is_empty():
		status.text = "Could not read the photos.\n" + last_error
		return

	hint.visible = false
	status.text = ""
	if failed > 0:
		status.text = "%d photo(s) could not be loaded" % failed
	if paths.size() > MAX_PHOTOS:
		status.text += " (max %d photos)" % MAX_PHOTOS

	# fly-in intro
	pos = -3.0
	tween = create_tween()
	tween.tween_property(self, "pos", 0.0, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------ image load ----
func _load_image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes)
	if err != OK:
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return null

	var longest := maxi(img.get_width(), img.get_height())
	if longest > MAX_TEX:
		var s := float(MAX_TEX) / float(longest)
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_BILINEAR)

	match _exif_orientation(bytes):
		3:
			img.rotate_180()
		6:
			img.rotate_90(CLOCKWISE)
		8:
			img.rotate_90(COUNTERCLOCKWISE)

	img.generate_mipmaps()
	return img


func _u16(b: PackedByteArray, o: int, le: bool) -> int:
	if o < 0 or o + 1 >= b.size():
		return 0
	if le:
		return b[o] | (b[o + 1] << 8)
	return (b[o] << 8) | b[o + 1]


func _u32(b: PackedByteArray, o: int, le: bool) -> int:
	if o < 0 or o + 3 >= b.size():
		return 0
	if le:
		return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


## Reads the EXIF orientation tag (phone photos are often stored rotated).
func _exif_orientation(b: PackedByteArray) -> int:
	if b.size() < 12 or b[0] != 0xFF or b[1] != 0xD8:
		return 1
	var i := 2
	while i + 4 < b.size():
		if b[i] != 0xFF:
			break
		var marker := b[i + 1]
		if marker == 0xDA:
			break
		var seg := (b[i + 2] << 8) | b[i + 3]
		if marker == 0xE1 and b[i + 4] == 0x45 and b[i + 5] == 0x78:
			var tiff := i + 10
			var le := b[tiff] == 0x49
			var ifd := tiff + _u32(b, tiff + 4, le)
			var n := _u16(b, ifd, le)
			for k in n:
				var e := ifd + 2 + k * 12
				if _u16(b, e, le) == 0x0112:
					return _u16(b, e + 8, le)
			return 1
		i += 2 + seg
	return 1


# ----------------------------------------------------------- 3D photo ----
func _make_photo(img: Image) -> Node3D:
	var tex := ImageTexture.create_from_image(img)
	var w := float(img.get_width())
	var h := float(img.get_height())
	var sc := minf(3.4 / w, 3.0 / h)
	var qw := w * sc
	var qh := h * sc

	var root := Node3D.new()

	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(qw + 0.16, qh + 0.16, 0.06)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.78, 0.6, 0.3)
	fm.metallic = 0.3
	fm.roughness = 0.45
	box.material = fm
	frame.mesh = box
	root.add_child(frame)

	var pic := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(qw, qh)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_texture = tex
	pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = pm
	pic.mesh = quad
	pic.position.z = 0.032
	root.add_child(pic)

	add_child(root)
	root.visible = false
	return root


# --------------------------------------------------------------- layout ----
func _set_pos(v: float) -> void:
	pos = v
	_update_layout()


func _update_layout() -> void:
	for i in photos.size():
		var d: float = float(i) - pos
		var c: float = clampf(d, -1.0, 1.0)
		var extra: float = d - c
		var n := photos[i]
		n.visible = absf(d) < 4.0
		n.position = Vector3(c * 2.6 + extra * 0.8, 0.2, -absf(c) * 1.6 - absf(extra) * 0.4)
		n.rotation.y = -c * deg_to_rad(50.0)
		var s: float = 1.0 - absf(c) * 0.12
		n.scale = Vector3(s, s, s)
	if counter and photos.size() > 0:
		var cur := clampi(roundi(pos), 0, photos.size() - 1) + 1
		counter.text = "%d / %d" % [cur, photos.size()]


# ---------------------------------------------------------------- input ----
func _unhandled_input(e: InputEvent) -> void:
	if photos.is_empty():
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			dragging = true
			vel = 0.0
			start_pos = pos
			if tween:
				tween.kill()
		elif dragging:
			dragging = false
			var target := roundi(pos + vel * 6.0)
			var lo := maxi(roundi(start_pos) - 1, 0)
			var hi := mini(roundi(start_pos) + 1, photos.size() - 1)
			target = clampi(target, lo, hi)
			tween = create_tween()
			tween.tween_property(self, "pos", float(target), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif e is InputEventMouseMotion and dragging:
		var w := get_viewport().get_visible_rect().size.x
		vel = -e.relative.x / w * 3.0
		pos = clampf(pos + vel, 0.0, float(photos.size() - 1))


func _process(delta: float) -> void:
	t += delta
	cam.position = Vector3(sin(t * 0.35) * 0.2, 0.3 + sin(t * 0.5) * 0.05, 6.5)
	cam.look_at(Vector3(0, 0.1, 0))
