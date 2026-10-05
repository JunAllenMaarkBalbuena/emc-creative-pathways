"""Reference-integrity and dead-code audit.

Three questions, all answered from the files on disk rather than from the
engine because the engine silently repairs some of these:

  1. Do every ext_resource path and uid:// reference resolve?
  2. Which .uid files exist with no matching file, and which uid:// strings
     point at nothing? Both are the "old uid collision" class of bug.
  3. Which scenes, scripts and assets are referenced by nothing at all?

uid references are checked separately from path references on purpose. A file
can be reachable by path while its uid is stale, and Godot resolves uid first,
so a stale uid is a real bug that a path-only check cannot see.
"""

import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RE_EXT = re.compile(r'\[ext_resource\s+type="([^"]+)"\s+([^\]]*?)id="([^"]+)"\]')
RE_ATTR = re.compile(r'(\w+)="([^"]*)"')
RE_SUB = re.compile(r'\[sub_resource\s+type="([^"]+)"\s+id="([^"]+)"\]')
RE_SUBREF = re.compile(r'SubResource\("([^"]+)"\)')
RE_EXTREF = re.compile(r'ExtResource\("([^"]+)"\)')
RE_UID = re.compile(r'uid://([a-z0-9]+)')


def rel(p):
    return "res://" + p.replace(os.sep, "/")


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def git(*args):
    r = subprocess.run(("git",) + args, cwd=ROOT, capture_output=True, text=True)
    return r.stdout.splitlines()


def tracked(ext):
    return [f for f in git("ls-files", "*" + ext) if f]


def uid_map():
    """uid string -> file path, built from the .uid sidecar files on disk."""
    out = {}
    for f in git("ls-files", "*.uid"):
        u = read(os.path.join(ROOT, f)).strip()
        if u:
            out[u.replace("uid://", "")] = f[:-4]  # strip .uid
    return out


def main():
    scenes = tracked(".tscn")
    resources = tracked(".tres")
    scripts = tracked(".gd")
    uids = uid_map()

    report = {
        "counts": {
            "tscn": len(scenes), "tres": len(resources),
            "gd": len(scripts), "uid_files": len(uids),
        },
        "ext_missing_path": [],
        "uid_unresolved": [],
        "sub_resource_unused": [],
        "orphan_uid_files": [],
        "unreferenced_scenes": [],
        "unreferenced_scripts": [],
        "unreferenced_assets": [],
    }

    # ---------------------------------------------------- 1 & 2: references
    used_uids = set()
    for f in scenes + resources:
        text = read(os.path.join(ROOT, f))
        local_uids = set(RE_UID.findall(text))

        declared = {}
        for m in RE_EXT.finditer(text):
            rid = m.group(3)
            attrs = dict(RE_ATTR.findall(m.group(2)))
            declared[rid] = attrs
            used_uids |= {u for u in RE_UID.findall(attrs.get("uid", ""))}

            path = attrs.get("path")
            if not path:
                continue
            disk = os.path.join(ROOT, path.replace("res://", "").replace("/", os.sep))
            if not os.path.isfile(disk):
                report["ext_missing_path"].append({
                    "file": f, "id": rid, "type": m.group(1),
                    "path": path, "why": "path does not exist on disk",
                })

        # sub_resources that nothing in the file points at
        sub_ids = {m.group(2) for m in RE_SUB.finditer(text)}
        used_subs = set(RE_SUBREF.findall(text))
        for sid in sorted(sub_ids - used_subs):
            report["sub_resource_unused"].append({"file": f, "id": sid})

        # any uid:// anywhere in the file that we have no file for
        for u in sorted(local_uids):
            if u not in uids:
                report["uid_unresolved"].append({"file": f, "uid": "uid://" + u})

    for f in scenes:
        text = read(os.path.join(ROOT, f))
        for m in RE_EXT.finditer(text):
            attrs = dict(RE_ATTR.findall(m.group(2)))
            u = attrs.get("uid", "")
            if u and u.replace("uid://", "") in uids:
                used_uids.add(u.replace("uid://", ""))

    for u, owner in sorted(uids.items()):
        if u not in used_uids:
            report["orphan_uid_files"].append({"uid": "uid://" + u, "file": owner})

    # ---------------------------------------------------- 3: dead code
    corpus = []
    for f in scenes + resources + scripts + tracked(".godot") + ["project.godot"]:
        corpus.append(read(os.path.join(ROOT, f)))
    for f in git("ls-files", "assets", "data"):
        if f.endswith((".import",)):
            continue
        corpus.append(read(os.path.join(ROOT, f)))
    blob = "\n".join(corpus)

    def referenced(target):
        name = os.path.basename(target)
        stem = os.path.splitext(name)[0]
        if (name in blob) or ('"%s"' % stem in blob) or ("'" + stem + "'" in blob):
            return True
        return False

    for f in scenes:
        if not referenced(f):
            report["unreferenced_scenes"].append(f)

    # a script counts as live if its path, its filename stem, or its class_name
    # is mentioned anywhere; class_name use does not need a path reference
    for f in scripts:
        text = read(os.path.join(ROOT, f))
        cn = re.search(r"^class_name\s+(\w+)", text, re.M)
        live = referenced(f)
        if not live and cn and cn.group(1) in blob:
            live = True
        if not live:
            report["unreferenced_scripts"].append(f)

    for f in tracked(".png") + tracked(".jpg") + tracked(".ogg") + tracked(".wav") + \
             tracked(".mp3") + tracked(".mp4") + tracked(".ogv") + tracked(".ttf") + \
             tracked(".svg") + tracked(".json"):
        if not referenced(f):
            report["unreferenced_assets"].append(f)

    out = os.path.join(ROOT, ".godot", "audit_refs.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)

    c = report["counts"]
    print("scenes %d | tres %d | scripts %d | .uid sidecars %d" % (
        c["tscn"], c["tres"], c["gd"], c["uid_files"]))
    print()
    for key in ("ext_missing_path", "uid_unresolved", "sub_resource_unused",
                "orphan_uid_files", "unreferenced_scenes", "unreferenced_scripts",
                "unreferenced_assets"):
        n = len(report[key])
        print("%-22s %d" % (key + ":", n))
        for item in report[key][:25]:
            if isinstance(item, dict):
                print("    " + "  ".join("%s=%s" % kv for kv in item.items()))
            else:
                print("    " + item)
    print()
    print("wrote", out)


if __name__ == "__main__":
    main()
