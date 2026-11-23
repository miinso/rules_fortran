"""Reads the minimum macOS version out of a cc toolchain's command line."""

_MIN_OS_PREFIXES = ("-mmacosx-version-min=", "-mmacos-version-min=")
_VERSION_CHARS = "0123456789."

def _triple_macos_version(triple):
    """"15.0" for arm64-apple-macosx15.0 (or macos15.0), else None."""
    parts = triple.split("-")
    if len(parts) < 3:
        return None
    os = parts[2]
    for prefix in ("macosx", "macos"):
        if os.startswith(prefix):
            rest = os[len(prefix):]
            version = ""
            for c in rest.elems():
                if c not in _VERSION_CHARS:
                    break
                version += c
            return version or None
    return None

def macos_min_os_flags(argv):
    """the cc toolchain's minimum macos version, as flags for flang.

    rules_cc's local toolchain says -mmacosx-version-min=X, apple_support's puts it
    in the triple (-target arm64-apple-macosxX). the last one on the line wins, as
    it does for clang.

    Args:
      argv: a cc compile command line.

    Returns:
      ["-mmacosx-version-min=X"], or [] when the command line sets no version.
    """
    found = None
    for i, arg in enumerate(argv):
        triple = None
        if arg.startswith(_MIN_OS_PREFIXES):
            found = arg.split("=", 1)[1] or found
        elif arg in ("-target", "--target") and i + 1 < len(argv):
            triple = argv[i + 1]
        elif arg.startswith("--target="):
            triple = arg[len("--target="):]
        if triple:
            found = _triple_macos_version(triple) or found
    return ["-mmacosx-version-min=" + found] if found else []
