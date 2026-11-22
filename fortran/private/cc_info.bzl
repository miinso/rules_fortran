"""The CcInfo of a target that offers a library: fortran_library and fortran_import."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def library_cc_info(ctx, toolchain, library):
    """CcInfo for a target with at most one library of its own, plus linkopts and deps.

    This is what lets C/C++ rules (cc_binary, cc_library) and the Fortran
    executables link the target.

    Args:
        ctx: Rule context, with `linkopts` and `deps` attrs
        toolchain: FortranToolchainInfo provider
        library: the target's LibraryToLink, or None when it has nothing to link

    Returns:
        CcInfo. Never None, also for a target with no library (see 500609c)
    """
    cc_infos = []

    if library or ctx.attr.linkopts:
        # 1. this target's library and linkopts
        # linkopts ride in the linker input so they reach every transitive
        # consumer (fortran_binary, cc_binary), once per library
        linker_input = cc_common.create_linker_input(
            owner = ctx.label,
            libraries = depset([library] if library else []),
            user_link_flags = ctx.attr.linkopts,
            # runtime libs are in toolchain, not here
        )
        cc_infos.append(CcInfo(
            compilation_context = cc_common.create_compilation_context(),
            linking_context = cc_common.create_linking_context(linker_inputs = depset([linker_input])),
        ))

    if library:
        # 2. the Fortran runtime that library needs (once, from toolchain)
        cc_infos.append(toolchain.runtime_ccinfo)

    # 3. CcInfo from dependencies
    for dep in ctx.attr.deps:
        if CcInfo in dep:
            cc_infos.append(dep[CcInfo])

    if not cc_infos:
        return CcInfo(
            compilation_context = cc_common.create_compilation_context(),
            linking_context = cc_common.create_linking_context(linker_inputs = depset([])),  # can't be Null, hence the empty depset
        )
    return cc_common.merge_cc_infos(cc_infos = cc_infos)
