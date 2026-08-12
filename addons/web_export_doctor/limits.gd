@tool
class_name WEDLimits
extends RefCounted

## Cista logika ocjenjivanja — bez editora, bez UI-ja, bez fajl sistema.
## Zato se moze testirati headless skriptom (vidi tools/run_tests.gd).
##
## VAZNO — sta se zapravo mjeri:
## itch.io ne vidi fajlove UNUTAR .pck arhive. On raspakuje zip i vidi
## index.pck, index.wasm, index.js, index.html. Sve assets su u JEDNOM fajlu.
## Zato se pravilo od 200 MB primjenjuje na IZLAZNE fajlove exporta, a ne na
## pojedinacne assets. Projekat s 300 assets po 10 MB ima najveci asset od
## 10 MB, ali index.pck od 3 GB — i itch.io ga odbija.

enum Verdict { PASS, WARN, FAIL }

## Jedan izlazni fajl exporta (index.pck, index.wasm, ...).
static func make_output(name: String, bytes: int) -> Dictionary:
	return {"name": name, "bytes": bytes}

## Ocijeni izlazne fajlove prema oba itch.io pravila.
##
## outputs: Array[Dictionary] s kljucevima "name" i "bytes".
## estimated: true ako su brojevi procijenjeni (nema jos stvarnih fajlova).
##
## Vraca Dictionary s dva NEZAVISNA rezultata, kako prompt trazi:
##   file_rule  — najveci pojedinacni izlazni fajl vs 200 MB
##   total_rule — suma svih izlaznih fajlova vs 500 MB
static func evaluate(outputs: Array, estimated: bool = false) -> Dictionary:
	var total_bytes := 0
	var largest_name := ""
	var largest_bytes := 0
	var offenders: Array[Dictionary] = []

	for out in outputs:
		var b: int = out.get("bytes", 0)
		total_bytes += b
		if b > largest_bytes:
			largest_bytes = b
			largest_name = out.get("name", "?")
		if b > WEDConfig.ITCH_MAX_FILE_BYTES:
			offenders.append(out)

	var file_pass := largest_bytes <= WEDConfig.ITCH_MAX_FILE_BYTES
	var total_pass := total_bytes <= WEDConfig.ITCH_MAX_TOTAL_BYTES

	var file_rule := {
		"passed": file_pass,
		"verdict": Verdict.PASS if file_pass else Verdict.FAIL,
		"largest_name": largest_name,
		"largest_bytes": largest_bytes,
		"limit_bytes": WEDConfig.ITCH_MAX_FILE_BYTES,
		"offenders": offenders,
		"message": _file_rule_message(file_pass, largest_name, largest_bytes, offenders),
	}

	var total_rule := {
		"passed": total_pass,
		"verdict": Verdict.PASS if total_pass else Verdict.FAIL,
		"total_bytes": total_bytes,
		"limit_bytes": WEDConfig.ITCH_MAX_TOTAL_BYTES,
		"message": _total_rule_message(total_pass, total_bytes),
	}

	return {
		"file_rule": file_rule,
		"total_rule": total_rule,
		"passed": file_pass and total_pass,
		"total_bytes": total_bytes,
		"largest_bytes": largest_bytes,
		"estimated": estimated,
		"outputs": outputs,
	}

static func _file_rule_message(passed: bool, name: String, bytes: int, offenders: Array) -> String:
	if passed:
		return "Largest file %s (%s) is under 200 MB." % [name, WEDConfig.format_bytes(bytes)]
	if offenders.size() > 1:
		return "%d output files exceed 200 MB — largest is %s (%s)." % [
			offenders.size(), name, WEDConfig.format_bytes(bytes)
		]
	return "%s is %s — over the 200 MB per-file limit." % [name, WEDConfig.format_bytes(bytes)]

static func _total_rule_message(passed: bool, total: int) -> String:
	if passed:
		return "Total %s is under 500 MB." % WEDConfig.format_bytes(total)
	return "Total %s — over the 500 MB limit." % WEDConfig.format_bytes(total)

## Izmjeri koliko ce asset ZAUZETI U PACKU, ne koliko zauzima na disku.
##
## Godot importovane resurse konvertuje, i u pack ide konvertovani oblik:
##   robot_walk.wav   1.52 MB  ->  .sample  0.31 MB   (5x manje)
##   scene.tscn       tekst    ->  .scn     binarno
## Mjerenje izvornih fajlova zato daje grubo pogresnu sliku. Na zvanicnom Godot
## demo projektu izvorni zbir je 3.1 MB, a stvarni pack 1.2 MB — procjena bi
## precijenila 2.6x i poslala korisnika da dijeli projekat bez potrebe.
##
## Putanja do konvertovanog oblika stoji u pratecem .import fajlu, pod
## dest_files. Ako .import ne postoji (skripte, .tres, obicni fajlovi), resurs
## ide u pack kakav jest, pa se mjeri izvorni fajl.
static func measure_packed_size(res_path: String) -> int:
	var import_path := res_path + ".import"
	if FileAccess.file_exists(import_path):
		var total := 0
		var found := false
		for dest in _read_dest_files(import_path):
			var n := _file_size(dest)
			if n > 0:
				total += n
				found = true
		if found:
			return total
		# .import postoji ali resurs jos nije importovan — vrati izvorni kao
		# priblizno, radije nego nulu.
	return _file_size(res_path)

static func _read_dest_files(import_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(import_path, FileAccess.READ)
	if f == null:
		return out
	# ConfigFile ne parsira .import pouzdano zbog [remap]/[deps] strukture,
	# pa se dest_files cita direktno.
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if not line.begins_with("dest_files="):
			continue
		var raw := line.substr("dest_files=".length()).strip_edges()
		raw = raw.trim_prefix("[").trim_suffix("]")
		for part in raw.split(","):
			var p := part.strip_edges().trim_prefix("\"").trim_suffix("\"")
			# U praksi je uvijek res://, ali ne vezuj se za tu shemu — testovi
			# pisu u user://, a i Godot bi mogao promijeniti konvenciju.
			if p.contains("://"):
				out.append(p)
		break
	f.close()
	return out

static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n

## Nadji assets koji su zapravo izlaz nekog ranijeg exporta.
##
## Ako je izlazni folder unutar projekta (npr. res://build/), "all_resources"
## pakuje i prethodni build u novi paket. Posljedica: pack raste pri svakom
## exportu, a uzrok nije ocit jer u FileSystem panelu to izgleda kao obican
## folder. Vraca listu takvih fajlova.
static func find_recycled_build_output(assets: Array, output_dirs: PackedStringArray) -> Array:
	var hits: Array = []
	for a in assets:
		var p: String = a.get("path", "")
		for d in output_dirs:
			if d.is_empty():
				continue
			if p.begins_with(d.trim_suffix("/") + "/"):
				hits.append(a)
				break
	return hits

## Boja reda u dijagnostickoj tabeli: koliko ovaj asset doprinosi problemu.
## Ovo NIJE itch.io pravilo — pojedinacni asset itch.io nikad ne vidi.
static func asset_verdict(bytes: int, total_bytes: int) -> Verdict:
	if bytes > WEDConfig.SPLIT_TARGET_BYTES:
		return Verdict.FAIL
	if total_bytes > 0 and float(bytes) / float(total_bytes) >= 0.25:
		return Verdict.WARN
	return Verdict.PASS

## Predvidi izlazne fajlove iz zbira assets, kada stvarnih fajlova jos nema.
## Koristi se za dugme "Scan without exporting" i kao fallback u _export_end().
static func predict_outputs(asset_bytes_total: int) -> Array:
	return [
		make_output("index.pck (estimate)", asset_bytes_total),
		make_output("web runtime (wasm+js+html, estimate)", WEDConfig.WEB_RUNTIME_OVERHEAD_BYTES),
	]

## Grupisi assets u pakete tako da svaki ostane ispod SPLIT_TARGET_BYTES.
##
## Grupise po folderima jer .pck mora sadrzavati cijele foldere da bi
## include_filter bio smislen. Dubina je ADAPTIVNA: krece od prvog nivoa, a
## folder koji sam po sebi prelazi cilj se razlaze na svoje podfoldere.
## (Bez toga bi projekat gdje je sve pod res://assets/ dao jednu grupu koja
## prelazi limit — sto je upravo slucaj u test projektu.)
##
## Folder koji je prevelik a nema dublju strukturu vraca se kao vlastita grupa
## oznacena s oversized=true — takav se ne moze automatski podijeliti i mora ga
## korisnik rijesiti rucno (kompresija, atlas, ili rucna podjela foldera).
static func group_by_folder(assets: Array) -> Array:
	# Fajlovi u rootu projekta (project.godot, main.tscn, ...) ostaju u glavnom
	# .pck — ne idu u split pakete. Bez ovoga bi njihov "folder" bio prazan
	# string, sto bi dalo exclude pattern "/*" i krhko ponasanje.
	var packable: Array = []
	for a in assets:
		if _folder_at_depth(a.get("path", ""), 1) != "":
			packable.append(a)

	var buckets := _bucket_at_depth(packable, 1)

	# First-fit descending: spakuj foldere u sto manje grupa.
	var groups: Array = []
	for f in buckets:
		if f["bytes"] > WEDConfig.SPLIT_TARGET_BYTES:
			groups.append({
				"folders": [f["folder"]],
				"bytes": f["bytes"],
				"files": f["files"],
				"oversized": true,
			})
			continue
		var placed := false
		for g in groups:
			if g.get("oversized", false):
				continue
			if g["bytes"] + f["bytes"] <= WEDConfig.SPLIT_TARGET_BYTES:
				g["folders"].append(f["folder"])
				g["bytes"] += f["bytes"]
				g["files"].append_array(f["files"])
				placed = true
				break
		if not placed:
			groups.append({
				"folders": [f["folder"]],
				"bytes": f["bytes"],
				"files": f["files"],
				"oversized": false,
			})

	return groups

## Grupisi na datoj dubini; svaku grupu koja prelazi cilj probaj razloziti dublje.
static func _bucket_at_depth(assets: Array, depth: int) -> Array:
	var by_folder: Dictionary = {}
	for a in assets:
		var folder := _folder_at_depth(a.get("path", ""), depth)
		if not by_folder.has(folder):
			by_folder[folder] = {"folder": folder, "bytes": 0, "files": []}
		by_folder[folder]["bytes"] += int(a.get("bytes", 0))
		by_folder[folder]["files"].append(a)

	var out: Array = []
	for f in by_folder.values():
		if f["bytes"] > WEDConfig.SPLIT_TARGET_BYTES and _has_deeper(f["files"], depth):
			out.append_array(_bucket_at_depth(f["files"], depth + 1))
		else:
			out.append(f)

	out.sort_custom(func(x, y): return x["bytes"] > y["bytes"])
	return out

static func _has_deeper(assets: Array, depth: int) -> bool:
	# Ima smisla ici dublje samo ako bar dva razlicita podfoldera postoje,
	# inace bi rekurzija samo dodavala nivo bez razdvajanja.
	var seen := {}
	for a in assets:
		seen[_folder_at_depth(a.get("path", ""), depth + 1)] = true
		if seen.size() > 1:
			return true
	return false

## "res://assets/level2/chunk.dat" na dubini 2 -> "assets/level2"
## Ako putanja nema toliko nivoa, vraca najdublji dostupan folder.
static func _folder_at_depth(res_path: String, depth: int) -> String:
	var p := res_path.trim_prefix("res://")
	var parts := p.split("/")
	if parts.size() <= 1:
		return ""  # fajl u rootu projekta
	var take := mini(depth, parts.size() - 1)
	var out := ""
	for i in take:
		out += ("/" if i > 0 else "") + parts[i]
	return out
