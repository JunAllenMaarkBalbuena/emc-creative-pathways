"""Rewrite ext_resource `path=` values that point at a file's old location.

Eight entries carry a stale path plus a correct uid, left over from a
folder reorganisation. Godot resolves them anyway because it falls back to the
uid, which is why nothing errors today - but the path is a lie, it shows up as a
broken dependency in the editor, and it is what a fresh reimport or a hand-edit
of the uid would expose.

The rewrite is uid-driven, never guessed: each entry's uid is looked up, and the
file that owns that uid supplies the correct path. If a uid cannot be resolved
the entry is left alone and reported.

Run from the project root:  python tools/fix_ext_resource_paths.py [--check]
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Group order matters and is not obvious:
#   1 = '[ext_resource type="Script" '   2 = type
#   3 = attribute list (uid + path)      4 = 'id="1_cs_player"]'
#   5 = the bare id '1_cs_player'
# An earlier version unpacked 4 and 5 as if they were (id, tail) and emitted
# path="...gd"1_cs_player, which silently broke all six affected scenes. The
# tail is now rebuilt from the bare id rather than sliced out of a group.
RE_EXT = re.compile(
    r'(\[ext_resource\s+type="([^"]+)"\s+)([^\]]*?)id="([^"]+)"\]')
RE_ATTR = re.compile(r'(\w+)="([^"]*)"')
RE_INLINE_UID = re.compile(r'^\s*\[(?:gd_scene|gd_resource|gd_script)\b[^\]]*uid="(uid://[a-z0-9]+)"')


def git(*a):
    r = subprocess.run(("git",) + a, cwd=ROOT, capture_output=True, text=True)
    return r.stdout.splitlines()


def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def write(p, s):
    with open(os.path.join(ROOT, p), "w", encoding="utf-8", newline="") as fh:
        fh.write(s)


def build_uid_map():
    """uid -> res:// path, from .uid sidecars, .import files and inline headers.

    All three are needed. Textures carry their uid in the .import file, scripts
    in a .uid sidecar, and scenes/resources inline in their own first line, so
    a map built from sidecars alone reports 24 phantom unresolved references.
    """
    out = {}
    for f in git("ls-files", "*.uid"):
        t = read(f).strip()
        if t.startswith("uid://"):
            out[t] = "res://" + f[:-4].replace(os.sep, "/")
    for f in git("ls-files", "*.import"):
        m = re.search(r'uid="(uid://[a-z0-9]+)"', read(f))
        if m:
            out[m.group(1)] = "res://" + f[:-7].replace(os.sep, "/")
    for f in git("ls-files", "*.tscn", "*.tres"):
        with open(os.path.join(ROOT, f), encoding="utf-8", errors="replace") as fh:
            first = fh.readline()
        m = RE_INLINE_UID.match(first)
        if m:
            out[m.group(1)] = "res://" + f.replace(os.sep, "/")
    return out


def main():
    check_only = "--check" in sys.argv
    uid_map = build_uid_map()
    fixes, unresolvable = [], []

    for f in [x for x in git("ls-files") if x.endswith((".tscn", ".tres"))]:
        text = read(f)
        changed = False

        def repl(m):
            nonlocal changed
            head, rtype, attrs_s, rid = m.group(1), m.group(2), m.group(3), m.group(4)
            attrs = dict(RE_ATTR.findall(attrs_s))
            path = attrs.get("path")
            uid = attrs.get("uid")
            if not path or not uid:
                return m.group(0)

            disk = os.path.join(ROOT, path.replace("res://", "").replace("/", os.sep))
            if os.path.isfile(disk):
                return m.group(0)           # path already correct

            correct = uid_map.get(uid)
            if correct is None:
                unresolvable.append((f, rid, uid, path))
                return m.group(0)
            if correct == path:
                return m.group(0)

            new_attrs = dict(RE_ATTR.findall(attrs_s))
            new_attrs["path"] = correct
            # The space before id=" is load-bearing: attrs_s ends with one, and
            # without it the result is path="...gd"id="1_cs_player".
            new_s = "".join(' %s="%s"' % kv for kv in new_attrs.items()) + " "
            changed = True
            fixes.append((f, rid, path, correct))
            return head + new_s + 'id="%s"]' % rid

        new_text = RE_EXT.sub(repl, text)
        if changed and not check_only:
            write(f, new_text)

    mode = "would fix" if check_only else "fixed"
    print("%s %d stale ext_resource path(s):" % (mode, len(fixes)))
    for f, rid, old, new in fixes:
        print("    %s  %s" % (f, rid))
        print("        %s" % old)
        print("     -> %s" % new)

    if unresolvable:
        print()
        print("LEFT ALONE - uid could not be resolved to any file (%d):" % len(unresolvable))
        for row in unresolvable:
            print("    %s  %s  %s  %s" % row)

    if check_only and fixes:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
