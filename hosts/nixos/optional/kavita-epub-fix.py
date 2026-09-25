"""Repair EPUBs that Kavita cannot open, in place.

Kavita parses EPUBs with VersOne.Epub on .NET, whose XML reader rejects any
document that declares `<?xml version="1.1"?>` ("Version number '1.1' is
invalid"). Other readers accept those files, so the problem shows only as a
book that never appears in Kavita. This rewrites the declaration to 1.0; the
content of the book does not change.

Usage: kavita-epub-fix <state-dir> <root> [<root> ...]
"""

import os
import re
import shutil
import sys
import time
import zipfile

XML_EXTS = (".opf", ".ncx", ".xml", ".xhtml", ".html", ".htm", ".svg")
DECL_11 = re.compile(rb"""^(\xef\xbb\xbf)?(\s*<\?xml[^>]*?version\s*=\s*["'])1\.1(["'])""")

# A file this new may still be arriving (a Chaptarr import over NFS, a copy
# in progress). Leave it for the next run rather than read half a zip.
MIN_AGE_SECONDS = 60


def needs_fix(zf):
    names = []
    for info in zf.infolist():
        if not info.filename.lower().endswith(XML_EXTS):
            continue
        with zf.open(info) as f:
            head = f.read(200)
        if DECL_11.match(head):
            names.append(info.filename)
    return names


def rewrite(path, bad, state_dir, root):
    st = os.stat(path)
    tmp = os.path.join(os.path.dirname(path), "." + os.path.basename(path) + ".fixing")
    with zipfile.ZipFile(path) as src, zipfile.ZipFile(tmp, "w") as dst:
        # Keep the original order: the EPUB spec requires `mimetype` first,
        # stored without compression, and copying each ZipInfo keeps that.
        for info in src.infolist():
            data = src.read(info)
            if info.filename in bad:
                data = DECL_11.sub(rb"\g<1>\g<2>1.0\g<3>", data, count=1)
            dst.writestr(info, data)

    # The original goes outside /srv/kavita, so Kavita never indexes it twice.
    backup = os.path.join(state_dir, "originals", os.path.relpath(path, root))
    os.makedirs(os.path.dirname(backup), exist_ok=True)
    shutil.copy2(path, backup)

    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, st.st_mode & 0o7777)
    os.replace(tmp, path)
    print(f"fixed XML 1.1 declaration in {', '.join(bad)}: {path}", flush=True)


def main():
    state_dir, roots = sys.argv[1], sys.argv[2:]
    now = time.time()
    fixed = failed = 0
    for root in roots:
        for dirpath, _, files in os.walk(root):
            for name in files:
                if not name.lower().endswith(".epub"):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    if now - os.stat(path).st_mtime < MIN_AGE_SECONDS:
                        continue
                    with zipfile.ZipFile(path) as zf:
                        bad = needs_fix(zf)
                    if bad:
                        rewrite(path, bad, state_dir, root)
                        fixed += 1
                except (zipfile.BadZipFile, OSError, KeyError) as e:
                    # One broken file must not stop the rest of the library.
                    print(f"skipped {path}: {e}", file=sys.stderr, flush=True)
                    failed += 1
    print(f"done: {fixed} fixed, {failed} skipped", flush=True)


if __name__ == "__main__":
    main()
