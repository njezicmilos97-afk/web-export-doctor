@tool
extends SceneTree

## Headless testovi za cistu logiku (WEDLimits).
## Pokretanje:
##   godot --headless --path <projekat> -s addons/web_export_doctor/tools/run_tests.gd
##
## Ovo je postojalo jer se EditorExportPlugin hook NE pokrece u headless modu,
## pa se logika ocjenjivanja mora moci provjeriti odvojeno od editora.

var _passed := 0
var _failed := 0

const MB := 1024 * 1024

func _init() -> void:
	print("=== WED testovi ===")
	_test_fail_project()
	_test_pass_project()
	_test_many_small_assets_no_false_pass()
	_test_exactly_at_limit()
	_test_grouping_splits_by_folder()
	_test_grouping_flags_oversized_folder()
	_test_grouping_goes_deeper_when_needed()
	_test_scripts_load_in_this_build()
	_test_thread_detection()
	_test_no_network_in_editor_code()
	_test_popout_injection()
	_test_recycled_build_output()
	_test_packed_size_uses_imported_form()
	_test_hostile_inputs()
	_test_upgrade_url_gate()
	print("=== %d prosao, %d pao ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

## Regresija za Lite paket: iz njega su Pro fajlovi fizicki izbaceni, pa
## plugin.gd ne smije referencirati Pro klase preko class_name — inace bi
## besplatna verzija pukla pri ucitavanju.
func _test_scripts_load_in_this_build() -> void:
	print("- skripte se ucitavaju (%s build)" % ("Pro" if WEDConfig.IS_PRO else "Lite"))
	const BASE := "res://addons/web_export_doctor/"
	var always := ["plugin.gd", "config.gd", "limits.gd", "export_plugin.gd", "ui/report_panel.gd"]
	for rel in always:
		_check("ucitava %s" % rel, load(BASE + rel) != null, true)

	var pro := ["auto_split.gd", "web_fixes.gd", "ui/split_panel.gd", "ui/webfix_panel.gd"]
	for rel in pro:
		var present := ResourceLoader.exists(BASE + rel)
		_check("Pro fajl %s %s" % [rel, "prisutan" if WEDConfig.IS_PRO else "izbacen"],
			present, WEDConfig.IS_PRO)
		if present:
			_check("ucitava %s" % rel, load(BASE + rel) != null, true)

## Feature 3 se smije oglasiti SAMO kad je Thread Support stvarno ukljucen.
## Lazni pozitiv bi poslao korisnika da mijenja podesavanja na itch.io bez
## razloga; lazni negativ bi pustio build koji tamo nece raditi.
func _test_thread_detection() -> void:
	# Pro klase se ucitavaju dinamicki, ne preko class_name: u Lite paketu ti
	# fajlovi ne postoje, a referenca preko class_name je PARSE greska — cijela
	# test skripta se ne bi ni ucitala.
	var WebFixes = _load_pro("web_fixes.gd")
	if WebFixes == null:
		print("- thread detekcija: preskoceno (Lite build)")
		return
	print("- thread detekcija")

	var real: Dictionary = WebFixes.read_thread_support("res://")
	print("    aktivni preset: found=%s enabled=%s ime=%s" % [
		real["found"], real["enabled"], real["preset"]])

	# Checklist se mijenja po stanju — i to je jedina razlika koju korisnik vidi.
	var on: String = WebFixes.build_itch_checklist(true)
	var off: String = WebFixes.build_itch_checklist(false)
	# Mjeri se trazi li se RADNJA, ne spominje li se pojam: tekst bez threadova
	# smije reci "SharedArrayBuffer nije potreban", ali ne smije slati korisnika
	# da mijenja podesavanja na itch.io.
	_check("s threadovima salje na Embed Options", on.contains("Embed Options"), true)
	_check("bez threadova NE salje na Embed Options", off.contains("Embed Options"), false)
	_check("s threadovima spominje Firefox", on.contains("Firefox"), true)
	_check("bez threadova ne panici oko Firefoxa", off.contains("Firefox"), false)

	# Provjeri da citanje iz cfg-a razlikuje ukljuceno od iskljucenog.
	var tmp := "user://wed_thread_probe"
	DirAccess.make_dir_recursive_absolute(tmp)
	for want in [true, false]:
		var cfg := ConfigFile.new()
		cfg.set_value("preset.0", "name", "Web")
		cfg.set_value("preset.0", "platform", "Web")
		cfg.set_value("preset.0", "runnable", true)
		cfg.set_value("preset.0.options", "variant/thread_support", want)
		cfg.save(tmp.path_join("export_presets.cfg"))
		var got: Dictionary = WebFixes.read_thread_support(tmp)
		_check("cfg thread_support=%s procitan" % want, got["enabled"], want)

	# Sukob split + threadovi mora biti prijavljen, i samo kad postoji oboje.
	_check("split + threadovi = sukob", WebFixes.split_conflicts_with_threads(true, 2), true)
	_check("split bez threadova = ok", WebFixes.split_conflicts_with_threads(false, 2), false)
	_check("threadovi bez splita = ok", WebFixes.split_conflicts_with_threads(true, 0), false)
	var warn: String = WebFixes.build_split_thread_warning()
	_check("upozorenje nudi izlaz", warn.contains("disable Thread Support"), true)

	# Vise Web preseta je cest slucaj ("Web" + "Web Debug"). Mjerodavan je
	# runnable — to je build koji se stvarno salje na itch.io.
	var multi := "user://wed_thread_multi"
	DirAccess.make_dir_recursive_absolute(multi)
	var c3 := ConfigFile.new()
	c3.set_value("preset.0", "name", "Web Debug")
	c3.set_value("preset.0", "platform", "Web")
	c3.set_value("preset.0", "runnable", false)
	c3.set_value("preset.0.options", "variant/thread_support", false)
	c3.set_value("preset.1", "name", "Web Release")
	c3.set_value("preset.1", "platform", "Web")
	c3.set_value("preset.1", "runnable", true)
	c3.set_value("preset.1.options", "variant/thread_support", true)
	c3.save(multi.path_join("export_presets.cfg"))
	var picked: Dictionary = WebFixes.read_thread_support(multi)
	_check("bira runnable preset, ne prvi po redu", picked["preset"], "Web Release")
	_check("cita threadove iz runnable preseta", picked["enabled"], true)

	# Isto, ali runnable je zapisan u [runnable_presets] sekciji (Godot to radi
	# kad sam prepise cfg) — mora dati isti rezultat.
	var moved := "user://wed_thread_moved"
	DirAccess.make_dir_recursive_absolute(moved)
	var c4 := ConfigFile.new()
	c4.set_value("runnable_presets", "Web Release", "Web Release")
	c4.set_value("preset.0", "name", "Web Debug")
	c4.set_value("preset.0", "platform", "Web")
	c4.set_value("preset.0.options", "variant/thread_support", false)
	c4.set_value("preset.1", "name", "Web Release")
	c4.set_value("preset.1", "platform", "Web")
	c4.set_value("preset.1.options", "variant/thread_support", true)
	c4.save(moved.path_join("export_presets.cfg"))
	var moved_pick: Dictionary = WebFixes.read_thread_support(moved)
	_check("prepoznaje runnable iz [runnable_presets]", moved_pick["preset"], "Web Release")

	# Projekat bez Web preseta ne smije nista tvrditi.
	var empty := "user://wed_thread_empty"
	DirAccess.make_dir_recursive_absolute(empty)
	var c2 := ConfigFile.new()
	c2.set_value("preset.0", "name", "Windows")
	c2.set_value("preset.0", "platform", "Windows Desktop")
	c2.set_value("preset.0", "runnable", true)
	c2.save(empty.path_join("export_presets.cfg"))
	var none: Dictionary = WebFixes.read_thread_support(empty)
	_check("bez Web preseta nema tvrdnje", none["found"], false)

## Addon ne smije imati mrezu, telemetriju ni licencni server.
## Jedini dozvoljeni izuzetak je templates/ — kod koji se GENERISE u korisnikovu
## igru i tamo skida .pck sa korisnikovog VLASTITOG servera. Taj kod se nikad ne
## izvrsava u editoru.
##
## Ovo je jaci dokaz od "testirano s iskljucenim internetom": ne moze proci ni
## slucajno dodavanje mrezne funkcije u buducnosti.
func _test_no_network_in_editor_code() -> void:
	print("- bez mreze u editorskom kodu")
	var banned := [
		"HTTPRequest", "HTTPClient", "TCPServer", "StreamPeerTCP", "StreamPeerTLS",  # net-ok
		"PacketPeerUDP", "UDPServer", "WebSocketPeer", "ENetConnection",  # net-ok
		"OS.shell_open", "IP.resolve_hostname",  # net-ok
	]
	var editor_files := _gd_files("res://addons/web_export_doctor", "templates")
	_check("ima sta provjeriti", editor_files.size() > 0, true)

	var hits: Array[String] = []
	for path in editor_files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		for term in banned:
			for line in src.split("\n"):
				var t := line.strip_edges()
				# Komentari, i linije izricito oznacene s "# net-ok" (ovaj test
				# mora smjeti spomenuti pojmove koje trazi).
				if t.begins_with("#") or t.contains("# net-ok"):
					continue
				if t.contains(term):
					hits.append("%s: %s" % [path.get_file(), term])
					break
	if hits.is_empty():
		print("    %d editorskih skripti, nijedan mrezni poziv" % editor_files.size())
	_check("nema mreznih poziva u editoru", hits, [] as Array[String])

	# Runtime template SMIJE koristiti mrezu — i to je jedino takvo mjesto.
	var loader := "res://addons/web_export_doctor/templates/pack_loader.gd"
	if ResourceLoader.exists(loader):
		var f := FileAccess.open(loader, FileAccess.READ)
		var has := f.get_as_text().contains(banned[0])  # net-ok
		f.close()
		_check("runtime template smije skidati pakete", has, true)

## Izlazni folder unutar projekta -> prethodni build zavrsi u novom packu.
## Ovo se u praksi desilo u test projektu, pa mora ostati pokriveno testom.
func _test_recycled_build_output() -> void:
	print("- izlaz ranijeg builda u packu")
	var assets := [
		{"path": "res://assets/huge/bigfile.dat", "bytes": 210},
		{"path": "res://build/index.png", "bytes": 5},
		{"path": "res://build/index.icon.png", "bytes": 3},
	]
	var dirs := PackedStringArray(["res://build"])
	var hits := WEDLimits.find_recycled_build_output(assets, dirs)
	_check("prepoznaje fajlove iz izlaznog foldera", hits.size(), 2)

	# Bez izlaznog foldera u projektu nema sta prijaviti.
	_check("cist projekat ne prijavljuje nista",
		WEDLimits.find_recycled_build_output(assets, PackedStringArray()).size(), 0)

	# Slican naziv ne smije dati lazni pozitiv ("buildings" nije "build").
	var tricky := [{"path": "res://buildings/tower.dat", "bytes": 9}]
	_check("slican naziv foldera nije lazni pozitiv",
		WEDLimits.find_recycled_build_output(tricky, dirs).size(), 0)

## Mjeriti izvorni fajl umjesto importovanog daje grubo pogresnu procjenu:
## na zvanicnom Godot demo projektu 3.1 MB izvorno vs 1.2 MB u packu (0.38x).
## Nakon ispravke 0.93x. Ovaj test cuva to ponasanje.
func _test_packed_size_uses_imported_form() -> void:
	print("- mjerenje importovanog oblika")
	var base := "user://wed_import_probe"
	DirAccess.make_dir_recursive_absolute(base)
	DirAccess.make_dir_recursive_absolute(base + "/imported")

	# Izvorni fajl 4000 B, importovani oblik 500 B.
	var src := base + "/sound.wav"
	var dst := base + "/imported/sound-abc.sample"
	_write_bytes(src, 4000)
	_write_bytes(dst, 500)

	var f := FileAccess.open(src + ".import", FileAccess.WRITE)
	f.store_string("[remap]\n\nimporter=\"wav\"\npath=\"%s\"\n\n[deps]\n\ndest_files=[\"%s\"]\n" % [dst, dst])
	f.close()

	_check("mjeri importovani oblik, ne izvorni", WEDLimits.measure_packed_size(src), 500)

	# Fajl bez .import ide u pack kakav jest.
	var plain := base + "/data.bin"
	_write_bytes(plain, 1234)
	_check("fajl bez .import mjeri se kakav jest", WEDLimits.measure_packed_size(plain), 1234)

	# .import koji pokazuje na nepostojeci fajl (jos nije importovano) ne smije
	# dati nulu — bolje priblizno nego da asset nestane iz izvjestaja.
	var stale := base + "/stale.wav"
	_write_bytes(stale, 777)
	var g := FileAccess.open(stale + ".import", FileAccess.WRITE)
	g.store_string("[deps]\n\ndest_files=[\"user://wed_import_probe/imported/nema-me.sample\"]\n")
	g.close()
	_check("neimportovan resurs ne nestaje", WEDLimits.measure_packed_size(stale), 777)

func _write_bytes(path: String, n: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var buf := PackedByteArray()
	buf.resize(n)
	f.store_buffer(buf)
	f.close()

## Ulazi koji se u praksi desavaju, a lako ruse alat: prazan projekat,
## nula bajtova, negativne velicine, ogromni brojevi, cudni nazivi.
func _test_hostile_inputs() -> void:
	print("- neocekivani ulazi")

	# Prazan projekat: nema fajlova, nema izlaza. Ne smije dijeliti nulom.
	var empty := WEDLimits.evaluate([])
	_check("prazan izvjestaj ne puca", empty["total_bytes"], 0)
	_check("prazan izvjestaj prolazi", empty["passed"], true)
	_check("grupisanje praznog projekta", WEDLimits.group_by_folder([]).size(), 0)

	# Fajl od 0 bajtova (cest kod placeholder assetsa).
	var zero := WEDLimits.group_by_folder([{"path": "res://a/empty.dat", "bytes": 0}])
	_check("nulti fajl daje jednu grupu", zero.size(), 1)
	_check("nulta grupa nije oversized", zero[0].get("oversized", true), false)

	# Negativna velicina ne smije ispisati "-0.0 MB".
	_check("negativna velicina se ne prikazuje kao broj", WEDConfig.format_bytes(-1), "?")

	# Vrlo velik projekat — 8 GB mora dati GB prikaz i pasti oba pravila.
	var huge := WEDLimits.evaluate([WEDLimits.make_output("index.pck", 8 * 1024 * 1024 * 1024)])
	_check("8 GB pada pravilo po fajlu", huge["file_rule"]["passed"], false)
	_check("8 GB pada ukupno pravilo", huge["total_rule"]["passed"], false)
	_check("velike brojke se prikazuju u GB", WEDConfig.format_bytes(8 * 1024 * 1024 * 1024), "8.00 GB")

	# Procenat kad je ukupno nula — dijeljenje nulom u tabeli.
	_check("verdikt pri nultom zbiru", WEDLimits.asset_verdict(0, 0), WEDLimits.Verdict.PASS)

	# Prazan projekat: project.godot je jedini fajl, dakle 100% zbira, a 0.0 MB.
	# Bojiti ga znaci upozoravati ni na sta. Vidjeno uzivo u praznom projektu.
	_check("sitan fajl na 100% ne dobija boju",
		WEDLimits.asset_verdict(1200, 1200), WEDLimits.Verdict.PASS)
	# Ali prag ne smije ugasiti upozorenje tamo gdje je zasluzeno.
	_check("krupan fajl na 100% i dalje dobija boju",
		WEDLimits.asset_verdict(50 * 1024 * 1024, 50 * 1024 * 1024), WEDLimits.Verdict.WARN)
	_check("fajl preko cilja za split je uvijek FAIL",
		WEDLimits.asset_verdict(190 * 1024 * 1024, 190 * 1024 * 1024), WEDLimits.Verdict.FAIL)

	# Putanja bez foldera (fajl u rootu) ne smije zavrsiti u split grupi.
	var root_only := WEDLimits.group_by_folder([{"path": "res://main.tscn", "bytes": 100}])
	_check("fajl u rootu ne pravi grupu", root_only.size(), 0)

	# Nazivi s razmacima, tackama i dijakriticima.
	var odd := WEDLimits.group_by_folder([
		{"path": "res://moj folder/a.dat", "bytes": 10},
		{"path": "res://moj folder/b.dat", "bytes": 10},
		{"path": "res://sound.fx/c.dat", "bytes": 10},
		{"path": "res://ćšž/d.dat", "bytes": 10},
	])
	var names: Array = []
	for g in odd:
		names.append_array(g["folders"])
	_check("folder s razmakom prepoznat", names.has("moj folder"), true)
	_check("folder s tackom prepoznat", names.has("sound.fx"), true)
	_check("folder s dijakriticima prepoznat", names.has("ćšž"), true)

## Lite prikazuje "Upgrade to Pro" link samo ako Pro stranica stvarno postoji.
## Dok je URL placeholder, dugme bi vodilo na naslovnicu itch.io — gore nego
## nikakvo dugme, jer izgleda kao pokvaren link.
func _test_upgrade_url_gate() -> void:
	print("- gate za Upgrade to Pro link")
	print("    trenutni URL: %s" % WEDConfig.UPGRADE_URL)
	print("    link se prikazuje: %s" % WEDConfig.has_upgrade_url())
	# Placeholder i prazna vrijednost ne smiju proci kao prava adresa.
	_check("placeholder se ne racuna kao adresa",
		WEDConfig.UPGRADE_URL == "https://itch.io/" and not WEDConfig.has_upgrade_url()
		or WEDConfig.UPGRADE_URL != "https://itch.io/",
		true)

## Ucitaj Pro skriptu ako postoji u ovom paketu, inace null.
## Referenca preko class_name ovdje NE SMIJE: u Lite paketu bi bila parse greska
## i cijela test skripta se ne bi ucitala.
func _load_pro(rel: String):
	var path := "res://addons/web_export_doctor/" + rel
	if not ResourceLoader.exists(path):
		return null
	return load(path)

func _gd_files(dir_path: String, skip_dir: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not n.begins_with("."):
			var full := dir_path.path_join(n)
			if da.current_is_dir():
				if n != skip_dir:
					out.append_array(_gd_files(full, skip_dir))
			elif n.ends_with(".gd"):
				out.append(full)
		n = da.get_next()
	da.list_dir_end()
	return out

## Firefox zaobilaznica: dugme koje otvara igru izvan itch.io iframe-a.
func _test_popout_injection() -> void:
	var WebFixes = _load_pro("web_fixes.gd")
	if WebFixes == null:
		return
	print("- popout dugme u index.html")
	var tmp := "user://wed_popout_test.html"
	var original := "<html><head><title>t</title></head><body><canvas id=\"c\"></canvas></body></html>"

	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(original)
	f.close()

	_check("ubacivanje uspjelo", WebFixes.inject_popout_button(tmp), OK)

	var r := FileAccess.open(tmp, FileAccess.READ)
	var html := r.get_as_text()
	r.close()

	_check("dugme dodato", html.contains("wed-popout"), true)
	_check("canvas ocuvan", html.contains("<canvas id=\"c\">"), true)
	_check("ubaceno prije </body>", html.find("wed-popout") < html.rfind("</body>"), true)
	_check("otvara novi tab", html.contains("window.open"), true)
	# Bez ovoga bi se dugme prikazivalo i van iframe-a, gdje nema svrhe.
	_check("prikazuje se samo u iframe-u", html.contains("window.self===window.top"), true)

	# Drugi poziv ne smije duplirati dugme.
	_check("drugi poziv ne duplira", WebFixes.inject_popout_button(tmp), OK)
	var r2 := FileAccess.open(tmp, FileAccess.READ)
	var html2 := r2.get_as_text()
	r2.close()
	_check("i dalje samo jedno dugme", html2.count("id=\"wed-popout\""), 1)

	# Fajl koji ne postoji mora dati gresku, ne tihi uspjeh.
	_check("nepostojeci fajl daje gresku",
		WebFixes.inject_popout_button("user://nema-me.html") != OK, true)

func _check(label: String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FAIL %s — dobio %s, ocekivao %s" % [label, str(actual), str(expected)])

## Stvarne izmjerene vrijednosti iz test-fail projekta.
func _test_fail_project() -> void:
	print("- FAIL projekat (index.pck 650 MB + wasm 37.7 MB)")
	var outputs := [
		WEDLimits.make_output("index.pck", 650 * MB),
		WEDLimits.make_output("index.wasm", int(37.7 * MB)),
		WEDLimits.make_output("index.js", int(0.27 * MB)),
	]
	var r := WEDLimits.evaluate(outputs)
	_check("pravilo 200 MB pada", r["file_rule"]["passed"], false)
	_check("pravilo 500 MB pada", r["total_rule"]["passed"], false)
	_check("ukupni rezultat pada", r["passed"], false)
	_check("krivac je index.pck", r["file_rule"]["largest_name"], "index.pck")

## Stvarne izmjerene vrijednosti iz test-pass projekta.
func _test_pass_project() -> void:
	print("- PASS projekat (index.pck 70 MB + wasm 37.7 MB)")
	var outputs := [
		WEDLimits.make_output("index.pck", 70 * MB),
		WEDLimits.make_output("index.wasm", int(37.7 * MB)),
	]
	var r := WEDLimits.evaluate(outputs)
	_check("pravilo 200 MB prolazi", r["file_rule"]["passed"], true)
	_check("pravilo 500 MB prolazi", r["total_rule"]["passed"], true)
	_check("ukupni rezultat prolazi", r["passed"], true)

## Regresija: ovo je greska zbog koje alat ne bi vrijedio nista.
## 300 assets po 10 MB — najveci asset je 10 MB, ali pack je 3 GB.
## Mjerenje po assetu bi javilo PASS, a itch.io odbija upload.
func _test_many_small_assets_no_false_pass() -> void:
	print("- 300 assets po 10 MB (zamka laznog PASS-a)")
	var asset_total := 300 * 10 * MB
	var outputs := WEDLimits.predict_outputs(asset_total)
	var r := WEDLimits.evaluate(outputs, true)
	_check("pravilo 200 MB pada (pack je 3 GB)", r["file_rule"]["passed"], false)
	_check("pravilo 500 MB pada", r["total_rule"]["passed"], false)

func _test_exactly_at_limit() -> void:
	print("- granicni slucajevi")
	var at := WEDLimits.evaluate([WEDLimits.make_output("index.pck", 200 * MB)])
	_check("tacno 200 MB prolazi", at["file_rule"]["passed"], true)
	var over := WEDLimits.evaluate([WEDLimits.make_output("index.pck", 200 * MB + 1)])
	_check("200 MB + 1 bajt pada", over["file_rule"]["passed"], false)
	var tot := WEDLimits.evaluate([WEDLimits.make_output("a.pck", 500 * MB)])
	_check("tacno 500 MB ukupno prolazi", tot["total_rule"]["passed"], true)

func _test_grouping_splits_by_folder() -> void:
	print("- grupisanje po folderu")
	var assets := [
		{"path": "res://levels/level1/a.dat", "bytes": 100 * MB},
		{"path": "res://levels/level1/b.dat", "bytes": 60 * MB},
		{"path": "res://audio/music.ogg", "bytes": 50 * MB},
		{"path": "res://ui/atlas.png", "bytes": 10 * MB},
	]
	var groups := WEDLimits.group_by_folder(assets)
	var total := 0
	for g in groups:
		total += int(g["bytes"])
		_check("grupa %s ispod cilja" % str(g["folders"]), int(g["bytes"]) <= WEDConfig.SPLIT_TARGET_BYTES, true)
	_check("nista nije izgubljeno", total, 220 * MB)

## Folder koji sam po sebi prelazi cilj ne moze se automatski podijeliti —
## mora biti oznacen, ne tiho spakovan u pack koji ce pasti.
func _test_grouping_flags_oversized_folder() -> void:
	print("- folder veci od cilja")
	var assets := [
		{"path": "res://huge/bigfile.dat", "bytes": 210 * MB},
		{"path": "res://ui/atlas.png", "bytes": 10 * MB},
	]
	var groups := WEDLimits.group_by_folder(assets)
	var oversized := 0
	for g in groups:
		if g.get("oversized", false):
			oversized += 1
	_check("jedan folder oznacen kao prevelik", oversized, 1)

## Regresija: u test-fail projektu je SVE pod res://assets/. Grupisanje samo po
## prvom nivou bi dalo jednu grupu od 650 MB — beskorisno. Mora ici dublje.
func _test_grouping_goes_deeper_when_needed() -> void:
	print("- adaptivna dubina (sve pod res://assets/)")
	var assets := [
		{"path": "res://assets/huge/bigfile.dat", "bytes": 210 * MB},
		{"path": "res://assets/level2/chunk_a.dat", "bytes": 160 * MB},
		{"path": "res://assets/level2/chunk_b.dat", "bytes": 160 * MB},
		{"path": "res://assets/level3/chunk_c.dat", "bytes": 120 * MB},
	]
	var groups := WEDLimits.group_by_folder(assets)
	_check("nije jedna grupa od svega", groups.size() > 1, true)
	var total := 0
	var oversized := 0
	for g in groups:
		total += int(g["bytes"])
		if g.get("oversized", false):
			oversized += 1
		else:
			_check("grupa %s ispod cilja" % str(g["folders"]),
				int(g["bytes"]) <= WEDConfig.SPLIT_TARGET_BYTES, true)
	_check("nista nije izgubljeno", total, 650 * MB)
	# assets/huge (210 MB) i assets/level2 (320 MB) nemaju dublju strukturu
	# koja bi ih razdvojila, pa moraju biti prijavljeni kao preveliki.
	_check("preveliki folderi su oznaceni", oversized >= 1, true)
