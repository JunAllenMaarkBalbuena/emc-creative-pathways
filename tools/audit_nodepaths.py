"""Cross-check NodePath and unique-name references in GDScript against the real
scene trees produced by tools/audit_dump.gd.

Division of labour, chosen because each source is authoritative for something:

  * node paths per scene  -> from the JSON, i.e. the engine's own SceneState
  * unique names per scene-> parsed from .tscn text (SceneState has no
                              dependable accessor for these in 4.7)
  * literals in scripts   -> parsed from .gd text with comments stripped

The literal parser strips comments first. Three separate false positives came
from not doing that: a line reading `# %UniqueName lookups happen on demand`
is a comment, not a reference.

Two syntaxes matter and both occur in this project:

    $Overlay/Status              unquoted node path, relative to the script's node
    $%SaveDialog/VBox/HBox/SaveBtn   unique name followed by a subpath

`%` is also the modulo operator, so a percent sign preceded by whitespace is
treated as arithmetic and skipped.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --------------------------------------------------------------- tokenisation
# Format specifiers that appear as %s / %d inside format strings and are not
# node references. Without this list every `"%s" % value` in the project reads as
# a broken unique-name lookup - 62 of the 67 first-pass %"hits" were these.
FORMAT_SPECS = set("sdxXofeEcgbGiu")


def tokenise(src):
    """Split GDScript into code and string content.

    Returns (code, strings) where:
      code    - comments blanked AND string bodies blanked, so anything matched
                in it is genuine code. Length is preserved so character offsets
                still map back to line numbers.
      strings - list of (start_offset, body) for each string literal, so
                get_node("%Foo") style references inside strings can still be
                recovered and checked.

    Comments must be blanked before strings are scanned, and vice versa, or a
    '#' inside a string swallows real code.
    """
    code = list(src)
    strings = []
    i, n = 0, len(src)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if code[k] != "\n":
                code[k] = " "

    while i < n:
        c = src[i]
        if src.startswith('"""', i) or src.startswith("'''", i):
            q = src[i:i + 3]
            j = src.find(q, i + 3)
            j = n if j == -1 else j + 3
            strings.append((i, src[i + 3:(j - 3) if j - 3 > i + 3 else i + 3]))
            blank(i, j)
            i = j
            continue
        if c in ('"', "'"):
            j = i + 1
            body_start = j
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == c or src[j] == "\n":
                    break
                j += 1
            strings.append((i, src[body_start:j]))
            blank(i, min(j + 1, n))
            i = j + 1
            continue
        if c == "#":
            j = src.find("\n", i)
            j = n if j == -1 else j
            blank(i, j)
            i = j
            continue
        i += 1

    return "".join(code), strings


def strip_comments(src):
    """Comments blanked, string bodies preserved. Kept for the $ pass."""
    code = list(src)
    i, n = 0, len(src)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if code[k] != "\n":
                code[k] = " "

    while i < n:
        c = src[i]
        if src.startswith('"""', i) or src.startswith("'''", i):
            q = src[i:i + 3]
            j = src.find(q, i + 3)
            j = n if j == -1 else j + 3
            i = j
            continue
        if c in ('"', "'"):
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == c or src[j] == "\n":
                    break
                j += 1
            i = j + 1
            continue
        if c == "#":
            j = src.find("\n", i)
            j = n if j == -1 else j
            blank(i, j)
            i = j
            continue
        i += 1
    return "".join(code)


# ------------------------------------------------------------ literal parsing
RE_DOLLAR = re.compile(r"""\$(?:"([^"]+)"|'([^']+)'|([A-Za-z_][A-Za-z0-9_]*(?:/[A-Za-z0-9_]+)*))""")
# %Name or %Name/sub/path, with no whitespace before the % so modulo is excluded.
RE_PERCENT = re.compile(r"""(?<![\s%)\w])%([A-Za-z_][A-Za-z0-9_]*)((?:/[A-Za-z0-9_]+)*)""")
RE_UNIQUE_DECL = re.compile(
    r'^\[node name="([^"]+)"[^\]]*\]\s*\n(?:[^\n]*\n)*?[^\n]*?unique_name_in_owner\s*=\s*true',
    re.M)


def parse_gd_literals(path):
    """Return {'dollar': [...], 'percent': [...]} for one script.

    `percent` entries carry an `origin` of 'code' or 'string' so a broken
    get_node("%Foo") inside a string literal is not silently dropped, while
    "%s" in a format string never reaches the checker at all.
    """
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read()

    # $ lives in code, so comments must be blanked but strings preserved:
    # $"A/B" is a legitimate quoted node path.
    dollar_src = strip_comments(raw)
    code_src, strings = tokenise(raw)

    dollar, percent = [], []
    for m in RE_DOLLAR.finditer(dollar_src):
        val = m.group(1) or m.group(2) or m.group(3)
        if not val:
            continue
        dollar.append({"path": val, "line": dollar_src.count("\n", 0, m.start()) + 1})

    for m in RE_PERCENT.finditer(code_src):
        name = m.group(1)
        if name in FORMAT_SPECS and not m.group(2):
            continue          # "%s" % v  ->  format, not a node
        percent.append({
            "name": name,
            "subpath": (m.group(2) or "").strip("/"),
            "line": code_src.count("\n", 0, m.start()) + 1,
            "origin": "code",
        })

    # get_node("%Foo") and friends live inside string literals.
    for offset, body in strings:
        for m in RE_PERCENT.finditer(body):
            name = m.group(1)
            if name in FORMAT_SPECS and not m.group(2):
                continue
            percent.append({
                "name": name,
                "subpath": (m.group(2) or "").strip("/"),
                "line": raw.count("\n", 0, offset) + 1,
                "origin": "string",
            })

    return {"dollar": dollar, "percent": percent}


def parse_scene_unique_names(path):
    """Unique-name nodes declared in a .tscn.

    Godot 4.7 writes this as its own property line AFTER the [node] header:

        [node name="PlasticBtn" type="Button" parent="..." unique_id=299892993]
        script = ExtResource("3")
        unique_name_in_owner = true

    so it cannot be matched by a single-line regex against the header.
    """
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    names, pending = [], None
    for line in lines:
        m = re.match(r'^\[node name="([^"]+)"', line)
        if m:
            pending = m.group(1)
            continue
        if re.match(r'^\[', line):        # next section, node had no props
            pending = None
            continue
        if pending and re.search(r'unique_name_in_owner\s*=\s*true', line):
            names.append(pending)
            pending = None
    return names


# ------------------------------------------------------------ path resolution
def normalise(path):
    """Collapse '.' and '..' segments. Returns None if it escapes the root."""
    parts = []
    for seg in path.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if not parts:
                return None
            parts.pop()
            continue
        parts.append(seg)
    return "/".join(parts)


def to_scene_form(path):
    """Convert a resolved path into the './A/B' form SceneState reports."""
    p = normalise(path)
    if p is None:
        return None
    return "." if p == "" else "./" + p


def strip_scene_prefix(node_path):
    """'./TopBar/BackBtn' -> 'TopBar/BackBtn'; '.' -> ''."""
    p = normalise(node_path or ".")
    return p or ""


def main():
    dump_path = os.path.join(ROOT, ".godot", "audit_dump.json")
    with open(dump_path, encoding="utf-8") as fh:
        dump = json.load(fh)

    scenes = dump["scenes"]
    scene_by_path = {s["path"]: s for s in scenes}

    broken_dollar, broken_percent, unverifiable = [], [], []

    total_dollar = total_percent = 0

    for scene in scenes:
        res = scene["path"].replace("res://", "").replace("/", os.sep)
        if not os.path.isfile(res):
            continue
        unique_names = set(parse_scene_unique_names(res))
        node_paths = set()
        for n in scene["nodes"]:
            np = strip_scene_prefix(n["path"])
            node_paths.add(np)
            # Parents of every node are valid targets too.
            while "/" in np:
                np = np.rsplit("/", 1)[0]
                node_paths.add(np)

        for entry in scene.get("scripts", []):
            script_res = entry["script"].replace("res://", "").replace("/", os.sep)
            if not os.path.isfile(script_res):
                continue
            lits = parse_gd_literals(script_res)
            base = strip_scene_prefix(entry["node_path"])

            for lit in lits["dollar"]:
                total_dollar += 1
                combined = normalise((base + "/" + lit["path"]) if base else lit["path"])
                if combined is None:
                    broken_dollar.append({
                        "scene": scene["path"], "script": entry["script"],
                        "node": entry["node_path"], "ref": lit["path"],
                        "line": lit["line"], "why": "escapes scene root via ..",
                    })
                elif combined not in node_paths:
                    broken_dollar.append({
                        "scene": scene["path"], "script": entry["script"],
                        "node": entry["node_path"], "ref": lit["path"],
                        "line": lit["line"], "why": "no such node",
                    })

            for lit in lits["percent"]:
                total_percent += 1
                name = lit["name"]
                if name in unique_names:
                    # %Name/sub/path is legal; verify the tail if present.
                    if lit["subpath"]:
                        anchor = None
                        for np in node_paths:
                            if np == name or np.endswith("/" + name):
                                anchor = np
                                break
                        if anchor is not None:
                            combined = normalise(anchor + "/" + lit["subpath"])
                            if combined not in node_paths:
                                broken_percent.append({
                                    "scene": scene["path"], "script": entry["script"],
                                    "node": entry["node_path"],
                                    "ref": "%" + name + "/" + lit["subpath"],
                                    "line": lit["line"], "why": "subpath under unique name does not exist",
                                })
                    continue
                broken_percent.append({
                    "scene": scene["path"], "script": entry["script"],
                    "node": entry["node_path"], "ref": "%" + name,
                    "line": lit["line"], "why": "no node declares unique_name_in_owner",
                })

    # ---- scripts that are not attached to any scene: cannot be verified ----
    attached = set()
    for scene in scenes:
        for entry in scene.get("scripts", []):
            attached.add(entry["script"])

    report = {
        "counts": dump["counts"],
        "load_ok": len(dump["load_ok"]),
        "load_failures": dump["load_failures"],
        "scenes": len(scenes),
        "total_dollar_refs": total_dollar,
        "total_percent_refs": total_percent,
        "broken_dollar": broken_dollar,
        "broken_percent": broken_percent,
    }

    out_path = os.path.join(ROOT, ".godot", "audit_nodepaths.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)

    print("scenes analysed          :", len(scenes))
    print("resources loaded OK      :", report["load_ok"])
    print("resource load FAILURES   :", len(dump["load_failures"]))
    print("$ node-path refs checked :", total_dollar)
    print("  broken                 :", len(broken_dollar))
    print("%% unique-name refs       : %d" % total_percent)
    print("  broken                 :", len(broken_percent))
    print()
    if broken_dollar:
        print("== BROKEN $ refs ==")
        for b in broken_dollar:
            print("  %s  %s:%d" % (b["scene"], b["script"], b["line"]))
            print("      on node %s  $%s   -> %s" % (b["node"], b["ref"], b["why"]))
    if broken_percent:
        print("== BROKEN %% refs ==")
        for b in broken_percent:
            print("  %s  %s:%d" % (b["scene"], b["script"], b["line"]))
            print("      on node %s  %s   -> %s" % (b["node"], b["ref"], b["why"]))
    print()
    print("wrote", out_path)


if __name__ == "__main__":
    main()
