#!/usr/bin/env python3
# Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
# Copyright (C) 2026 Greenshot for Mac (Community) contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The translations of the app, made from Greenshot's language packs (docs/translations.md).

The Mac's English text is the key of every translation (what SwiftUI and `String(localized:)` look up). This tool
matches those texts with the English values of upstream Greenshot's language packs (src/Greenshot/Languages and the
plug-ins' packs, vendored in scripts/l10n/upstream) and writes one Localizable.strings per language. A text without an
upstream key stays English.

Commands (run from anywhere, `python3 -I scripts/l10n/l10n.py <command>`):
  vendor --upstream <checkout>   copy upstream's language packs and help pages into the repository
  keys <stringsdata folder>      the Mac's texts from the compiler (scripts/l10n/extract.sh) as JSON on stdout
  generate [--machine]           write Resources/Localizations, LanguagePacks+Generated.swift, docs/translations.md
  check [--machine]              fail when the committed files differ from what generate writes
  suggest                        near matches for texts without an upstream key (for overrides.tsv), TSV on stdout
  candidates <paths...>          string literals that may need `String(localized:)`, for wrapping work

Python 3.9, standard library only.
"""
from __future__ import annotations

import argparse
import difflib
import filecmp
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

UPSTREAM_DIR = os.path.join(HERE, "upstream")
MACHINE_DIR = os.path.join(HERE, "machine")
LANGUAGES_TSV = os.path.join(HERE, "languages.tsv")
OVERRIDES_TSV = os.path.join(HERE, "overrides.tsv")
MAC_KEYS_JSON = os.path.join(HERE, "mac-keys.json")

LOCALIZATIONS = os.path.join("Resources", "Localizations")
HELP = os.path.join("Resources", "Help")
GENERATED_SWIFT = os.path.join("Sources", "GreenshotCore", "Localization", "LanguagePacks+Generated.swift")
REPORT = os.path.join("docs", "translations.md")

BASE_LANGUAGE = "en-US"
CORE = "core"
# Upstream's core sections, in the order a text is taken from when several keys have it.
CORE_SECTIONS = ["Core", "Editor", "Settings", "Welcome", "SelfService", "Recipe"]
APP_NAME = "Greenshot"
CREDIT_KEY = "__about_translation__"

# Help pages that aren't UTF-8 upstream; everything else is UTF-8 (a BOM is dropped).
HELP_ENCODINGS = {"help-hu-HU.html": "cp1250"}
HELP_FALLBACK_ENCODING = "cp1252"

# Windows wording that must not reach the Mac through an override or a machine translation (it can't through an exact
# match: the Mac's English would have to say it too).
WINDOWS_TERMS = [r"\bWindows\b", r"\bExplorer\b", r"\bCtrl\b", r"\bStrg\b", r"\bPrtSc\b", r"\bPrint Screen\b",
                 r"\b[Tt]ray\b", r"\b[Tt]askbar\b", r"\bnotification area\b", r"\b[Rr]egistry\b", r"\.ini\b"]

# printf specifiers as the Swift compiler writes them into keys (`%@`, `%lld`, `%lf` …), optionally positional.
MAC_SPEC = re.compile(r"%(?:(\d+)\$)?(@|ll[duxX]|l[duxXf]|[dDiuUxXoOfFeEgGcCsSaAp])")
# .NET composite format items: {0}, {1:N0}, {2,-10}.
UPSTREAM_PLACEHOLDER = re.compile(r"\{(\d+)(?:,-?\d+)?(?::[^}]*)?\}")
TOKEN = "\x00"
APP_TOKEN = "\x01"


# MARK: ini files

def unescape_ini(value: str) -> str:
    """Dapplo.Ini's escapes: \\n, \\t and \\\\."""
    out, i = [], 0
    while i < len(value):
        c = value[i]
        if c == "\\" and i + 1 < len(value):
            n = value[i + 1]
            if n == "n":
                out.append("\n"); i += 2; continue
            if n == "t":
                out.append("\t"); i += 2; continue
            if n == "\\":
                out.append("\\"); i += 2; continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_ini(text: str) -> Dict[Tuple[str, str], str]:
    """{(section, key): value} of a language pack, values unescaped."""
    if text.startswith("\ufeff"):
        text = text[1:]
    data: Dict[Tuple[str, str], str] = {}
    section = ""
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        stripped = line.strip()
        if not stripped or stripped.startswith(";") or stripped.startswith("#"):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1].strip()
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[(section, key.strip())] = unescape_ini(value)
    return data


@dataclass
class Upstream:
    """The vendored language packs: values by (module, ietf), the descriptions, the commit."""
    packs: Dict[Tuple[str, str], Dict[Tuple[str, str], str]]
    descriptions: Dict[str, str]
    commit: str

    def value(self, module: str, ietf: str, section: str, key: str) -> str:
        return self.packs.get((module, ietf), {}).get((section, key), "")


def pack_file_parts(name: str) -> Optional[Tuple[str, str]]:
    """greenshot.de-DE.ini -> (core, de-DE); greenshot.jira.de-DE.ini -> (jira, de-DE)."""
    if not (name.startswith("greenshot.") and name.endswith(".ini")):
        return None
    parts = name[len("greenshot."):-len(".ini")].split(".")
    if len(parts) == 1:
        return CORE, parts[0]
    if len(parts) == 2:
        return parts[0], parts[1]
    return None


def load_upstream(folder: str = UPSTREAM_DIR) -> Upstream:
    packs: Dict[Tuple[str, str], Dict[Tuple[str, str], str]] = {}
    descriptions: Dict[str, str] = {}
    for name in sorted(os.listdir(folder)):
        parts = pack_file_parts(name)
        if not parts:
            continue
        with open(os.path.join(folder, name), encoding="utf-8-sig") as f:
            data = parse_ini(f.read())
        packs[parts] = data
        if parts[0] == CORE:
            descriptions[parts[1]] = data.get(("__language__", "Description"), parts[1]).strip()
    commit = ""
    commit_file = os.path.join(folder, "UPSTREAM")
    if os.path.exists(commit_file):
        with open(commit_file, encoding="utf-8") as f:
            commit = f.read().strip()
    return Upstream(packs, descriptions, commit)


# MARK: languages

@dataclass(frozen=True)
class Language:
    ietf: str
    lproj: str
    rtl: bool


def load_languages(path: str = LANGUAGES_TSV) -> List[Language]:
    languages = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            ietf, lproj, rtl = line.split("\t")[:3]
            languages.append(Language(ietf, lproj, rtl.strip() == "rtl"))
    return languages


# MARK: matching

def mac_specs(text: str) -> List[str]:
    """The conversions of the printf specifiers of a Mac key, in text order ('@', 'lld', …)."""
    return [m.group(2) for m in MAC_SPEC.finditer(text.replace("%%", ""))]


def upstream_placeholders(text: str) -> List[int]:
    return [int(m.group(1)) for m in UPSTREAM_PLACEHOLDER.finditer(text.replace("{{", "").replace("}}", ""))]


def _normalise_text(text: str) -> str:
    text = text.replace("\u2026", "...")
    text = re.sub(r"\s+", " ", text).strip()
    while True:
        trimmed = re.sub(r"(\.\.\.|[:\uff1a])\s*$", "", text).rstrip()
        if trimmed == text:
            break
        text = trimmed
    return text.casefold()


def normalise_mac(text: str) -> str:
    """The Mac's English for comparing: specifiers as one token, `…` as `...`, spaces collapsed, no trailing `...`
    or colon, case folded. `&` stays: upstream has no mnemonics (its `&`s are literal)."""
    marked = MAC_SPEC.sub(TOKEN, text.replace("%%", "\x02")).replace("\x02", "%")
    return _normalise_text(marked)


def normalise_upstream(text: str, app_name_token: bool = False) -> str:
    marked = UPSTREAM_PLACEHOLDER.sub(TOKEN, text.replace("{{", "\x03").replace("}}", "\x04"))
    marked = marked.replace("\x03", "{").replace("\x04", "}")
    if app_name_token:
        marked = re.sub(r"\b%s\b" % APP_NAME, TOKEN, marked)
    return _normalise_text(marked)


def upstream_tokens(text: str, app_name_token: bool) -> List[Optional[int]]:
    """The placeholders of an upstream text in text order: their index, None for the app name."""
    pattern = UPSTREAM_PLACEHOLDER.pattern + (r"|\b%s\b" % APP_NAME if app_name_token else "")
    tokens: List[Optional[int]] = []
    for m in re.finditer(pattern, text.replace("{{", "").replace("}}", "")):
        tokens.append(int(m.group(1)) if m.group(1) is not None else None)
    return tokens


@dataclass(frozen=True)
class Ref:
    module: str
    section: str
    key: str

    def __str__(self) -> str:
        return "%s:%s.%s" % (self.module, self.section, self.key)

    @staticmethod
    def parse(text: str) -> "Ref":
        module, rest = text.split(":", 1)
        section, key = rest.split(".", 1)
        return Ref(module, section, key)

    def rank(self) -> Tuple[int, int, str, str]:
        if self.module == CORE:
            index = CORE_SECTIONS.index(self.section) if self.section in CORE_SECTIONS else len(CORE_SECTIONS)
            return (0, index, "", self.key)
        return (1, 0, self.module, self.key)


@dataclass
class Candidate:
    ref: Ref
    english: str  # upstream's en-US value
    kind: str  # exact, normalised, app name, override
    tokens: List[Optional[int]]  # upstream placeholders in text order (None: the app name), aligned with the Mac's


def english_values(up: Upstream) -> List[Tuple[Ref, str]]:
    values = []
    for (module, ietf), data in sorted(up.packs.items()):
        if ietf != BASE_LANGUAGE:
            continue
        for (section, key), value in sorted(data.items()):
            if section == "__language__" or not value.strip():
                continue
            values.append((Ref(module, section, key), value))
    return values


@dataclass
class Override:
    english: str
    action: str  # map, pin, reject
    ref: Optional[Ref]
    note: str


def load_overrides(path: str = OVERRIDES_TSV) -> List[Override]:
    overrides = []
    if not os.path.exists(path):
        return overrides
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) < 2:
                raise SystemExit("overrides.tsv:%d: expected english<TAB>action<TAB>ref<TAB>note" % number)
            english = unescape_tsv(columns[0])
            action = columns[1].strip()
            ref = Ref.parse(columns[2].strip()) if len(columns) > 2 and columns[2].strip() else None
            note = columns[3].strip() if len(columns) > 3 else ""
            if action not in ("map", "pin", "reject"):
                raise SystemExit("overrides.tsv:%d: unknown action %r" % (number, action))
            if action in ("map", "pin") and ref is None:
                raise SystemExit("overrides.tsv:%d: %s needs an upstream key" % (number, action))
            overrides.append(Override(english, action, ref, note))
    return overrides


def unescape_tsv(text: str) -> str:
    return unescape_ini(text)


def windows_terms(text: str) -> List[str]:
    return [p for p in WINDOWS_TERMS if re.search(p, text)]


def new_windows_terms(translation: str, english: str) -> List[str]:
    """Windows terms in `translation` that the Mac's English doesn't have."""
    return [p for p in windows_terms(translation) if not re.search(p, english)]


class Matcher:
    """Finds the upstream keys of a Mac text."""

    def __init__(self, up: Upstream, overrides: List[Override]):
        self.values = english_values(up)
        self.by_value: Dict[str, List[Tuple[Ref, str]]] = {}
        self.by_normal: Dict[str, List[Tuple[Ref, str]]] = {}
        self.by_app_normal: Dict[str, List[Tuple[Ref, str]]] = {}
        self.by_ref: Dict[Ref, str] = {}
        for ref, value in self.values:
            self.by_ref[ref] = value
            self.by_value.setdefault(value, []).append((ref, value))
            self.by_normal.setdefault(normalise_upstream(value), []).append((ref, value))
            if re.search(r"\b%s\b" % APP_NAME, value):
                self.by_app_normal.setdefault(normalise_upstream(value, True), []).append((ref, value))
        self.overrides: Dict[str, List[Override]] = {}
        for override in overrides:
            self.overrides.setdefault(override.english, []).append(override)
        self.problems: List[str] = []
        for override in overrides:
            if override.ref is not None and override.ref not in self.by_ref:
                self.problems.append("overrides.tsv: %s is no upstream en-US key" % override.ref)
            if override.action in ("map", "pin") and override.ref in self.by_ref:
                terms = new_windows_terms(self.by_ref[override.ref], override.english)
                if terms and not override.note.startswith("ok:"):
                    self.problems.append("overrides.tsv: %r -> %s has Windows wording (%s); start the note with 'ok:'"
                                         % (override.english, override.ref, ", ".join(terms)))
        if self.problems:
            raise SystemExit("\n".join(self.problems))

    def candidates(self, english: str) -> Tuple[List[Candidate], List[Override]]:
        """The upstream keys of `english`, best first, and the overrides that applied."""
        specs = mac_specs(english)
        overrides = self.overrides.get(english, [])
        forced = [o for o in overrides if o.action in ("map", "pin")]
        if forced:
            result = []
            for o in forced:
                value = self.by_ref[o.ref]
                tokens = align(value, len(specs))
                if tokens is None:
                    raise SystemExit("overrides.tsv: %r and %s have different placeholders" % (english, o.ref))
                result.append(Candidate(o.ref, value, "override", tokens))
            return result, overrides
        found: Dict[Ref, Candidate] = {}
        for ref, value in self.by_value.get(english, []):
            tokens = align(value, len(specs))
            if tokens is not None:
                found[ref] = Candidate(ref, value, "exact", tokens)
        normal = normalise_mac(english)
        for ref, value in self.by_normal.get(normal, []):
            if ref not in found:
                tokens = upstream_tokens(value, False)
                if len(tokens) == len(specs):
                    found[ref] = Candidate(ref, value, "normalised", tokens)
        if specs:
            for ref, value in self.by_app_normal.get(normal, []):
                if ref not in found:
                    tokens = upstream_tokens(value, True)
                    if len(tokens) == len(specs):
                        found[ref] = Candidate(ref, value, "app name", tokens)
        for o in overrides:
            if o.action == "reject":
                if o.ref is None:
                    found.clear()
                else:
                    found.pop(o.ref, None)
        return sorted(found.values(), key=lambda c: c.ref.rank()), overrides


def align(value: str, count: int) -> Optional[List[Optional[int]]]:
    """The placeholders of `value` for a Mac text with `count` specifiers in the same order; the app name counts as a
    placeholder when that makes them agree. None: they don't agree."""
    tokens = upstream_tokens(value, False)
    if len(tokens) == count:
        return tokens
    tokens = upstream_tokens(value, True)
    if len(tokens) == count:
        return tokens
    return None


# MARK: translations

def is_cjk(lproj: str) -> bool:
    return lproj.startswith("zh") or lproj.startswith("ja")


def align_punctuation(translation: str, english: str, lproj: str) -> str:
    """The translation with the Mac text's trailing ellipsis and colon (upstream often differs: "Settings..." where the
    Mac has "Settings…", "Width:" where the Mac's form has "Width")."""
    text = translation.rstrip()
    mac = english.rstrip()
    colon_match = re.search(r"[\s\u00a0]*[:\uff1a]$", text)
    colon = colon_match.group(0) if colon_match else ""
    if colon_match:
        text = text[:colon_match.start()].rstrip()
    ellipsis = text.endswith("\u2026") or text.endswith("...")
    mac_colon = mac.endswith(":") or mac.endswith("\uff1a")
    mac_core = mac[:-1].rstrip() if mac_colon else mac
    if mac_core.endswith("\u2026") or mac_core.endswith("..."):
        if ellipsis:
            text = text[:-1] if text.endswith("\u2026") else text[:-3]
            text = text.rstrip()
        text += "\u2026" if mac_core.endswith("\u2026") else "..."
    elif ellipsis:
        text = (text[:-1] if text.endswith("\u2026") else text[:-3]).rstrip()
    if mac_colon:
        text += colon if colon else ("\uff1a" if is_cjk(lproj) else ":")
    return text


def align_case(translation: str, english: str) -> str:
    """A capital first letter where the Mac text starts with one (upstream's text may come from inside a sentence or a
    submenu: "alle" for the Mac's "All")."""
    if translation and english and english[0].isupper() and translation[0].islower():
        return translation[0].upper() + translation[1:]
    return translation


def spec_signature(text: str) -> Optional[List[Tuple[int, str]]]:
    """[(position, conversion)] of a format string, sorted; None when it has a `%` that is no specifier."""
    result: List[Tuple[int, str]] = []
    sequential = 0
    i = 0
    while i < len(text):
        if text[i] != "%":
            i += 1
            continue
        if text.startswith("%%", i):
            i += 2
            continue
        m = MAC_SPEC.match(text, i)
        if not m:
            return None
        if m.group(1):
            position = int(m.group(1))
        else:
            sequential += 1
            position = sequential
        result.append((position, m.group(2)))
        i = m.end()
    return sorted(result)


def key_signature(key: str) -> List[Tuple[int, str]]:
    return [(i + 1, conversion) for i, conversion in enumerate(mac_specs(key))]


def convert(translation: str, key: str, english: str, candidate: Candidate, lproj: str) -> Tuple[Optional[str], str]:
    """An upstream translation as a value for the Mac key: (value, "") or (None, why it was dropped). The specifiers
    come from the Mac's English (`english`: the key, or its `defaultValue` when the key is an identifier)."""
    text = translation.strip()
    if not text or text == candidate.english.strip():
        return None, ""  # untranslated: English, not a drop
    specs = mac_specs(english)
    text = align_case(align_punctuation(text, english, lproj), english)
    if specs:
        text = text.replace("%", "%%")
        positions: Dict[int, int] = {}
        app_positions: List[int] = []
        for j, token in enumerate(candidate.tokens, 1):
            if token is None:
                app_positions.append(j)
            else:
                positions[token] = j

        def spec(position: int) -> str:
            conversion = specs[position - 1]
            return "%%%d$%s" % (position, conversion) if len(specs) > 1 else "%" + conversion

        problem = []

        def replace(m: re.Match) -> str:
            index = int(m.group(1))
            if index not in positions:
                problem.append("placeholder {%d} isn't in the English" % index)
                return m.group(0)
            return spec(positions[index])

        text = UPSTREAM_PLACEHOLDER.sub(replace, text.replace("{{", "\x03").replace("}}", "\x04"))
        text = text.replace("\x03", "{").replace("\x04", "}")
        if problem:
            return None, problem[0]
        if app_positions:
            names = list(re.finditer(r"\b%s\b" % APP_NAME, text))
            if len(names) != len(app_positions):
                return None, "the app name isn't written %s" % APP_NAME
            pieces, last = [], 0
            for m, position in zip(names, app_positions):
                pieces.append(text[last:m.start()])
                pieces.append(spec(position))
                last = m.end()
            pieces.append(text[last:])
            text = "".join(pieces)
        if spec_signature(text) != key_signature(english):
            return None, "placeholders differ from the English"
    else:
        if UPSTREAM_PLACEHOLDER.search(text):
            return None, "placeholders differ from the English"
    if text == english:
        return None, ""
    return text, ""


def convert_machine(translation: str, key: str, english: str) -> Tuple[Optional[str], str]:
    """A machine translation of the Mac's English (written with the Mac's specifiers): (value, "") or (None, why)."""
    text = translation.strip()
    if not text or text == english:
        return None, ""
    if mac_specs(english) or "%%" in english:
        if spec_signature(text) != key_signature(english):
            return None, "placeholders differ from the English"
    elif MAC_SPEC.search(text):
        return None, "placeholders differ from the English"
    terms = new_windows_terms(text, english)
    if terms:
        return None, "Windows wording"
    return text, ""


def load_machine(lproj: str, folder: str = MACHINE_DIR) -> Dict[str, Tuple[str, str]]:
    """english -> (translation, source) of scripts/l10n/machine/<lproj>.tsv; empty when there is none."""
    path = os.path.join(folder, lproj + ".tsv")
    table: Dict[str, Tuple[str, str]] = {}
    if not os.path.exists(path):
        return table
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) < 2:
                continue
            table[unescape_tsv(columns[0])] = (unescape_tsv(columns[1]), columns[2].strip() if len(columns) > 2 else "")
    return table


# MARK: generation

@dataclass
class MacKey:
    key: str
    value: Optional[str]
    files: List[str]

    @property
    def english(self) -> str:
        return self.value if self.value is not None else self.key


def load_mac_keys(path: str = MAC_KEYS_JSON) -> List[MacKey]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return [MacKey(k["key"], k.get("value"), k.get("files", [])) for k in data["keys"]]


@dataclass
class Entry:
    key: str
    value: str
    comment: str


@dataclass
class Result:
    """What generate found: the entries per language and the numbers for the report."""
    entries: Dict[str, List[Entry]] = field(default_factory=dict)
    upstream_entries: Dict[str, List[Entry]] = field(default_factory=dict)
    matched: Dict[str, List[Candidate]] = field(default_factory=dict)
    kinds: Dict[str, int] = field(default_factory=dict)
    rejected: List[Tuple[str, str]] = field(default_factory=list)
    conflicts: Dict[str, List[str]] = field(default_factory=dict)
    drops: Dict[Tuple[str, str], List[str]] = field(default_factory=dict)
    machine_counts: Dict[str, int] = field(default_factory=dict)
    upstream_counts: Dict[str, int] = field(default_factory=dict)


def strings_escape(text: str) -> str:
    return (text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")
            .replace("\r", "\\r"))


def comment_escape(text: str) -> str:
    return text.replace("*/", "* /")


def build(up: Upstream, languages: List[Language], keys: List[MacKey], overrides: List[Override],
          machine: bool, machine_folder: str = MACHINE_DIR) -> Result:
    matcher = Matcher(up, overrides)
    result = Result()
    for mac in keys:
        candidates, applied = matcher.candidates(mac.english)
        for o in applied:
            if o.action == "reject":
                result.rejected.append((mac.english, str(o.ref) if o.ref else "all keys"))
        if candidates:
            result.matched[mac.key] = candidates
            kind = candidates[0].kind
            result.kinds[kind] = result.kinds.get(kind, 0) + 1
    for language in languages:
        entries: List[Entry] = []
        machine_table = load_machine(language.lproj, machine_folder) if machine else {}
        upstream_count = machine_count = 0
        for mac in keys:
            if language.ietf == BASE_LANGUAGE:
                break
            value, comment = None, ""
            outputs = []
            for candidate in result.matched.get(mac.key, []):
                raw = up.value(candidate.ref.module, language.ietf, candidate.ref.section, candidate.ref.key)
                if not raw.strip():
                    continue
                converted, why = convert(raw, mac.key, mac.english, candidate, language.lproj)
                if converted is None:
                    if why:
                        result.drops.setdefault((mac.english, why), []).append(language.ietf)
                    continue
                outputs.append((converted, candidate))
            if outputs:
                value, chosen = outputs[0]
                comment = str(chosen.ref) + ("" if chosen.kind == "exact" else ", " + chosen.kind)
                if len({o[0] for o in outputs}) > 1:
                    result.conflicts.setdefault(mac.english, []).append(language.ietf)
                upstream_count += 1
            elif machine and mac.english in machine_table and mac.key not in result.matched:
                translation, _source = machine_table[mac.english]
                converted, why = convert_machine(translation, mac.key, mac.english)
                if converted is None:
                    if why:
                        result.drops.setdefault((mac.english, "machine: " + why), []).append(language.ietf)
                else:
                    value, comment = converted, "machine"
                    machine_count += 1
            if value is not None:
                entries.append(Entry(mac.key, value, comment))
        result.entries[language.lproj] = sorted(entries, key=lambda e: e.key)
        result.upstream_counts[language.lproj] = upstream_count
        result.machine_counts[language.lproj] = machine_count
        result.upstream_entries[language.lproj] = upstream_table(up, language)
    return result


def upstream_table(up: Upstream, language: Language) -> List[Entry]:
    """Every upstream English text without placeholders -> its translation, for `L10nText.display` (texts that are also
    data), and the pack's translator credit."""
    if language.ietf == BASE_LANGUAGE:
        return []
    chosen: Dict[str, Tuple[Tuple[int, int, str, str], Entry]] = {}
    for ref, english in english_values(up):
        if UPSTREAM_PLACEHOLDER.search(english):
            continue
        raw = up.value(ref.module, language.ietf, ref.section, ref.key).strip()
        if not raw or raw == english.strip():
            continue
        current = chosen.get(english)
        if current is None or ref.rank() < current[0]:
            chosen[english] = (ref.rank(), Entry(english, raw, str(ref)))
    entries = [e for _, e in chosen.values()]
    credit = up.value(CORE, language.ietf, "Core", "about_translation").strip()
    if credit:
        entries.append(Entry(CREDIT_KEY, credit, "core:Core.about_translation"))
    return sorted(entries, key=lambda e: e.key)


def strings_file(entries: List[Entry], header: str) -> str:
    lines = ["/* " + comment_escape(header) + " */", ""]
    for e in entries:
        lines.append("/* %s */" % comment_escape(e.comment))
        lines.append("\"%s\" = \"%s\";" % (strings_escape(e.key), strings_escape(e.value)))
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


def swift_string(text: str) -> str:
    return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\""


def generated_swift(up: Upstream, languages: List[Language], help_files: List[str]) -> str:
    lines = [
        "// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot",
        "// Copyright (C) 2026 Greenshot for Mac (Community) contributors",
        "// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom",
        "// SPDX-License-Identifier: GPL-3.0-or-later",
        "// Generated by scripts/l10n/l10n.py from scripts/l10n/languages.tsv and the language packs (upstream %s). "
        "Don't edit." % (up.commit or "?"),
        "",
        "extension LanguagePacks {",
        "    /// Upstream's language packs, by upstream code (the `Description=` of each pack is its name).",
        "    public static let all: [LanguagePack] = [",
    ]
    for language in sorted(languages, key=lambda l: l.ietf):
        help_file = "help-%s.html" % language.ietf
        help_text = swift_string(help_file) if help_file in help_files else "nil"
        lines.append("        LanguagePack(ietf: %s, lproj: %s, description: %s, rightToLeft: %s, helpFile: %s),"
                     % (swift_string(language.ietf), swift_string(language.lproj),
                        swift_string(up.descriptions.get(language.ietf, language.ietf)),
                        "true" if language.rtl else "false", help_text))
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def report(up: Upstream, languages: List[Language], keys: List[MacKey], result: Result, machine: bool,
           help_files: List[str]) -> str:
    total = len(keys)
    matched = len(result.matched)
    lines = [
        "# Translations",
        "",
        "<!-- Generated by scripts/l10n/l10n.py generate%s. Don't edit: change the tool, scripts/l10n/overrides.tsv or "
        "scripts/l10n/languages.tsv and run scripts/l10n/update.sh. -->" % (" --machine" if machine else ""),
        "",
        "Greenshot for Mac (Community) reuses the translations of Greenshot for Windows: its language packs (upstream "
        "commit `%s`, vendored in `scripts/l10n/upstream`) are matched with the Mac's English texts. A Mac text whose "
        "English is also an upstream text (the same words; an ellipsis, a trailing colon, spaces and capitals don't "
        "count) gets that text's translation; every other text stays English. The packs are GPL, like this app; the "
        "translators' credits are in each pack (`about_translation`) and About shows the one of the language in use."
        % (up.commit or "?"),
        "",
        "## How it works",
        "",
        "- `scripts/l10n/extract.sh` builds the app with the compiler's `-emit-localized-strings` and writes every "
        "localizable text (SwiftUI literals, `String(localized:)`) to `scripts/l10n/mac-keys.json`.",
        "- `scripts/l10n/l10n.py generate` matches them with the upstream English (`scripts/l10n/overrides.tsv` maps "
        "near matches by hand or rejects a wrong one) and writes `Resources/Localizations/<language>.lproj/"
        "Localizable.strings`, the `Upstream.strings` table for texts that are also data (`L10nText.display`) and "
        "`LanguagePacks+Generated.swift`. `scripts/l10n/update.sh` runs both steps.",
        "- `scripts/build-app.sh` copies the `.lproj` folders and the help pages (`Resources/Help`) into the app and "
        "lists the languages in `CFBundleLocalizations`, so macOS offers them in System Settings › General › Language "
        "& Region › Applications.",
        "- `scripts/l10n/l10n.py check` (CI) fails when the committed files differ from what `generate` writes.",
        "- New texts in the code: SwiftUI literals need nothing; AppKit and other texts use `String(localized: \"…\")`. "
        "Logs, data, identifiers and recipe/IPC/MCP texts stay English.",
        "- Updating from upstream: `python3 -I scripts/l10n/l10n.py vendor --upstream <checkout>`, then "
        "`scripts/l10n/update.sh`, then review `python3 -I scripts/l10n/l10n.py suggest` for new near matches.",
        "- Trying a language in a development build: `scripts/l10n/stage-dev.sh`, then `GreenshotMac --language de-DE` "
        "(or `--snapshot <folder> --language ar-SY`).",
        "",
        "## Coverage",
        "",
        "%d texts of the Mac are localizable; %d of them have an upstream key (%s)%s."
        % (total, matched, ", ".join("%s %d" % (k, v) for k, v in sorted(result.kinds.items())) or "none",
           "; %d rejected by overrides.tsv" % len(result.rejected) if result.rejected else ""),
        "",
    ]
    header = "| Language | Code | macOS | Translated | Share |"
    rule = "|---|---|---|---:|---:|"
    if machine:
        header = "| Language | Code | macOS | Upstream | Machine | Translated | Share |"
        rule = "|---|---|---|---:|---:|---:|---:|"
    lines += [header, rule]
    for language in sorted(languages, key=lambda l: l.ietf):
        if language.ietf == BASE_LANGUAGE:
            continue
        upstream_count = result.upstream_counts.get(language.lproj, 0)
        machine_count = result.machine_counts.get(language.lproj, 0)
        translated = upstream_count + machine_count
        share = "%d %%" % round(100.0 * translated / total) if total else "-"
        name = up.descriptions.get(language.ietf, language.ietf).replace("|", "/")
        if machine:
            lines.append("| %s | %s | %s | %d | %d | %d | %s |" % (name, language.ietf, language.lproj, upstream_count,
                                                                 machine_count, translated, share))
        else:
            lines.append("| %s | %s | %s | %d | %s |" % (name, language.ietf, language.lproj, translated, share))
    lines += ["", "Right to left: %s." % ", ".join(l.ietf for l in languages if l.rtl),
              "Help pages (`Resources/Help`, from upstream): %s." % ", ".join(
                  f[len("help-"):-len(".html")] for f in help_files), ""]
    if result.conflicts:
        lines += ["## Texts with several upstream keys", "",
                  "Their translations differ; the first key in upstream's order (Core, Editor, Settings, Welcome, "
                  "SelfService, Recipe, then the plug-ins) is used. Pin another one in overrides.tsv.", ""]
        for english in sorted(result.conflicts):
            refs = ", ".join(str(c.ref) for c in result.matched.get(english_key(keys, english), []))
            lines.append("- %s — %s (%d languages)" % (md(english), refs, len(result.conflicts[english])))
        lines.append("")
    if result.rejected:
        lines += ["## Rejected matches", ""]
        for english, ref in sorted(result.rejected):
            lines.append("- %s — %s" % (md(english), ref))
        lines.append("")
    if result.drops:
        lines += ["## Translations not used", "",
                  "These translations exist but don't fit the Mac text; the text stays English in those languages.", ""]
        for (english, why), languages_dropped in sorted(result.drops.items()):
            lines.append("- %s — %s: %s" % (md(english), why, ", ".join(sorted(set(languages_dropped)))))
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


def english_key(keys: List[MacKey], english: str) -> str:
    for k in keys:
        if k.english == english:
            return k.key
    return english


def md(text: str) -> str:
    return "`%s`" % text.replace("`", "'").replace("\n", " ")


def help_files_in(root: str) -> List[str]:
    folder = os.path.join(root, HELP)
    if not os.path.isdir(folder):
        return []
    return sorted(f for f in os.listdir(folder) if f.startswith("help-") and f.endswith(".html"))


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def generate(out_root: str, machine: bool, machine_folder: str = MACHINE_DIR, upstream_folder: str = UPSTREAM_DIR,
             keys_path: str = MAC_KEYS_JSON, help_root: str = ROOT) -> Result:
    up = load_upstream(upstream_folder)
    languages = load_languages()
    keys = load_mac_keys(keys_path)
    result = build(up, languages, keys, load_overrides(), machine, machine_folder)
    help_files = help_files_in(help_root)
    localizations = os.path.join(out_root, LOCALIZATIONS)
    if os.path.isdir(localizations):
        for name in os.listdir(localizations):
            if name.endswith(".lproj"):
                shutil.rmtree(os.path.join(localizations, name))
    for language in languages:
        pack = "greenshot.%s.ini and its plug-in packs" % language.ietf
        header = ("Generated by scripts/l10n/l10n.py from Greenshot's language packs (upstream %s, %s), "
                  "GPL-3.0-or-later. Don't edit: see docs/translations.md." % (up.commit or "?", pack))
        if language.ietf == BASE_LANGUAGE:
            header = ("English is the key of every text; this table is empty. Generated by scripts/l10n/l10n.py, "
                      "see docs/translations.md.")
        folder = os.path.join(localizations, language.lproj + ".lproj")
        write(os.path.join(folder, "Localizable.strings"), strings_file(result.entries[language.lproj], header))
        write(os.path.join(folder, "Upstream.strings"), strings_file(result.upstream_entries[language.lproj], header))
    write(os.path.join(out_root, GENERATED_SWIFT), generated_swift(up, languages, help_files))
    write(os.path.join(out_root, REPORT), report(up, languages, keys, result, machine, help_files))
    return result


def compare_trees(expected_root: str, actual_root: str) -> List[str]:
    """Differences between the generated files under two roots."""
    differences = []
    for relative in [LOCALIZATIONS]:
        a, b = os.path.join(expected_root, relative), os.path.join(actual_root, relative)
        a_files = set(walk(a)) if os.path.isdir(a) else set()
        b_files = set(walk(b)) if os.path.isdir(b) else set()
        for f in sorted(a_files ^ b_files):
            differences.append("%s: %s" % (os.path.join(relative, f), "missing" if f in a_files else "not generated"))
        for f in sorted(a_files & b_files):
            if not filecmp.cmp(os.path.join(a, f), os.path.join(b, f), shallow=False):
                differences.append("%s: differs" % os.path.join(relative, f))
    for relative in [GENERATED_SWIFT, REPORT]:
        a, b = os.path.join(expected_root, relative), os.path.join(actual_root, relative)
        if not os.path.exists(b):
            differences.append("%s: missing" % relative)
        elif not filecmp.cmp(a, b, shallow=False):
            differences.append("%s: differs" % relative)
    return differences


def walk(folder: str) -> Iterable[str]:
    for dirpath, _dirnames, filenames in os.walk(folder):
        for name in filenames:
            if name == ".DS_Store":
                continue
            yield os.path.relpath(os.path.join(dirpath, name), folder)


# MARK: vendoring

def vendor(checkout: str) -> None:
    sources = []
    src = os.path.join(checkout, "src")
    for project in sorted(os.listdir(src)):
        folder = os.path.join(src, project, "Languages")
        if project == "Greenshot" or project.startswith("Greenshot.Plugin."):
            if os.path.isdir(folder):
                sources += [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if pack_file_parts(f)]
    if os.path.isdir(UPSTREAM_DIR):
        shutil.rmtree(UPSTREAM_DIR)
    os.makedirs(UPSTREAM_DIR)
    for path in sources:
        with open(path, encoding="utf-8-sig") as f:
            text = f.read()
        write(os.path.join(UPSTREAM_DIR, os.path.basename(path)), text.replace("\r\n", "\n"))
    commit = subprocess.run(["git", "-C", checkout, "rev-parse", "--short=8", "HEAD"], check=True,
                            capture_output=True, text=True).stdout.strip()
    write(os.path.join(UPSTREAM_DIR, "UPSTREAM"), commit + "\n")
    help_out = os.path.join(ROOT, HELP)
    if os.path.isdir(help_out):
        shutil.rmtree(help_out)
    languages = os.path.join(src, "Greenshot", "Languages")
    for name in sorted(os.listdir(languages)):
        if name.startswith("help-") and name.endswith(".html"):
            with open(os.path.join(languages, name), "rb") as f:
                write(os.path.join(help_out, name), help_page_utf8(f.read(), name))
    print("Vendored %d language packs and %d help pages of upstream %s" % (len(sources), len(help_files_in(ROOT)),
                                                                          commit))


def help_page_utf8(data: bytes, name: str) -> str:
    """A help page as UTF-8 with a charset declaration (upstream's pages are partly Latin-1, without one)."""
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode(HELP_ENCODINGS.get(name, HELP_FALLBACK_ENCODING))
    text = text.replace("\r\n", "\n")
    text = re.sub(r"<meta[^>]*charset[^>]*>\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"<head>", "<head>\n\t\t<meta charset=\"utf-8\">", text, count=1, flags=re.IGNORECASE)
    return text


# MARK: keys from the compiler

def read_keys(folder: str) -> dict:
    found: Dict[Tuple[str, Optional[str]], set] = {}
    for dirpath, _dirnames, filenames in os.walk(folder):
        for name in sorted(filenames):
            if not name.endswith(".stringsdata"):
                continue
            with open(os.path.join(dirpath, name), encoding="utf-8") as f:
                data = json.load(f)
            source = data.get("source", "")
            relative = source[source.rfind("Sources/"):] if "Sources/" in source else os.path.basename(source)
            # The snapshots' sample texts aren't part of the app's UI.
            if os.path.basename(relative).startswith("Snapshots"):
                continue
            for table, entries in data.get("tables", {}).items():
                if table != "Localizable":
                    continue
                for entry in entries:
                    key = entry.get("key", "")
                    if not key.strip():
                        continue
                    found.setdefault((key, entry.get("value")), set()).add(relative)
    keys = []
    for (key, value), files in sorted(found.items(), key=lambda kv: (kv[0][0], kv[0][1] or "")):
        item = {"key": key}
        if value is not None:
            item["value"] = value
        item["files"] = sorted(files)
        keys.append(item)
    return {"keys": keys}


# MARK: suggestions and wrapping candidates

def suggest() -> str:
    up = load_upstream()
    matcher = Matcher(up, load_overrides())
    keys = load_mac_keys()
    normals = {}
    for ref, value in matcher.values:
        normals.setdefault(normalise_upstream(value), (ref, value))
    choices = list(normals)
    lines = ["# english\tratio\tupstream key\tupstream English"]
    for mac in keys:
        candidates, applied = matcher.candidates(mac.english)
        if candidates or applied:
            continue
        normal = normalise_mac(mac.english)
        if len(normal) < 4:
            continue
        best = difflib.get_close_matches(normal, choices, n=1, cutoff=0.8)
        if best:
            ref, value = normals[best[0]]
            ratio = difflib.SequenceMatcher(None, normal, best[0]).ratio()
            lines.append("%s\t%.2f\t%s\t%s" % (strings_escape(mac.english), ratio, ref, strings_escape(value)))
    return "\n".join(lines) + "\n"


UI_CONTEXT = re.compile(r"(Text|Button|Toggle|Picker|Section|LabeledContent|Label|TextField|SecureField|\.help|Stepper|"
                        r"Menu|GroupBox|DisclosureGroup|\.alert|\.confirmationDialog|Link)\(\s*$|"
                        r"(title|withTitle|checkboxWithTitle|radioButtonWithTitle|labelWithString|"
                        r"wrappingLabelWithString|label|message|placeholder|help|tooltip|toolTip)\s*:\s*$|"
                        r"(messageText|informativeText|placeholderString|toolTip|\.title|prompt|\.message|"
                        r"nameFieldLabel|stringValue)\s*=\s*$|setAccessibilityLabel\(\s*$")
SKIP_CONTEXT = re.compile(r"\blog\.(debug|info|warn|error)\(\s*$|\bprint\(\s*$|fatalError\(\s*$|forKey:\s*$|"
                          r"systemImage:\s*$|systemSymbolName:\s*$|named:\s*$|identifier:\s*$|URL\(string:\s*$|"
                          r"keyEquivalent:\s*$|String\(localized:\s*$|verbatim:\s*$")


def swift_literals(source: str) -> Iterable[Tuple[int, int, str]]:
    """(offset, line, text) of the plain string literals of Swift source outside comments."""
    i, n = 0, len(source)
    while i < n:
        if source.startswith("//", i):
            j = source.find("\n", i)
            i = n if j < 0 else j
            continue
        if source.startswith("/*", i):
            j = source.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if source.startswith('"""', i):
            j = source.find('"""', i + 3)
            if j < 0:
                return
            yield i, source.count("\n", 0, i) + 1, source[i + 3:j]
            i = j + 3
            continue
        if source[i] == "#" and source.startswith('#"', i):
            j = source.find('"#', i + 2)
            i = n if j < 0 else j + 2
            continue
        if source[i] == '"':
            j, depth = i + 1, 0
            while j < n and source[j] not in '"\n':
                if source[j] == "\\" and j + 1 < n and source[j + 1] == "(":
                    depth, j = 1, j + 2
                    while j < n and depth:
                        depth += {"(": 1, ")": -1}.get(source[j], 0)
                        j += 1
                    continue
                j += 2 if source[j] == "\\" else 1
            yield i, source.count("\n", 0, i) + 1, source[i + 1:j]
            i = j + 1
            continue
        i += 1


def candidates(paths: List[str]) -> str:
    out = []
    files = []
    for path in paths:
        if os.path.isdir(path):
            files += sorted(os.path.join(d, f) for d, _, fs in os.walk(path) for f in fs if f.endswith(".swift"))
        else:
            files.append(path)
    for path in files:
        if os.path.basename(path).startswith("Snapshots"):
            continue
        with open(path, encoding="utf-8") as f:
            source = f.read()
        for offset, line, text in swift_literals(source):
            if len(re.findall(r"[^\W\d_]", text)) < 2 or re.fullmatch(r"[a-z0-9_.\-/:]+", text):
                continue
            before = source[source.rfind("\n", 0, offset) + 1:offset]
            if SKIP_CONTEXT.search(before):
                continue
            kind = "ui" if UI_CONTEXT.search(before) else "other"
            out.append("%s:%d\t%s\t%s" % (path, line, kind, text.replace("\n", "\\n")))
    return "\n".join(out) + ("\n" if out else "")


# MARK: command line

def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("vendor")
    p.add_argument("--upstream", required=True)
    p = sub.add_parser("keys")
    p.add_argument("folder")
    for name in ("generate", "check"):
        p = sub.add_parser(name)
        p.add_argument("--machine", action="store_true", help="also use scripts/l10n/machine/<lproj>.tsv")
    sub.add_parser("suggest")
    p = sub.add_parser("candidates")
    p.add_argument("paths", nargs="+")
    args = parser.parse_args(argv)
    if args.command == "vendor":
        vendor(args.upstream)
    elif args.command == "keys":
        json.dump(read_keys(args.folder), sys.stdout, ensure_ascii=False, indent=1)
        sys.stdout.write("\n")
    elif args.command == "generate":
        result = generate(ROOT, args.machine)
        print("%d texts, %d with an upstream key; German %d, French %d, Japanese %d"
              % (len(load_mac_keys()), len(result.matched), result.upstream_counts.get("de", 0),
                 result.upstream_counts.get("fr", 0), result.upstream_counts.get("ja", 0)))
    elif args.command == "check":
        with tempfile.TemporaryDirectory() as temporary:
            generate(temporary, args.machine)
            differences = compare_trees(temporary, ROOT)
        if differences:
            print("The translations are out of date (run scripts/l10n/update.sh or l10n.py generate):")
            print("\n".join("  " + d for d in differences))
            return 1
        print("The translations are up to date.")
    elif args.command == "suggest":
        sys.stdout.write(suggest())
    elif args.command == "candidates":
        sys.stdout.write(candidates(args.paths))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
