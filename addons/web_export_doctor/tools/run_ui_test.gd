@tool
extends SceneTree

## Instancira panele i stvarno ih ubaci u stablo, da _ready() odradi izgradnju UI-ja.
## Hvata greske koje se inace vide tek kad editor ucita plugin.

var _failed := 0

func _check(label: String, actual, expected) -> void:
	if actual == expected:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s — dobio %s, ocekivao %s" % [label, str(actual), str(expected)])
		_failed += 1

func _init() -> void:
	print("=== WED UI smoke test ===")
	var failed := 0

	var host := Control.new()
	root.add_child(host)

	# Feature 1 panel — mora raditi i u Lite i u Pro.
	var rp := WEDReportPanel.new()
	host.add_child(rp)
	print("  ok   report panel instanciran, ime=%s, djece=%d" % [rp.name, rp.get_child_count()])
	if rp.get_child_count() == 0:
		print("  FAIL report panel nije izgradio UI")
		failed += 1

	# Napuni ga podacima kao da je export zavrsio.
	var report := WEDLimits.evaluate([
		WEDLimits.make_output("index.pck", 650 * 1024 * 1024),
		WEDLimits.make_output("index.wasm", 38 * 1024 * 1024),
	])
	report["assets"] = [
		{"path": "res://assets/huge/bigfile.dat", "type": "dat",
		 "bytes": 210 * 1024 * 1024, "percent": 32.3, "verdict": WEDLimits.Verdict.FAIL},
		{"path": "res://assets/level2/chunk_a.dat", "type": "dat",
		 "bytes": 160 * 1024 * 1024, "percent": 24.6, "verdict": WEDLimits.Verdict.WARN},
	]
	rp.show_report(report)
	print("  ok   show_report() prosao")

	# Brzi skan nad stvarnim res://
	rp.quick_scan()
	print("  ok   quick_scan() prosao")

	# Regresija: skan ne smije brojati vlastite izlazne artefakte. Ako u
	# projektu postoji build/ s ranijim exportom, .pck bi udvostrucio procjenu.
	var scanned: Array = rp._report.get("assets", [])
	var bad: Array = []
	for a in scanned:
		var ext := str(a["path"]).get_extension().to_lower()
		if ext in ["pck", "wasm", "zip"]:
			bad.append(a["path"])
	if bad.is_empty():
		print("  ok   skan ne broji export artefakte (%d fajlova skenirano)" % scanned.size())
	else:
		print("  FAIL skan broji export artefakte: %s" % str(bad))
		failed += 1

	# Pro paneli — samo ako postoje u ovom buildu.
	const BASE := "res://addons/web_export_doctor/"
	for entry in [["ui/split_panel.gd", "set_assets"], ["ui/webfix_panel.gd", "apply_report"]]:
		var rel: String = entry[0]
		var method: String = entry[1]
		if not ResourceLoader.exists(BASE + rel):
			print("  --   %s nije u ovom buildu (Lite)" % rel)
			continue
		var scr = load(BASE + rel)
		if scr == null:
			print("  FAIL %s se ne ucitava" % rel)
			failed += 1
			continue
		var panel = scr.new()
		host.add_child(panel)
		print("  ok   %s instanciran, ime=%s, djece=%d" % [rel, panel.name, panel.get_child_count()])
		if method == "set_assets":
			panel.set_assets(report["assets"])
		else:
			# Regresija: brzi skan NE SMIJE gasiti prikaz stanja threadova.
			# Izvjestaj bez "from_export" dolazi iz skena i mora ostaviti panel
			# da cita stanje iz preseta, umjesto da tvrdi "iskljuceni".
			var scan_report := report.duplicate()
			scan_report["thread_support"] = false
			scan_report.erase("from_export")
			panel.apply_report(scan_report)
			var after_scan: bool = panel._seen_export
			_check("skan ne prebacuje panel u post-export rezim", after_scan, false)

			var export_report := report.duplicate()
			export_report["thread_support"] = true
			export_report["from_export"] = true
			panel.apply_report(export_report)
			_check("stvarni export prebacuje panel", panel._seen_export, true)
			_check("stvarni export cita thread_support", panel._has_threads, true)
		print("  ok   %s.%s() prosao" % [rel, method])

	failed += _failed
	print("=== %s ===" % ("UI OK" if failed == 0 else "%d problema" % failed))
	quit(1 if failed > 0 else 0)
