@tool
class_name WEDConfig
extends RefCounted

## Build flag. Packaging skripta ga prepisuje: false za Lite, true za Pro.
const IS_PRO: bool = false

const VERSION: String = "1.0.0"

## itch.io ogranicenja za HTML5 upload.
## Nijedan raspakovani fajl > 200 MB; ukupno raspakovano > 500 MB.
const ITCH_MAX_FILE_BYTES: int = 200 * 1024 * 1024
const ITCH_MAX_TOTAL_BYTES: int = 500 * 1024 * 1024

## Ciljna gornja granica po split paketu â€” margina ispod 200 MB pravila.
const SPLIT_TARGET_BYTES: int = 180 * 1024 * 1024

## Prakticna granica za paket koji se ucitava U IGRI na webu.
## itch.io dozvoljava 200 MB po fajlu, ali to je granica UPLOADA, ne ucitavanja:
## na webu HTTPRequest drzi cijeli paket u memoriji pa ga prepisuje u user://
## (IndexedDB). Izmjereno na Godot 4.7.1 u Chrome-u: paket od 188 MB se nije
## ucitao ni nakon minute, dok se paketi od ~8 MB ucitavaju odmah.
## Paketi iznad ove granice i dalje prolaze upload â€” samo ih treba ucitavati
## rijetko i uz vidljiv loading ekran.
const WEB_COMFORTABLE_PACK_BYTES: int = 64 * 1024 * 1024

## Procjena fiksnog overheada web exporta (wasm + js + html + ikone) kada
## stvarni izlazni fajlovi jos ne postoje na disku. Izmjereno na Godot 4.7.1:
## index.wasm ~37.7 MB, index.js ~0.27 MB, ostalo ~0.05 MB.
const WEB_RUNTIME_OVERHEAD_BYTES: int = 40 * 1024 * 1024

## Adresa Pro stranice. Dok stoji podrazumijevana vrijednost, Lite ne prikazuje
## link nego "coming soon" â€” bolje nego dugme koje vodi na nepostojecu stranicu.
## build_package.ps1 podsjeca dok se ne postavi.
const UPGRADE_URL: String = "https://itch.io/"

## true kad je UPGRADE_URL stvarna adresa proizvoda, a ne placeholder.
static func has_upgrade_url() -> bool:
	return UPGRADE_URL != "https://itch.io/" and UPGRADE_URL.contains("itch.io/")

## Jedinica je namjerno MiB (1024*1024) iako se pise "MB" â€” jer itch.io racuna
## isto tako. Provjereno uploadom: fajl od 214.959.720 bajtova itch.io prijavljuje
## kao "205.00 MB", sto je 1024-baza. Da se koristi 1000-baza, granica bi bila
## 9.7 MB niza i alat bi javljao FAIL za buildove koje itch.io prihvata.
static func format_bytes(bytes: int) -> String:
	if bytes < 0:
		return "?"
	var mb := bytes / (1024.0 * 1024.0)
	if mb >= 1024.0:
		return "%.2f GB" % (mb / 1024.0)
	return "%.1f MB" % mb
