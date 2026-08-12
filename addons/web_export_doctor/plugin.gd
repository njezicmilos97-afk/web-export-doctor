@tool
extends EditorPlugin

## Web Export Doctor — provjerava da li Web export prolazi itch.io limite
## PRIJE zipovanja i uploada.

const DOCK_TITLE := "Web Export Doctor"

const BASE := "res://addons/web_export_doctor/"

var _dock: Control
var _tabs: TabContainer
var _report_panel: WEDReportPanel
# Pro paneli se ucitavaju uslovno — u Lite paketu ti fajlovi ne postoje,
# pa se na njih ne smije referencirati preko class_name.
var _split_panel: Control
var _webfix_panel: Control
var _export_plugin: WEDExportPlugin

func _enter_tree() -> void:
	_export_plugin = WEDExportPlugin.new()
	_export_plugin.report_ready.connect(_on_report_ready)
	add_export_plugin(_export_plugin)

	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

func _build_dock() -> Control:
	var root := VBoxContainer.new()
	root.name = DOCK_TITLE

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Namjerno bez sirinskog minimuma: dock je po defaultu ~200 px, pa bi
	# siri minimum gurao naslove tabova van vidljivog dijela panela.
	_tabs.custom_minimum_size = Vector2(0, 360)
	root.add_child(_tabs)

	_report_panel = WEDReportPanel.new()
	_tabs.add_child(_report_panel)

	# Bez rucnih preloma unutar pasusa — Label sam prelama po sirini docka, pa
	# rucni "\n" pravi kratke odsjecene redove usred recenice.
	_split_panel = _make_pro_panel("ui/split_panel.gd", "Split", "Auto-split is part of the Pro version.\n\nWhen the pre-flight report says FAIL, this splits your content into a base .pck plus extra packages under the limit, using Godot's own export pipeline.")
	_tabs.add_child(_split_panel)

	_webfix_panel = _make_pro_panel("ui/webfix_panel.gd", "Web Fix", "Web fixes are part of the Pro version.\n\nThread Support detection, the itch.io SharedArrayBuffer checklist, the Firefox iframe workaround, and measured audio settings for web.")
	_tabs.add_child(_webfix_panel)

	# Skeniranje bez exporta puni i plan podjele, ne samo izvjestaj.
	_report_panel.report_updated.connect(_on_report_ready)

	var foot := Label.new()
	foot.text = "v%s  •  %s" % [WEDConfig.VERSION, "Pro" if WEDConfig.IS_PRO else "Lite"]
	foot.add_theme_font_size_override("font_size", 10)
	foot.add_theme_color_override("font_color", Color.GRAY)
	root.add_child(foot)

	return root

## Ucitaj Pro panel ako postoji; inace vrati zakljucanu zamjenu.
## Lite paket fizicki ne sadrzi Pro fajlove, pa se provjerava postojanje.
func _make_pro_panel(rel_path: String, title: String, blurb: String) -> Control:
	if WEDConfig.IS_PRO and ResourceLoader.exists(BASE + rel_path):
		var scr := load(BASE + rel_path)
		if scr != null:
			return scr.new()
	return _locked_panel(title, blurb)

func _locked_panel(title: String, blurb: String) -> Control:
	var box := VBoxContainer.new()
	box.name = title
	box.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)

	# Dok Pro stranica ne postoji, dugme koje vodi nikuda gori je od nikakvog.
	if not WEDConfig.has_upgrade_url():
		l.text = blurb + "\n\nThe Pro version is not published yet."
		return box

	l.text = blurb + "\n\nUpgrade to Pro:"
	var link := LinkButton.new()
	link.text = WEDConfig.UPGRADE_URL
	link.uri = WEDConfig.UPGRADE_URL
	box.add_child(link)
	return box

func _on_report_ready(report: Dictionary) -> void:
	if _report_panel != null and not report.is_empty():
		# Izbjegni petlju: panel emituje isti signal koji sam obradjuje.
		if _report_panel.get("_report") != report:
			_report_panel.show_report(report)
	if _split_panel != null and _split_panel.has_method("set_assets"):
		_split_panel.set_assets(report.get("assets", []))
	if _webfix_panel != null and _webfix_panel.has_method("apply_report"):
		_webfix_panel.apply_report(report)
