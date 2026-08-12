# Web Export Doctor

Tells you whether your Godot HTML5 export will pass itch.io's limits — **before**
you zip and upload, not after.

itch.io enforces two rules on HTML5 games: no single extracted file over
**200 MB**, and no more than **500 MB** extracted in total. Godot packs
everything into one `index.pck`, so a content-heavy project breaks the first
rule with no warning from the editor.

![Pre-flight report](addons/web_export_doctor/docs/screenshot.png)

## What it does

Hooks into the export and afterwards shows two independent verdicts — one per
rule:

```
Rule: 200 MB per file   FAIL
   index.pck is 241.4 MB — over the 200 MB per-file limit.
Rule: 500 MB total      PASS
   Total 279.4 MB is under 500 MB.
```

That pair is the whole point: a project can sit far below the total limit and
still be rejected, because one file is too big.

Plus a table of the content sorted by size, so you can see what is actually
filling the pack. Click a column header to change sorting.

The **Scan without exporting** button gives a quick estimate over `res://` when
you don't want to wait for a full export.

## Install

**From the Asset Store:** search for *Web Export Doctor* in the editor.

**Manually:**

1. Copy `addons/web_export_doctor/` into your project's `addons/` folder
2. Project → Project Settings → Plugins → enable **Web Export Doctor**
3. The panel appears in the right dock

## Limitations, stated plainly

- Web/HTML5 export only.
- **Your assets are never modified** — no compression, no re-encoding. They are
  read, never written.
- The quick scan is an **estimate**, but a close one. It reads the *imported*
  form of each resource rather than the source file, because that's what
  actually goes into the pack — a 1.5 MB `.wav` becomes a 0.3 MB `.sample`.
  Measured against real exports it lands between 0.93× and 1.01× of the real
  pack. A full export is still the final word.
- **Godot 4.7+**, developed and verified on 4.7.1 stable, on **Windows**.
  Linux, macOS and older 4.x releases are untested rather than unsupported —
  the report is plain GDScript and should behave the same anywhere. Tell me how
  it goes and I'll widen the range.

## No server

Everything runs locally in the editor. No telemetry, no license server, no
third-party calls. Works with the internet disconnected.

That isn't just a claim — it's enforced by a test. `run_tests.gd` scans every
script in the addon and fails if any of them mentions `HTTPRequest`,
`HTTPClient`, sockets or `OS.shell_open`.

## Tests

You can run these on your own project.

**Read-only** — pure logic, no files written:

```
godot --headless --path . -s addons/web_export_doctor/tools/run_tests.gd
```

**Writes to `build/`** — runs a real web export to compare against the estimate:

```
godot --headless --path . -s addons/web_export_doctor/tools/run_estimate_test.gd
```

## Splitting a pack that's over the limit

If the 200 MB rule fails, splitting into multiple packages is the only way out —
a monolithic `index.pck` cannot be squeezed past it. That is what the paid
[Pro version](https://itch.io/) does: it splits your content into packages under
the limit using Godot's own export pipeline, and ships a runtime `PackLoader`
autoload plus a loading screen scene.

You don't need it to find out whether you have a problem. You need it to solve
one.

## AI disclosure

The code and documentation in this repository were written with an AI
assistant. That says how it was written, not whether it works — so the numbers
it reports were checked against real uploads: a 205 MB build was uploaded to
itch.io and rejected, a 196 MB build was uploaded and accepted, and itch.io's
own error message reports the same figure the addon does, because both count in
the same 1024-based units. The test suite that verifies this ships with the
addon.

## License

MIT — see [LICENSE](LICENSE).
