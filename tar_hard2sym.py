#!/usr/bin/env python3
"""Rewrite a tar archive so every hardlink entry becomes a symlink.

Usage: tar_hard2sym.py INPUT.tar[.gz|.bz2|.xz] OUTPUT.tar[.gz|.bz2|.xz]

Hardlink targets in tar are stored relative to the archive root, but symlink
targets are resolved relative to the link's own directory, so the target is
rewritten as a relative path. Streams the archive, so memory use stays low.
"""
import posixpath
import sys
import tarfile


def compression_mode(path):
    for ext, mode in ((".gz", "gz"), (".tgz", "gz"), (".bz2", "bz2"),
                      (".xz", "xz")):
        if path.endswith(ext):
            return mode
    return ""


def convert(src_path, dst_path):
    count = 0
    with tarfile.open(src_path, "r|*") as src, \
         tarfile.open(dst_path, "w|" + compression_mode(dst_path),
                      format=tarfile.PAX_FORMAT) as dst:
        for m in src:
            if m.islnk():
                link_dir = posixpath.dirname(posixpath.normpath(m.name)) or "."
                target = posixpath.normpath(m.linkname)
                m.type = tarfile.SYMTYPE
                m.linkname = posixpath.relpath(target, link_dir)
                m.size = 0
                # Stale pax records from the source (long linkpath, size)
                # would override the rewritten values in the output.
                m.pax_headers.pop("linkpath", None)
                m.pax_headers.pop("size", None)
                dst.addfile(m)
                count += 1
            elif m.isreg():
                dst.addfile(m, src.extractfile(m))
            else:
                dst.addfile(m)
    return count


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    n = convert(sys.argv[1], sys.argv[2])
    print(f"Converted {n} hardlink(s) to symlink(s).")


if __name__ == "__main__":
    main()
