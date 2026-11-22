"""Compiles Fortran sources into a static library.

NOTE: Fortran sources that define a MODULE produce `*.mod` files (interface metadata).
Sources that USE a module need the corresponding `*.mod` file to compile.

This rule:
  - Compiles Fortran sources to `*.o` (always) + `*.mod` (only if MODULE defined)
  - Archives `*.o` into `*.a`
  - Provides `*.mod` directories to dependents via FortranInfo
  - Provides CcInfo with `*.a` + runtime library paths for C/C++ interop
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(":cc_info.bzl", "library_cc_info")
load(":compile.bzl", "COMPILE_ATTRS", "MODULE_ORDER_ATTRS", "compile_sources")
load(":providers.bzl", "FortranInfo")

def _fortran_library_impl(ctx):
    """Implementation function for fortran_library rule.

    Input: ctx.files.srcs (Fortran sources), ctx.attr.deps (fortran_library deps)
    Output: DefaultInfo (`*.a` + `*.mod`), FortranInfo, CcInfo
    """
    toolchain = ctx.toolchains["@rules_fortran//fortran:toolchain_type"].fortran

    compiled = compile_sources(ctx, toolchain)
    objects = compiled.objects  # `*.o` files for archiving
    modules = compiled.modules  # module directories for dependents (0 or more .mod files each)

    # Archive compiled objects into static library (`*.a` file)
    archive = None
    if objects:
        archive = ctx.actions.declare_file("lib{}.a".format(ctx.label.name))

        # wrap (possibly long) arguments into a file
        # https://bazel.build/rules/lib/builtins/Args#use_param_file
        args = ctx.actions.args()
        args.add("rcs")
        args.add(archive.path)
        for obj in objects:
            args.add(obj)
        args.use_param_file("@%s", use_always = True)
        args.set_param_file_format("multiline")

        ctx.actions.run(
            executable = toolchain.archiver,
            arguments = [args],
            inputs = objects,
            outputs = [archive],
            mnemonic = "FortranArchive",
            progress_message = "Creating Fortran archive {}".format(archive.short_path),
        )

    # DefaultInfo: just a list of files built when building this target (`*.a` + `*.mod` directories)
    output_files = ([archive] + modules) if archive else modules

    # CcInfo: Allows C/C++ rules (cc_binary, cc_library) to link against this Fortran library
    library = None
    if archive:
        cc_toolchain = find_cc_toolchain(ctx)
        library = cc_common.create_library_to_link(
            actions = ctx.actions,
            feature_configuration = cc_common.configure_features(ctx = ctx, cc_toolchain = cc_toolchain),
            static_library = archive,
            alwayslink = ctx.attr.alwayslink,
        )

    # runfiles: own data + whatever deps and data targets need at run time,
    # so a binary linking this library gets them too
    runfiles = ctx.runfiles(files = ctx.files.data).merge_all([
        target[DefaultInfo].default_runfiles
        for target in ctx.attr.deps + ctx.attr.data
    ])

    return [
        DefaultInfo(files = depset(output_files), runfiles = runfiles),
        FortranInfo(
            transitive_modules = depset(
                direct = modules,
                transitive = compiled.dep_modules,
            ),
        ),
        library_cc_info(ctx, toolchain, library),
    ]

fortran_library = rule(
    implementation = _fortran_library_impl,
    doc = """Compiles Fortran sources into a static library.

    Examples:
        fortran_library(
            name = "math",
            srcs = ["module.f90", "utils.f90"],
        )

        fortran_library(
            name = "advanced",
            srcs = ["solver.f90"],
            deps = [":math"],
            copts = ["-O2"],
        )

        fortran_library(
            name = "all",
            deps = [":math", ":advanced"],
        )
    """,
    attrs = COMPILE_ATTRS | MODULE_ORDER_ATTRS | {
        "alwayslink": attr.bool(
            default = False,
            doc = "If True, every object of this library is linked into any binary that depends on it, " +
                  "even objects nothing references. Use it for code that is only reached indirectly " +
                  "(looked up by name, weakly referenced), and for BLOCK DATA units that only initialize a " +
                  "COMMON block, which not every linker pulls out of an archive.",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Files needed at run time. Added to the runfiles of every binary or test that links this library.",
        ),
        "linkopts": attr.string_list(
            doc = "Additional linker options (propagated to binaries).",
        ),
        # https://bazel.build/versions/8.4.0/configure/integrate-cpp
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    toolchains = [
        "@rules_fortran//fortran:toolchain_type",
        "@bazel_tools//tools/cpp:toolchain_type",  # to create CcInfo (not just reading it like in fortran_binary)
    ],
    fragments = ["cpp"],  # `cc_common.configure_features()` requires this fragment thing
)
