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
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":compile.bzl", "check_defines", "compile_fortran")
load(":providers.bzl", "FortranInfo")

def _fortran_library_impl(ctx):
    """Implementation function for fortran_library rule.

    Input: ctx.files.srcs (Fortran sources), ctx.attr.deps (fortran_library deps)
    Output: DefaultInfo (`*.a` + `*.mod`), FortranInfo, CcInfo
    """
    toolchain = ctx.toolchains["@rules_fortran//fortran:toolchain_type"].fortran

    # module directories of deps: sources that USE a module need its `*.mod`
    # file at compile time
    dep_modules = [dep[FortranInfo].transitive_modules for dep in ctx.attr.deps if FortranInfo in dep]
    modules_from_deps = depset(transitive = dep_modules)

    # Compile each source: `*.f90` -> `*.o` (always) + `*.mod` (if source defines a MODULE)
    # https://fortran-lang.org/learn/building_programs/include_files/#include-files-and-modules
    objects = []  # `*.o` files for archiving
    modules = []  # module directories for dependents, one per source (0 or more .mod files each)

    check_defines(ctx.files.srcs, ctx.attr.defines)
    for src in ctx.files.srcs:
        result = compile_fortran(
            ctx = ctx,
            toolchain = toolchain,
            src = src,
            modules = modules_from_deps,
            copts = ctx.attr.copts,
            defines = ctx.attr.defines,
            includes = ctx.attr.includes,
            hdrs = ctx.files.hdrs,
        )
        objects.append(result.object)
        modules.append(result.module)

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
    cc_infos = []

    if archive or ctx.attr.linkopts:
        # 1. create CcInfo for this library's archive and linkopts
        # linkopts ride in the linker input so they reach every transitive
        # consumer (fortran_binary, cc_binary), once per library
        libraries_to_link = []
        if archive:
            cc_toolchain = find_cc_toolchain(ctx)
            libraries_to_link.append(cc_common.create_library_to_link(
                actions = ctx.actions,
                feature_configuration = cc_common.configure_features(ctx = ctx, cc_toolchain = cc_toolchain),
                static_library = archive,
            ))
        linker_input = cc_common.create_linker_input(
            owner = ctx.label,
            libraries = depset(libraries_to_link),
            user_link_flags = ctx.attr.linkopts,
            # runtime libs are in toolchain, not here
        )
        linking_context = cc_common.create_linking_context(linker_inputs = depset([linker_input]))
        cc_infos.append(CcInfo(
            compilation_context = cc_common.create_compilation_context(),
            linking_context = linking_context,
        ))

    if archive:
        # 2. add toolchain runtime CcInfo (once, from toolchain)
        cc_infos.append(toolchain.runtime_ccinfo)

    # 3. collect and add CcInfo from dependencies
    for dep in ctx.attr.deps:
        if CcInfo in dep:
            cc_infos.append(dep[CcInfo])

    # 4. merge all CcInfos (or create empty if none)
    # always return CcInfo even for libraries with no sources. See: 500609c
    if cc_infos:
        merged = cc_common.merge_cc_infos(cc_infos = cc_infos)
        compilation_context = merged.compilation_context
        linking_context = merged.linking_context
    else:
        compilation_context = cc_common.create_compilation_context()
        linking_context = cc_common.create_linking_context(linker_inputs = depset([]))  # can't be Null, hence the empty depset

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
                transitive = dep_modules,
            ),
        ),
        CcInfo(
            compilation_context = compilation_context,
            linking_context = linking_context,
        ),
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
    attrs = {
        "copts": attr.string_list(
            doc = "Additional compiler options to pass to the Fortran compiler.",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Files needed at run time. Added to the runfiles of every binary or test that links this library.",
        ),
        "defines": attr.string_list(
            doc = "Preprocessor defines for .F files (e.g., ['_OPENMP', 'USE_MPI']).",
        ),
        "deps": attr.label_list(
            providers = [[FortranInfo], [CcInfo]],
            doc = "List of fortran_library or cc_library targets that this library depends on.",
        ),
        "hdrs": attr.label_list(
            allow_files = [".inc", ".mod"],
            doc = "Header/include files (.inc, .mod) for INCLUDE statements and pre-built modules.",
        ),
        "includes": attr.string_list(
            doc = "List of include directories to add to the compile line.",
        ),
        "linkopts": attr.string_list(
            doc = "Additional linker options (propagated to binaries).",
        ),
        "srcs": attr.label_list(
            allow_files = [".f", ".f90", ".f95", ".f03", ".f08", ".F", ".F90", ".F95", ".F03", ".F08"],
            doc = "List of Fortran source files to compile.",
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
