@tool
class_name TerrainPanel
extends PanelContainer

## TerrainPanel — the unified mobile-first editor panel (TKT-021).
##
## One left-edge, full-height, dismissable panel that hosts EVERY terrain
## control as tabs (Fırça / Varlıklar / Chunk'lar). Replaces both the old
## 1100px-wide toolbar band (whose internal ScrollContainer hijacked
## horizontal drags on the top of the screen — the reported "kayma") and
## the free-floating 430×360 asset window that covered the phone's tiny
## 3D viewport.
##
## Deliberately a DUMB SHELL: it owns layout only. The plugin keeps
## ownership of every control and every signal handler and fills the tab
## roots this class exposes (ADR-021-3) — so the rewrite moves pixels, not
## behaviour. Width is fixed at PANEL_WIDTH so the viewport keeps ~83% of
## a landscape phone; each tab scrolls vertically inside.

signal closed

const PANEL_WIDTH := 340.0
const EDGE_MARGIN := 8.0

var tabs: TabContainer
# Tab roots the plugin fills. Each lives inside its own ScrollContainer.
var brush_tab_root: VBoxContainer
var assets_tab_root: VBoxContainer


func _init() -> void:
	name = "_MobileTerrainPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.15, 0.97)
	style.border_width_right = 2
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	hide()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "🏔 MobileTerrain3D"
	title.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(40, 40)
	btn_close.tooltip_text = "Paneli kapat (üst şeritteki 🏔 Panel ile tekrar aç)"
	btn_close.pressed.connect(_on_close_pressed)
	header.add_child(btn_close)
	outer.add_child(header)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	brush_tab_root = _make_scrolled_tab("Fırça")
	assets_tab_root = _make_scrolled_tab("Varlıklar")


# Anchor to the LEFT edge of `parent_screen`, full height. Called once by
# the plugin after parenting. Anchors (not fixed offsets) so editor window
# rotation/resize keeps the panel glued to the edge.
func attach_to(parent_screen: Control) -> void:
	parent_screen.add_child(self)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = EDGE_MARGIN
	offset_right = EDGE_MARGIN + PANEL_WIDTH
	offset_top = EDGE_MARGIN
	offset_bottom = -EDGE_MARGIN


# Add a pre-built Control (e.g. the chunk visibility tab) as its own tab.
# The control's `name` becomes the tab title.
func add_tab_control(control: Control) -> void:
	tabs.add_child(control)


# Build "<title>" tab = ScrollContainer (vertical) wrapping a VBox the
# plugin fills with control rows. Returns the VBox.
func _make_scrolled_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)
	return root


func _on_close_pressed() -> void:
	hide()
	closed.emit()
