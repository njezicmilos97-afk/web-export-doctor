@tool
extends SceneTree

## Poredi PROCJENU ("Skeniraj bez exporta") sa STVARNIM exportom.
##
## Bitno na projektima sa stvarnim resursima: Godot konvertuje PNG u .ctex,
## scene u .scn itd. Ako procjena mjeri izvorne fajlove, a u pack ide konvertovan
## oblik, procjena moze biti daleko od istine — a Feature 1 je besplatni mamak
## koji mora biti tacan.
##
## Pokretanje:
##   godot --headless --path <projekat> -s addons/web_export_doctor/tools/run_estimate_test.gd

const OUTPUT_EXT := ["pck", "wasm", "zip"]
const META_EXT := ["import", "uid"]

func _init() -> void:
	print("=== WED test procjene vs stvarnog exporta ===")

	# 1. Procjena nad izvornim res:// (isto sto radi dugme u docku).
	var assets := _scan("res://")
	var src_total := 0
	for a in assets:
		src_total += int(a["bytes"])
	print("- izvornih fajlova: %d, ukupno %s" % [assets.size(), WEDConfig.format_bytes(src_total)])
	for a in assets:
		print("    %-28s %s" % [str(a["path"]).trim_prefix("res://"), WEDConfig.format_bytes(int(a["bytes"]))])

	var predicted := WEDLimits.evaluate(WEDLimits.predict_outputs(src_total), true)
	var predicted_pck := 0
	for o in predicted["outputs"]:
		if str(o["name"]).begins_with("index.pck"):
			predicted_pck = int(o["bytes"])

	# 2. Stvarni export.
	var project_path := ProjectSettings.globalize_path("res://")

	# Bez Web preseta export ne moze proci, a gola poruka "export nije uspio"
	# izgleda kao kvar alata umjesto kao nedostajuce podesavanje projekta.
	var preset := _find_web_preset(project_path)
	if preset.is_empty():
		print("")
		print("  PRESKOCENO: projekat nema Web export preset.")
		print("  Napravi ga: Project > Export > Add > Web, pa pokreni ponovo.")
		quit(0)
		return
	print("- koristim preset: %s" % preset)

	var out_dir := project_path.path_join("build")
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("- izvozim...")
	var args := PackedStringArray([
		"--headless", "--path", project_path,
		"--export-release", preset, out_dir.path_join("index.html"),
	])
	var stdout: Array = []
	var code := OS.execute(OS.get_executable_path(), args, stdout, true)
	if code != 0:
		print("  FAIL export nije uspio (exit %d)" % code)
		quit(1)
		return

	var real_pck := _file_size(out_dir.path_join("index.pck"))
	var real_total := _dir_total(out_dir)
	print("- stvarni index.pck: %s" % WEDConfig.format_bytes(real_pck))
	print("- stvarni ukupno:    %s" % WEDConfig.format_bytes(real_total))

	# 3. Poredjenje.
	print("")
	print("procjena packa:  %s" % WEDConfig.format_bytes(predicted_pck))
	print("stvarni pack:    %s" % WEDConfig.format_bytes(real_pck))
	var diff := real_pck - predicted_pck
	var ratio := (float(real_pck) / float(predicted_pck)) if predicted_pck > 0 else 0.0
	print("razlika:         %s  (%.2fx)" % [WEDConfig.format_bytes(absi(diff)), ratio])

	# Procjena ne mora biti savrsena, ali ne smije biti obmanjujuca.
	# Granica: stvarni pack ne smije biti vise od 1.5x veci od procjene, jer bi
	# tada projekat blizu limita dobio PASS a stvarno pao.
	var ok := ratio <= 1.5 and ratio >= 0.5
	print("")
	if ok:
		print("REZULTAT: procjena je upotrebljiva (unutar 0.5x-1.5x)")
	else:
		print("REZULTAT: PROCJENA JE OBMANJUJUCA — treba korekcija za importovane resurse")
	quit(0 if ok else 1)

## Nadji Web preset po imenu. Ne pretpostavljaj da se zove bas "Web" —
## korisnik ga moze nazvati kako hoce.
func _find_web_preset(project_path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(project_path.path_join("export_presets.cfg")) != OK:
		return ""
	for section in cfg.get_sections():
		if section.ends_with(".options") or section == "runnable_presets":
			continue
		if str(cfg.get_value(section, "platform", "")) == "Web":
			return str(cfg.get_value(section, "name", ""))
	return ""

func _file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n

func _dir_total(p: String) -> int:
	var total := 0
	var da := DirAccess.open(p)
	if da == null:
		return 0
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not da.current_is_dir():
			total += _file_size(p.path_join(n))
		n = da.get_next()
	da.list_dir_end()
	return total

func _scan(dir_path: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not n.begins_with("."):
			var full := dir_path.path_join(n)
			if da.current_is_dir():
				if n != "addons" and not n.begins_with("build"):
					out.append_array(_scan(full))
			else:
				var ext := n.get_extension().to_lower()
				if not META_EXT.has(ext) and not OUTPUT_EXT.has(ext):
					# Isto mjerenje koje koristi i dock: konvertovani oblik.
					out.append({"path": full, "bytes": WEDLimits.measure_packed_size(full)})
		n = da.get_next()
	da.list_dir_end()
	return out
