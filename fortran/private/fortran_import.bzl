"""Brings Fortran code that was built outside of Bazel into the build.

A prebuilt Fortran library comes as `*.mod` files (what `USE` reads at compile
time) and an archive or shared library (what the linker reads). This rule
offers both to dependents the same way fortran_library does:
  - FortranInfo with the `*.mod` files
  - CcInfo with the library, the Fortran runtime and linkopts
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":cc_info.bzl", "library_cc_info")
load(":providers.bzl", "FortranInfo")

def _fortran_import_impl(ctx):
    toolchain = ctx.toolchains["@rules_fortran//fortran:toolchain_type"].fortran

    libraries = [
        f
        for f in [ctx.file.static_library, ctx.file.shared_library, ctx.file.interface_library]
        if f
    ]

    library = None
    if libraries:
        cc_toolchain = find_cc_toolchain(ctx)
        library = cc_common.create_library_to_link(
            actions = ctx.actions,
            feature_configuration = cc_common.configure_features(ctx = ctx, cc_toolchain = cc_toolchain),
            cc_toolchain = cc_toolchain,
            static_library = ctx.file.static_library,
            dynamic_library = ctx.file.shared_library,
            interface_library = ctx.file.interface_library,
            alwayslink = ctx.attr.alwayslink,
        )

    runfiles = ctx.runfiles(files = ctx.files.data).merge_all([
        target[DefaultInfo].default_runfiles
        for target in ctx.attr.deps + ctx.attr.data
    ])

    return [
        DefaultInfo(files = depset(ctx.files.modules + libraries), runfiles = runfiles),
        FortranInfo(
            transitive_modules = depset(
                direct = ctx.files.modules,
                transitive = [dep[FortranInfo].transitive_modules for dep in ctx.attr.deps if FortranInfo in dep],
            ),
        ),
        library_cc_info(ctx, toolchain, library),
    ]

fortran_import = rule(
    implementation = _fortran_import_impl,
    doc = """Imports a prebuilt Fortran library: its module files and its archive or shared library.

    Depend on it like on a fortran_library. Dependents can USE its modules and
    are linked against its library.

    Module files are not portable: a `.mod` file can only be read by the
    compiler (and usually the compiler version) that wrote it. Import module
    files that were written by the same flang the toolchain uses.

    Examples:
        fortran_import(
            name = "vendor",
            modules = glob(["include/*.mod"]),
            static_library = "lib/libvendor.a",
        )

        fortran_binary(
            name = "app",
            srcs = ["main.f90"],  # use vendor
            deps = [":vendor"],
        )
    """,
    attrs = {
        "alwayslink": attr.bool(
            default = False,
            doc = "If True, every object of static_library is linked into any binary that depends on it, " +
                  "even objects nothing references.",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Files needed at run time. Added to the runfiles of every binary or test that links this library.",
        ),
        "deps": attr.label_list(
            providers = [[FortranInfo], [CcInfo]],
            doc = "Targets the prebuilt library needs itself: their modules are passed on to dependents " +
                  "together with this target's, and they are linked after it.",
        ),
        "interface_library": attr.label(
            allow_single_file = True,
            doc = "The file to link against when shared_library cannot be linked directly, " +
                  "e.g. the import library (.lib) of a DLL on Windows.",
        ),
        "linkopts": attr.string_list(
            doc = "Additional linker options (propagated to binaries).",
        ),
        "modules": attr.label_list(
            allow_files = [".mod", ".smod"],
            doc = "Prebuilt module files. Dependents, direct and transitive, can USE the modules they describe.",
        ),
        "shared_library": attr.label(
            allow_single_file = True,
            doc = "A prebuilt shared library (.so, .dylib, .dll). It is used when there is no static_library, " +
                  "and is then shipped in the runfiles of every executable linking it. " +
                  "On macOS its install name has to start with `@rpath/`.",
        ),
        "static_library": attr.label(
            allow_single_file = [".a", ".lib"],
            doc = "A prebuilt static library.",
        ),
        # https://bazel.build/versions/8.4.0/configure/integrate-cpp
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    toolchains = [
        "@rules_fortran//fortran:toolchain_type",
        "@bazel_tools//tools/cpp:toolchain_type",  # to create CcInfo
    ],
    fragments = ["cpp"],  # `cc_common.configure_features()` requires this fragment thing
)
