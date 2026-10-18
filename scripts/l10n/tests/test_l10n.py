# Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
# Copyright (C) 2026 Greenshot for Mac (Community) contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests of scripts/l10n/l10n.py: python3 -I -m unittest discover -s scripts/l10n/tests"""
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import l10n  # noqa: E402

ELLIPSIS = "\u2026"


def upstream(values):
    """An Upstream of {(module, ietf): {(section, key): value}}."""
    return l10n.Upstream(values, {"en-US": "English", "de-DE": "Deutsch", "ja-JP": "Japanese"}, "test")


def candidate(english_value, tokens, kind="exact", ref="core:Core.key"):
    return l10n.Candidate(l10n.Ref.parse(ref), english_value, kind, tokens)


class IniTests(unittest.TestCase):
    def test_sections_escapes_and_comments(self):
        data = l10n.parse_ini("\ufeff[__language__]\nDescription=Deutsch\n; a comment\n[Core]\n"
                              "a=Eins\\nZwei\\tdrei\nb = x=y\npath=C:\\\\Temp\nempty=\n")
        self.assertEqual(data[("__language__", "Description")], "Deutsch")
        self.assertEqual(data[("Core", "a")], "Eins\nZwei\tdrei")
        self.assertEqual(data[("Core", "b")], " x=y")
        self.assertEqual(data[("Core", "path")], "C:\\Temp")
        self.assertEqual(data[("Core", "empty")], "")

    def test_pack_file_names(self):
        self.assertEqual(l10n.pack_file_parts("greenshot.de-DE.ini"), ("core", "de-DE"))
        self.assertEqual(l10n.pack_file_parts("greenshot.de-x-franconia.ini"), ("core", "de-x-franconia"))
        self.assertEqual(l10n.pack_file_parts("greenshot.jira.pt-BR.ini"), ("jira", "pt-BR"))
        self.assertIsNone(l10n.pack_file_parts("help-de-DE.html"))


class NormaliseTests(unittest.TestCase):
    def test_ellipsis_colon_case_spaces(self):
        self.assertEqual(l10n.normalise_mac("Settings" + ELLIPSIS), l10n.normalise_upstream("settings..."))
        self.assertEqual(l10n.normalise_mac("Width"), l10n.normalise_upstream("Width:"))
        self.assertEqual(l10n.normalise_mac("Open  the\nfile"), l10n.normalise_upstream("Open the file"))

    def test_placeholders_and_ampersand(self):
        self.assertEqual(l10n.normalise_mac("Saved %lld files to %@"), l10n.normalise_upstream("Saved {0:N0} files to {1}"))
        self.assertNotEqual(l10n.normalise_mac("System Hardware"), l10n.normalise_upstream("System & Hardware"))
        self.assertEqual(l10n.normalise_mac("100%% of %@"), l10n.normalise_upstream("100% of {0}"))

    def test_mac_specifiers(self):
        self.assertEqual(l10n.mac_specs("%lld of %@ at %lf"), ["lld", "@", "lf"])
        self.assertEqual(l10n.mac_specs("100%% done %@"), ["@"])
        self.assertEqual(l10n.spec_signature("%2$@ and %1$lld"), [(1, "lld"), (2, "@")])
        self.assertIsNone(l10n.spec_signature("50 % off %@"))


class MatchTests(unittest.TestCase):
    def setUp(self):
        self.up = upstream({
            ("core", "en-US"): {("Core", "settings"): "Settings...", ("Editor", "settings"): "Settings...",
                                ("Core", "about"): "About Greenshot", ("Core", "explorer"): "Open in Explorer",
                                ("Settings", "width"): "Width:"},
            ("core", "de-DE"): {("Core", "settings"): "Einstellungen...", ("Editor", "settings"): "Optionen...",
                                ("Core", "about"): "Über Greenshot", ("Settings", "width"): "Breite:"},
        })

    def test_exact_normalised_app_name(self):
        matcher = l10n.Matcher(self.up, [])
        found, _ = matcher.candidates("Settings" + ELLIPSIS)
        self.assertEqual([str(c.ref) for c in found], ["core:Core.settings", "core:Editor.settings"])
        self.assertEqual(found[0].kind, "normalised")
        found, _ = matcher.candidates("About %@")
        self.assertEqual([(str(c.ref), c.kind, c.tokens) for c in found], [("core:Core.about", "app name", [None])])
        self.assertEqual(matcher.candidates("About Greenshot")[0][0].kind, "exact")
        self.assertEqual(matcher.candidates("Height")[0], [])

    def test_overrides(self):
        reject = l10n.Override("Width", "reject", None, "")
        self.assertEqual(l10n.Matcher(self.up, [reject]).candidates("Width")[0], [])
        mapped = l10n.Override("Breadth", "map", l10n.Ref.parse("core:Settings.width"), "same meaning")
        found, _ = l10n.Matcher(self.up, [mapped]).candidates("Breadth")
        self.assertEqual([(str(c.ref), c.kind) for c in found], [("core:Settings.width", "override")])
        pinned = l10n.Override("Settings" + ELLIPSIS, "pin", l10n.Ref.parse("core:Editor.settings"), "")
        found, _ = l10n.Matcher(self.up, [pinned]).candidates("Settings" + ELLIPSIS)
        self.assertEqual([str(c.ref) for c in found], ["core:Editor.settings"])

    def test_an_identifier_keys_override_wins_over_its_english(self):
        by_key = l10n.Override("editor.width", "map", l10n.Ref.parse("core:Settings.width"), "")
        reject = l10n.Override("Width", "reject", None, "")
        matcher = l10n.Matcher(self.up, [by_key, reject])
        self.assertEqual([str(c.ref) for c in matcher.candidates("Width", "editor.width")[0]], ["core:Settings.width"])
        self.assertEqual(matcher.candidates("Width", "Width")[0], [])

    def test_override_with_windows_wording_is_refused(self):
        windows = l10n.Override("Show in Finder", "map", l10n.Ref.parse("core:Core.explorer"), "")
        with self.assertRaises(SystemExit):
            l10n.Matcher(self.up, [windows])
        allowed = l10n.Override("Show in Finder", "map", l10n.Ref.parse("core:Core.explorer"), "ok: reviewed")
        self.assertEqual(len(l10n.Matcher(self.up, [allowed]).candidates("Show in Finder")[0]), 1)


class ConvertTests(unittest.TestCase):
    def test_positions_follow_the_upstream_indexes(self):
        value, why = l10n.convert("{0}: {1} Dateien", "%lld files in %@", "%lld files in %@",
                                  candidate("{1} files in {0}", [1, 0]), "de")
        self.assertEqual((value, why), ("%2$@: %1$lld Dateien", ""))

    def test_single_specifier_number_format_and_percent(self):
        value, _ = l10n.convert("Qualität {0:N0} %", "Quality %lld%%", "Quality %lld%%",
                                candidate("Quality {0}%", [0]), "de")
        self.assertEqual(value, "Qualität %lld %%")
        value, _ = l10n.convert("100 % fertig", "100% done", "100% done", candidate("100% done", []), "de")
        self.assertEqual(value, "100 % fertig")

    def test_punctuation_and_case(self):
        self.assertEqual(l10n.align_punctuation("Einstellungen...", "Settings" + ELLIPSIS, "de"), "Einstellungen" + ELLIPSIS)
        self.assertEqual(l10n.align_punctuation("Einstellungen" + ELLIPSIS, "Settings", "de"), "Einstellungen")
        self.assertEqual(l10n.align_punctuation("Breite:", "Width", "de"), "Breite")
        self.assertEqual(l10n.align_punctuation("Breite", "Width:", "de"), "Breite:")
        self.assertEqual(l10n.align_punctuation("Largeur\u00a0:", "Width:", "fr"), "Largeur\u00a0:")
        self.assertEqual(l10n.align_punctuation("\u5e45", "Width:", "ja"), "\u5e45\uff1a")
        self.assertEqual(l10n.align_case("alle", "All"), "Alle")
        self.assertEqual(l10n.align_case("iPhone", "phone"), "iPhone")

    def test_upstream_hints_are_left_out(self):
        value, _ = l10n.convert("Pfeil zeichnen (A)", "Draw Arrow", "Draw Arrow", candidate("Draw arrow (A)", [], "override"), "de")
        self.assertEqual(value, "Pfeil zeichnen")
        value, _ = l10n.convert("\u77e2\u5370\uff08A\uff09", "Draw Arrow", "Draw Arrow", candidate("Draw arrow (A)", [], "override"), "ja")
        self.assertEqual(value, "\u77e2\u5370")
        value, _ = l10n.convert("Seite (A4)", "Page (A4)", "Page (A4)", candidate("Page (A4)", []), "de")
        self.assertEqual(value, "Seite (A4)")

    def test_app_name(self):
        value, _ = l10n.convert("Über Greenshot", "About %@", "About %@", candidate("About Greenshot", [None]), "de")
        self.assertEqual(value, "Über %@")
        value, why = l10n.convert("حول جرين شوت", "About %@", "About %@", candidate("About Greenshot", [None]), "ar")
        self.assertIsNone(value)
        self.assertIn("app name", why)

    def test_drops(self):
        value, why = l10n.convert("Gespeichert", "Saved %@", "Saved %@", candidate("Saved {0}", [0]), "de")
        self.assertIsNone(value)
        self.assertEqual(why, "placeholders differ from the English")
        value, why = l10n.convert("{1} gespeichert", "Saved %@", "Saved %@", candidate("Saved {0}", [0]), "de")
        self.assertIsNone(value)
        self.assertTrue(why)
        self.assertEqual(l10n.convert("Settings...", "Settings", "Settings", candidate("Settings...", []), "de"),
                         (None, ""))

    def test_texts_without_placeholders_keep_their_percent_sign(self):
        # Neither String(localized:) nor SwiftUI formats a text without arguments (probed: a table value "100 % A" and
        # "Rate %d ok" show as written), so no escaping; a printf specifier there would show as written too.
        value, _ = l10n.convert("Qualit\u00e4t 100 %", "Quality 100%", "Quality 100%", candidate("Quality 100%", []), "de")
        self.assertEqual(value, "Qualit\u00e4t 100 %")


    def test_a_leading_ellipsis_of_a_right_to_left_pack(self):
        self.assertEqual(l10n.align_punctuation("...\u05e9\u05de\u05d9\u05e8\u05d4", "Save As" + ELLIPSIS, "he"),
                         "\u05e9\u05de\u05d9\u05e8\u05d4" + ELLIPSIS)
        self.assertEqual(l10n.align_punctuation("...\u05e9\u05de\u05d9\u05e8\u05d4", "Save As", "he"),
                         "\u05e9\u05de\u05d9\u05e8\u05d4")
        self.assertEqual(l10n.align_punctuation("...weiter", "...more", "de"), "...weiter")

    def test_identifier_keys_use_the_default_value(self):
        value, _ = l10n.convert("Öffnen {0}", "menu.open", "Open %@", candidate("Open {0}", [0]), "de")
        self.assertEqual(value, "Öffnen %@")


class MachineTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.up = upstream({
            ("core", "en-US"): {("Core", "cancel"): "Cancel", ("Core", "undo"): "Undo"},
            ("core", "de-DE"): {("Core", "cancel"): "Abbrechen"},
        })
        with open(os.path.join(self.folder, "de.tsv"), "w", encoding="utf-8") as f:
            f.write("# english\ttranslation\tsource\n"
                    "Cancel\tStornieren\ttest model 2026-10-18\n"
                    "Undo\tRückgängig\ttest model 2026-10-18\n"
                    "Saved %@\tGespeichert: %@\treviewed by a test\n"
                    "Copied %@\tKopiert\ttest\n"
                    "Open the menu\tÖffne das Tray-Menü in Windows\ttest\n"
                    "A text the Mac no longer has\tEin alter Text\ttest\n"
                    "PNG\tPNG\ttest\n")
        self.languages = [l10n.Language("en-US", "en", False), l10n.Language("de-DE", "de", False)]
        self.keys = [l10n.MacKey(k, None, []) for k in ["Cancel", "Undo", "Saved %@", "Copied %@", "Open the menu", "PNG"]]

    def tearDown(self):
        shutil.rmtree(self.folder)

    def test_without_the_tables(self):
        result = l10n.build(self.up, self.languages, self.keys, [], False, self.folder)
        self.assertEqual([(e.key, e.value, e.comment) for e in result.entries["de"]], [("Cancel", "Abbrechen", "core:Core.cancel")])
        self.assertEqual(result.machine_counts["de"], 0)
        self.assertNotIn(l10n.MACHINE_KEY, [e.key for e in result.upstream_entries["de"]])

    def test_fills_only_texts_without_an_upstream_translation(self):
        result = l10n.build(self.up, self.languages, self.keys, [], True, self.folder)
        entries = {e.key: (e.value, e.comment) for e in result.entries["de"]}
        self.assertEqual(entries["Cancel"], ("Abbrechen", "core:Core.cancel"))
        # An upstream key the German pack doesn't translate.
        self.assertEqual(entries["Undo"], ("Rückgängig", "machine"))
        self.assertEqual(entries["Saved %@"], ("Gespeichert: %@", "machine, reviewed"))
        self.assertNotIn("Copied %@", entries)
        self.assertNotIn("Open the menu", entries)
        self.assertEqual(result.machine_counts["de"], 2)
        self.assertEqual(result.machine_reviewed["de"], 1)
        self.assertIn(("Copied %@", "machine: placeholders differ from the English"), result.drops)
        self.assertIn(("Open the menu", "machine: Windows wording"), result.drops)
        self.assertEqual(result.machine_unused["de"], [("A text the Mac no longer has", "no Mac text"),
                                                       ("Cancel", "upstream has a translation")])
        self.assertEqual(result.machine_sources["de"], {"test model 2026-10-18": 2, "reviewed by a test": 1, "test": 4})
        self.assertNotIn("PNG", entries)
        marker = [e for e in result.upstream_entries["de"] if e.key == l10n.MACHINE_KEY]
        self.assertEqual([e.value for e in marker], ["2"])

    def test_untranslated_rows(self):
        result = l10n.build(self.up, self.languages, self.keys, [], True, self.folder)
        # PNG's row keeps the English on purpose; the dropped rows need a fix.
        self.assertEqual(l10n.untranslated_rows(result, self.languages, self.keys),
                         [("de", "Copied %@"), ("de", "Open the menu")])
        plain = l10n.build(self.up, self.languages, self.keys, [], False, self.folder)
        self.assertEqual(len(l10n.untranslated_rows(plain, self.languages, self.keys)), 5)

    def test_tsv_escapes_round_trip(self):
        text = "Line one\nline two\twith a tab and a \\ backslash"
        self.assertEqual(l10n.unescape_tsv(l10n.escape_tsv(text)), text)
        self.assertNotIn("\n", l10n.escape_tsv(text))


class OutputTests(unittest.TestCase):
    def test_strings_escaping(self):
        text = l10n.strings_file([l10n.Entry("Say \"hi\"\n", "Sag \\ \"hallo\"", "core:Core.x */")], "header")
        self.assertIn("\"Say \\\"hi\\\"\\n\" = \"Sag \\\\ \\\"hallo\\\"\";", text)
        self.assertIn("/* core:Core.x * / */", text)

    def test_help_page_becomes_utf8(self):
        page = l10n.help_page_utf8("<html>\r\n<head>\r\n<title>Caf\xe9</title></head>".encode("cp1252"), "help-fr-FR.html")
        self.assertIn("Caf\u00e9", page)
        self.assertIn("<meta charset=\"utf-8\">", page)
        self.assertNotIn("\r", page)
        hu = l10n.help_page_utf8("<head>\u0151</head>".encode("cp1250"), "help-hu-HU.html")
        self.assertIn("\u0151", hu)
        old = l10n.help_page_utf8(b"<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"/></head>",
                                  "help-zh-CN.html")
        self.assertEqual(old.count("charset"), 1)


class HelpLinkTests(unittest.TestCase):
    def test_links_to_a_translators_disk_become_anchors(self):
        page = l10n.help_page_utf8(b'<head></head><a href="file:///G:/windowsxp/Projet/help-fr-FR2.html#settings">pr\xe9f</a>'
                                   b' <a href="file:///C:/x.html">x</a>', "help-fr-FR.html")
        self.assertIn('<a href="#settings">pr\u00e9f</a>', page)
        self.assertNotIn("file:///", page)
        self.assertIn(" x", page)


class ScopedRejectTests(unittest.TestCase):
    def test_a_reject_for_one_language(self):
        up = upstream({
            ("core", "en-US"): {("Editor", "cut"): "Cut", ("Editor", "copy"): "Copy"},
            ("core", "de-DE"): {("Editor", "cut"): "Kopieren", ("Editor", "copy"): "Kopieren"},
            ("core", "ja-JP"): {("Editor", "cut"): "\u5207\u308a\u53d6\u308a", ("Editor", "copy"): "\u30b3\u30d4\u30fc"},
        })
        languages = [l10n.Language("de-DE", "de", False), l10n.Language("ja-JP", "ja", False)]
        keys = [l10n.MacKey("Cut", None, ["Menu.swift"]), l10n.MacKey("Copy", None, ["Menu.swift"])]
        plain = l10n.build(up, languages, keys, [], False)
        self.assertEqual(plain.collisions["de"], [("Kopieren", "Copy", "Cut")])
        self.assertEqual(plain.collisions["ja"], [])
        reject = l10n.Override("Cut", "reject", l10n.Ref.parse("core:Editor.cut"), "", ("de",))
        scoped = l10n.build(up, languages, keys, [reject], False)
        self.assertEqual([e.key for e in scoped.entries["de"]], ["Copy"])
        self.assertEqual([e.key for e in scoped.entries["ja"]], ["Copy", "Cut"])
        self.assertEqual(scoped.collisions["de"], [])

    def test_only_reject_takes_languages(self):
        folder = tempfile.mkdtemp()
        try:
            path = os.path.join(folder, "overrides.tsv")
            with open(path, "w", encoding="utf-8") as f:
                f.write("Cut\treject@sl,pt-BR\tcore:Editor.cut\tnote\n")
            overrides = l10n.load_overrides(path)
            self.assertEqual(overrides[0].languages, ("sl", "pt-BR"))
            with open(path, "w", encoding="utf-8") as f:
                f.write("Cut\tmap@sl\tcore:Editor.cut\tnote\n")
            with self.assertRaises(SystemExit):
                l10n.load_overrides(path)
        finally:
            shutil.rmtree(folder)


class ScanTests(unittest.TestCase):
    SOURCE = "\n".join([
        '        Text("Ready to go")',
        '        label.stringValue = "Ready to go"',
        '        let done = String(localized: "Done", comment: "A note for translators")',
        '        case "Window title": break',
        '        title = BidiText.isolatedLTR("Shift Option")',
        '        alert.messageText = "Width <= 10 px; use a larger value"',
        '        log.info("Something happened here")',
        '        let s = "\u20ac"; item.title = "Save it now"',
        '        let id = "com.example.identifier"',
        '        let lines = """',
        '            Two lines',
        '            of text',
        '            """',
        '        let name = "Hello \\(user), welcome"',
    ])

    def scan(self, localized):
        return [(line, kind, text) for line, kind, text in l10n.scan_source(self.SOURCE, localized)]

    def test_literals_and_columns(self):
        found = {line: (column, text) for _, line, column, text in l10n.swift_literals(self.SOURCE)}
        self.assertEqual(found[1], (14, "Ready to go"))
        self.assertEqual(found[8][1], "Save it now")
        self.assertEqual(found[8][0], len('        let s = "\u20ac"; item.title = '.encode("utf-8")) + 1)
        self.assertEqual(found[10][1], "Two lines\nof text")
        self.assertEqual(found[14][1], "Hello " + l10n.TOKEN + ", welcome")

    def test_only_texts_the_compiler_didnt_extract(self):
        save_column = len('        let s = "\u20ac"; item.title = '.encode("utf-8")) + 1
        localized = {(1, 14), (3, 38), (8, save_column)}
        lines = {line: (kind, text) for line, kind, text in self.scan(localized)}
        self.assertEqual(lines[2], ("other", "Ready to go"))  # the same text elsewhere is still a plain String
        self.assertEqual(lines[6], ("ui", "Width <= 10 px; use a larger value"))
        self.assertIn(10, lines)
        self.assertIn(14, lines)
        for skipped in (1, 3, 4, 5, 7, 8, 9):
            self.assertNotIn(skipped, lines)


class GenerateTests(unittest.TestCase):
    """The real vendored packs with a few Mac texts, into a temporary root."""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.keys = os.path.join(self.root, "keys.json")
        with open(self.keys, "w", encoding="utf-8") as f:
            json.dump({"keys": [{"key": "Cancel", "files": []}, {"key": "Self-Service" + ELLIPSIS, "files": []},
                                {"key": "A text only the Mac has", "files": []}]}, f)
        self.machine = os.path.join(self.root, "machine")
        os.makedirs(self.machine)

    def tearDown(self):
        shutil.rmtree(self.root)

    def generate(self, out, machine):
        return l10n.generate(out, machine, machine_folder=self.machine, keys_path=self.keys)

    def read(self, root, relative):
        with open(os.path.join(root, relative), encoding="utf-8") as f:
            return f.read()

    def test_output_and_check(self):
        out = os.path.join(self.root, "a")
        self.generate(out, False)
        german = self.read(out, "Resources/Localizations/de.lproj/Localizable.strings")
        self.assertIn("\"Cancel\" = \"Abbrechen\";", german)
        self.assertIn("\"Self-Service" + ELLIPSIS + "\" = \"Fehlerbehebung" + ELLIPSIS + "\";", german)
        self.assertNotIn("A text only the Mac has", german)
        self.assertEqual(len([d for d in os.listdir(os.path.join(out, "Resources/Localizations"))]), 40)
        self.assertIn("\"Cancel\"", self.read(out, "Resources/Localizations/ja.lproj/Upstream.strings"))
        again = os.path.join(self.root, "b")
        self.generate(again, False)
        self.assertEqual(l10n.compare_trees(again, out), [])

    def test_machine_tables(self):
        plain = os.path.join(self.root, "plain")
        self.generate(plain, False)
        with open(os.path.join(self.machine, "de.tsv"), "w", encoding="utf-8") as f:
            f.write("A text only the Mac has\tEin Text nur vom Mac\ttest\n")
        unflagged = os.path.join(self.root, "unflagged")
        self.generate(unflagged, False)
        self.assertEqual(l10n.compare_trees(unflagged, plain), [])
        flagged = os.path.join(self.root, "flagged")
        self.generate(flagged, True)
        german = self.read(flagged, "Resources/Localizations/de.lproj/Localizable.strings")
        self.assertIn("/* machine */\n\"A text only the Mac has\" = \"Ein Text nur vom Mac\";", german)
        self.assertIn("machine translations of scripts/l10n/machine/de.tsv", german.splitlines()[0])
        self.assertNotIn("machine", self.read(flagged, "Resources/Localizations/fr.lproj/Localizable.strings"))
        self.assertIn("\"__machine_translations__\" = \"1\";",
                      self.read(flagged, "Resources/Localizations/de.lproj/Upstream.strings"))
        report = self.read(flagged, "docs/translations.md")
        self.assertIn("| Machine |", report)
        self.assertIn("## Machine translations", report)
        self.assertIn("Sources: test (1 rows). 0 rows keep the English on purpose", report)
        plain_report = self.read(plain, "docs/translations.md")
        self.assertNotIn("Machine", plain_report.split("## Coverage")[1].split("\n\n")[1])
        self.assertNotIn("## Machine translations", plain_report)
        self.assertIn("generate --no-machine", plain_report.splitlines()[2])


if __name__ == "__main__":
    unittest.main()
