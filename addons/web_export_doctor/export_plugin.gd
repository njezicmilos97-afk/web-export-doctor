@tool
class_name WEDExportPlugin
extends EditorExportPlugin

## Feature 1 — Pre-flight izvjestaj.
## Kaci se na export pipeline i mjeri sta stvarno izlazi iz exporta.

signal report_ready(report: Dictionary)

var _assets: Array[Dictionary] = []
var _is_web: bool = false
var _output_path: String = ""
var _thread_support: bool = false

func _get_name() -> String:
	return "WebExportDoctor"

func _export_begin(features: PackedStringArray, debug: bool, path: String, flags: int) -> void:
	_assets.clear()
	_output_path = path
	_is_web = "web" in features
	_thread_support = _read_thread_support()

func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	if not _is_web:
		return
	# Isto mjerenje koje koristi i "Scan without exporting" — konvertovani oblik,
	# ne izvorni fajl. Bez toga bi isti .wav bio 1.5 MB u jednom prikazu i
	# 0.3 MB u drugom, pa bi tabela protivrjecila sama sebi.
	# measure_packed_size cita samo duzine, nikad sadrzaj — bitno je jer bi za
	# 650 MB projekat ucitavanje u memoriju bilo katastrofalno.
	var size := WEDLimits.measure_packed_size(path)
	if size <= 0:
		return
	_assets.append({"path": path, "type": type, "bytes": size})

func _export_end() -> void:
	if not _is_web:
		return

	var asset_total := 0
	for a in _assets:
		asset_total += int(a["bytes"])

	# PASS/FAIL se racuna nad IZLAZNIM fajlovima, ne nad assetsima.
	# Prvo pokusaj izmjeriti stvarne fajlove na disku — to je tacan rezultat.
	var outputs := _measure_output_files(_output_path)
	var estimated := outputs.is_empty()
	if estimated:
		# Fajlovi jos nisu zapisani — koristi predikciju iz zbira assets.
		outputs = WEDLimits.predict_outputs(asset_total)

	var result := WEDLimits.evaluate(outputs, estimated)
	result["assets"] = _sorted_assets(asset_total)
	result["asset_total_bytes"] = asset_total
	result["thread_support"] = _thread_support
	result["output_path"] = _output_path
	# Oznaka da izvjestaj dolazi iz STVARNOG exporta. Brzi skan emituje isti
	# signal, ali ne zna nista o presetu — bez ove oznake bi Web Fix tab mislio
	# da je export obavljen i prijavio "threadovi iskljuceni" i kada su ukljuceni.
	result["from_export"] = true

	_print_summary(result)
	report_ready.emit(result)

## Nadji fajlove koje je export upravo napisao, npr. index.pck / index.wasm / ...
## Filtrira po basename-u izlaznog puta da ne pokupi tudje fajlove iz foldera.
func _measure_output_files(out_path: String) -> Array:
	if out_path.is_empty():
		return []
	var dir_path := out_path.get_base_dir()
	var stem := out_path.get_file().get_basename()
	if dir_path.is_empty() or stem.is_empty():
		return []

	var da := DirAccess.open(dir_path)
	if da == null:
		return []

	var found: Array = []
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not da.current_is_dir() and name.begins_with(stem) and _is_uploaded(name):
			var full := dir_path.path_join(name)
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				found.append(WEDLimits.make_output(name, f.get_length()))
				f.close()
		name = da.get_next()
	da.list_dir_end()
	return found

## Sta se stvarno salje na itch.io.
## Ako je izlazni folder unutar projekta, Godot importuje slike iz njega i pravi
## .import/.uid fajlove pored njih. Oni nisu dio uploada i ne smiju se brojati.
func _is_uploaded(file_name: String) -> bool:
	var ext := file_name.get_extension().to_lower()
	return ext != "import" and ext != "uid"

func _sorted_assets(total: int) -> Array:
	var list := _assets.duplicate()
	list.sort_custom(func(a, b): return int(a["bytes"]) > int(b["bytes"]))
	for a in list:
		a["percent"] = (float(a["bytes"]) / float(total) * 100.0) if total > 0 else 0.0
		a["verdict"] = WEDLimits.asset_verdict(int(a["bytes"]), total)
	return list

## Feature 3 koristi ovo: da li je Thread Support ukljucen u aktivnom presetu.
## Cita se iz preseta, ne pogadja se — Godot ima odvojene web template binarije
## za thread i nothread varijantu, pa je opcija jedini pouzdan izvor.
func _read_thread_support() -> bool:
	var v = get_option("variant/thread_support")
	if typeof(v) == TYPE_BOOL:
		return v
	var preset := get_export_preset()
	if preset != null:
		var pv = preset.get("variant/thread_support")
		if typeof(pv) == TYPE_BOOL:
			return pv
	return false

func _print_summary(r: Dictionary) -> void:
	var tag := "[WED]"
	print("%s ---- itch.io pre-flight report ----" % tag)
	if r["estimated"]:
		print("%s (estimate — output files are not on disk yet)" % tag)
	for o in r["outputs"]:
		print("%s   %-44s %s" % [tag, o["name"], WEDConfig.format_bytes(o["bytes"])])
	var fr: Dictionary = r["file_rule"]
	var tr: Dictionary = r["total_rule"]
	print("%s   200 MB per file : %s — %s" % [tag, "PASS" if fr["passed"] else "FAIL", fr["message"]])
	print("%s   500 MB total    : %s — %s" % [tag, "PASS" if tr["passed"] else "FAIL", tr["message"]])
