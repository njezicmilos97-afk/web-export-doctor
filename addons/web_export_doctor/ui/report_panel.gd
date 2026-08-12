@tool
class_name WEDReportPanel
extends VBoxContainer

## Feature 1 — Pre-flight izvjestaj (Lite + Pro).

signal report_updated(report: Dictionary)

## Namjerno bez zasebne "Tip" kolone: ekstenzija je vec u imenu fajla, a dock je
## po defaultu ~250 px — cetvrta kolona je gurala imena na 5 znakova, pa su
## razliciti fajlovi izgledali identicno ("level", "level", "level").
const COL_PATH := 0
const COL_SIZE := 1
const COL_PCT := 2
const COL_COUNT := 3

var _rule_file: Label
var _rule_total: Label
var _summary: Label
var _tree: Tree
var _scan_btn: Button

var _report: Dictionary = {}
var _sort_col: int = COL_SIZE
var _sort_desc: bool = true

# UI se gradi u _init(), ne u _ready(). Plugin dodaje panele u TabContainer
# koji jos nije u editorovom stablu, pa _ready() tada ne okida — panel bi ostao
# prazan, a TabContainer bi za naslov taba procitao automatsko ime cvora.
func _init() -> void:
	name = "Report"
	add_theme_constant_override("separation", 6)
	_build()

func _build() -> void:
	var head := Label.new()
	head.text = "itch.io pre-flight"
	head.add_theme_font_size_override("font_size", 14)
	add_child(head)

	# Dva NEZAVISNA rezultata, kako itch.io i provjerava.
	_rule_file = Label.new()
	_rule_file.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_rule_file)

	_rule_total = Label.new()
	_rule_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_rule_total)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 11)
	add_child(_summary)

	add_child(HSeparator.new())

	_scan_btn = Button.new()
	_scan_btn.text = "Scan without exporting (estimate)"
	_scan_btn.tooltip_text = "Quick estimate over res:// without a full export."
	_scan_btn.pressed.connect(quick_scan)
	add_child(_scan_btn)

	_tree = Tree.new()
	_tree.columns = COL_COUNT
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 220)
	_tree.set_column_title(COL_PATH, "Resource")
	_tree.set_column_title(COL_SIZE, "Size")
	_tree.set_column_title(COL_PCT, "%")
	_tree.set_column_expand(COL_PATH, true)
	_tree.set_column_expand(COL_SIZE, false)
	_tree.set_column_expand(COL_PCT, false)
	_tree.set_column_custom_minimum_width(COL_SIZE, 66)
	_tree.set_column_custom_minimum_width(COL_PCT, 44)
	_tree.column_title_clicked.connect(_on_title_clicked)
	add_child(_tree)

	_set_idle()

func _set_idle() -> void:
	_rule_file.text = "Rule: 200 MB per file   —"
	_rule_total.text = "Rule: 500 MB total      —"
	_summary.text = "Export the project for Web, or click scan for a quick estimate."
	_paint(_rule_file, Color.GRAY)
	_paint(_rule_total, Color.GRAY)
	_paint(_summary, Color.GRAY)

func show_report(report: Dictionary) -> void:
	_report = report
	var fr: Dictionary = report["file_rule"]
	var tr: Dictionary = report["total_rule"]

	_rule_file.text = "Rule: 200 MB per file   %s\n   %s" % [
		"PASS" if fr["passed"] else "FAIL", fr["message"]]
	_paint(_rule_file, _ok_color(fr["passed"]))

	_rule_total.text = "Rule: 500 MB total      %s\n   %s" % [
		"PASS" if tr["passed"] else "FAIL", tr["message"]]
	_paint(_rule_total, _ok_color(tr["passed"]))

	var lines: Array[String] = []
	if report.get("estimated", false):
		lines.append("ESTIMATE — output files are not on disk yet.")

	# Izlazni folder unutar projekta znaci da svaki export pakuje prethodni.
	var recycled := WEDLimits.find_recycled_build_output(
		report.get("assets", []), _export_output_dirs())
	if not recycled.is_empty():
		var wasted := 0
		for r in recycled:
			wasted += int(r["bytes"])
		lines.append("WARNING: %d file(s) in the pack come from your export output folder (%s). Every export packs the previous one — move the output outside the project, or add it to exclude_filter."
			% [recycled.size(), WEDConfig.format_bytes(wasted)])
	for o in report["outputs"]:
		lines.append("%s: %s" % [o["name"], WEDConfig.format_bytes(o["bytes"])])
	_summary.text = "\n".join(lines)
	_paint(_summary, Color.GRAY)

	_populate()
	report_updated.emit(report)

func _populate() -> void:
	_tree.clear()
	var assets: Array = _report.get("assets", [])
	if assets.is_empty():
		return
	var sorted := assets.duplicate()
	sorted.sort_custom(_comparator)

	# Ista imena fajlova u razlicitim folderima su cesta ("data.dat", "atlas.png").
	# Ako se ime ponavlja, uz njega ide i folder — inace su redovi nerazlucivi.
	var name_counts := {}
	for a in sorted:
		var n := str(a["path"]).get_file()
		name_counts[n] = int(name_counts.get(n, 0)) + 1

	var root := _tree.create_item()
	for a in sorted:
		var it := _tree.create_item(root)
		it.set_text(COL_PATH, _short_path(str(a["path"]), name_counts))
		it.set_tooltip_text(COL_PATH, str(a["path"]))
		it.set_text(COL_SIZE, WEDConfig.format_bytes(int(a["bytes"])))
		it.set_text(COL_PCT, "%.0f%%" % float(a.get("percent", 0.0)))
		_tint(it, int(a.get("verdict", WEDLimits.Verdict.PASS)))

## Prikazuje ime fajla, ne put. Putevi se razlikuju tek na kraju
## ("level2/chunk_a.dat" vs "level2/chunk_b.dat"), a bas kraj se odsijeca u
## uskoj koloni — pa su razliciti redovi izgledali identicno.
## Pun put je u tooltip-u, a grupisanje po folderima u Split tabu.
##
## Izuzetak: kad vise fajlova dijeli isto ime, samo ime nista ne govori —
## tada se prefiksuje roditeljskim folderom ("forest/data.dat").
func _short_path(res_path: String, name_counts: Dictionary = {}) -> String:
	var file_name := res_path.get_file()
	if int(name_counts.get(file_name, 1)) <= 1:
		return file_name
	var parent := res_path.get_base_dir().get_file()
	if parent.is_empty():
		return file_name
	return parent + "/" + file_name

## Boja reda oznacava koliko asset doprinosi velicini packa.
## To NIJE itch.io pravilo — pojedinacni asset itch.io nikad ne vidi.
func _tint(item: TreeItem, verdict: int) -> void:
	var c: Color
	match verdict:
		WEDLimits.Verdict.FAIL:
			c = Color(1.0, 0.35, 0.35)
		WEDLimits.Verdict.WARN:
			c = Color(1.0, 0.75, 0.3)
		_:
			return
	for col in COL_COUNT:
		item.set_custom_color(col, c)

func _comparator(a: Dictionary, b: Dictionary) -> bool:
	var x
	var y
	match _sort_col:
		COL_PATH:
			# Sortiraj po onome sto je PRIKAZANO (ime fajla), ne po punom putu —
			# inace klik na zaglavlje daje redoslijed koji izgleda nasumicno.
			x = str(a["path"]).get_file()
			y = str(b["path"]).get_file()
		COL_PCT:
			x = float(a.get("percent", 0.0))
			y = float(b.get("percent", 0.0))
		_:
			x = int(a["bytes"])
			y = int(b["bytes"])
	if _sort_desc:
		return x > y
	return x < y

func _on_title_clicked(column: int, _mouse_button: int) -> void:
	if column == _sort_col:
		_sort_desc = not _sort_desc
	else:
		_sort_col = column
		_sort_desc = true
	_populate()

## Brza procjena bez punog exporta. Namjerno oznacena kao procjena:
## ne vidi konvertovane oblike importovanih resursa niti tacnu velicinu
## web runtime-a, pa se moze razlikovati od stvarnog exporta.
func quick_scan() -> void:
	var assets := _scan_dir("res://", _export_output_dirs())
	var total := 0
	for a in assets:
		total += int(a["bytes"])

	var report := WEDLimits.evaluate(WEDLimits.predict_outputs(total), true)
	assets.sort_custom(func(a, b): return int(a["bytes"]) > int(b["bytes"]))
	for a in assets:
		a["percent"] = (float(a["bytes"]) / float(total) * 100.0) if total > 0 else 0.0
		a["verdict"] = WEDLimits.asset_verdict(int(a["bytes"]), total)
	report["assets"] = assets
	report["asset_total_bytes"] = total
	show_report(report)

## Ekstenzije koje su rezultat exporta ili editorska metadata, a ne izvorni
## sadrzaj. Bez ovog filtera skan broji ranije napravljene .pck/.wasm fajlove i
## procjena naraste visestruko.
const OUTPUT_EXTENSIONS := ["pck", "wasm", "zip"]
const META_EXTENSIONS := ["import", "uid"]
## Folderi koje addon sam pravi.
const SKIPPED_DIRS := ["addons", "build_split"]

## Dubina je ogranicena zbog simbolickih linkova i junction pointa: folder koji
## pokazuje na svog pretka vodi u beskonacnu rekurziju i rusi editor. Nijedan
## realan projekat nema ovoliko ugnijezdenih foldera.
const MAX_SCAN_DEPTH := 32

func _scan_dir(path: String, skip_dirs: PackedStringArray = PackedStringArray(), depth := 0) -> Array:
	var out: Array = []
	if depth > MAX_SCAN_DEPTH:
		push_warning("Web Export Doctor: scan stopped at %d levels deep (%s). Symlink loop?" % [MAX_SCAN_DEPTH, path])
		return out
	var da := DirAccess.open(path)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n.begins_with("."):
			n = da.get_next()
			continue
		var full := path.path_join(n)
		if da.current_is_dir():
			if not SKIPPED_DIRS.has(n) and not skip_dirs.has(full):
				out.append_array(_scan_dir(full, skip_dirs, depth + 1))
		else:
			var ext := n.get_extension().to_lower()
			if not META_EXTENSIONS.has(ext) and not OUTPUT_EXTENSIONS.has(ext):
				# Mjeri konvertovani oblik, ne izvorni fajl — to je ono sto
				# stvarno zavrsi u packu.
				var size := WEDLimits.measure_packed_size(full)
				if size > 0:
					out.append({"path": full, "type": ext, "bytes": size})
		n = da.get_next()
	da.list_dir_end()
	return out

## Izlazni folderi procitani iz export_presets.cfg. Preciznije nego pogadjati
## ime "build" — korisnik svoj izlazni folder moze zvati kako hoce.
func _export_output_dirs() -> PackedStringArray:
	var dirs := PackedStringArray()
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return dirs
	for section in cfg.get_sections():
		if section.ends_with(".options"):
			continue
		var p := str(cfg.get_value(section, "export_path", ""))
		if p.is_empty():
			continue
		var d := ("res://" + p).get_base_dir()
		if d != "res://" and not dirs.has(d):
			dirs.append(d)
	return dirs

func _ok_color(ok: bool) -> Color:
	return Color(0.45, 0.85, 0.45) if ok else Color(1.0, 0.4, 0.4)

func _paint(l: Label, c: Color) -> void:
	l.add_theme_color_override("font_color", c)
