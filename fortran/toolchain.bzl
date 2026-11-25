"""Fortran toolchain definitions."""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//fortran/private:macos.bzl", "macos_min_os_flags")
load("//fortran/private:providers.bzl", "FortranToolchainInfo")

def _make_runtime_ccinfo(ctx, cc_toolchain, feature_configuration, runtime_libs):
    """Create CcInfo for Fortran runtime libraries.

    This creates a CcInfo provider containing the Fortran runtime libraries
    (libflang_rt.runtime.a, libclang_rt.builtins.a) in a way that can be
    merged once into all fortran_library targets,

    Args:
        ctx: Rule context
        cc_toolchain: The C++ toolchain
        feature_configuration: Feature configuration from cc_common
        runtime_libs: List of runtime library files

    Returns:
        CcInfo provider containing the runtime libraries
    """
    if not runtime_libs:
        # No runtime libs - return empty CcInfo
        return CcInfo(
            compilation_context = cc_common.create_compilation_context(),
            # linker_inputs cant be None, hence the empty depset
            linking_context = cc_common.create_linking_context(linker_inputs = depset([])),
        )

    # Create library_to_link for each runtime library
    libraries_to_link = []
    for lib in runtime_libs:
        # Determine if this is a static or dynamic library based on extension
        # TODO: shared lib support
        is_static = lib.extension == "a" or lib.extension == "lib"
        is_dynamic = lib.extension in ["so", "dylib", "dll"]

        library_to_link = cc_common.create_library_to_link(
            actions = ctx.actions,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            static_library = lib if is_static else None,
            dynamic_library = lib if is_dynamic else None,
        )
        libraries_to_link.append(library_to_link)

    # Create linker_input with the runtime libraries
    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        libraries = depset(libraries_to_link),
        # NOTE: additional link flags (like -lpthread) should be in linker_flags if needed
    )

    # Create and return CcInfo
    linking_context = cc_common.create_linking_context(
        linker_inputs = depset([linker_input]),
    )

    return CcInfo(
        compilation_context = cc_common.create_compilation_context(),
        linking_context = linking_context,
    )

def _cc_macos_min_os_flags(ctx, cc_toolchain, feature_configuration):
    """the cc toolchain's own minimum macos version, so fortran objects match cc ones.

    it follows --macos_minimum_os (the default is the sdk version) and reads the
    same on every bazel version; [] off macos or when the cc toolchain sets none.
    """
    if not ctx.attr.macos_minimum_os_from_cc:
        return []
    if not ctx.target_platform_has_constraint(ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]):
        return []
    variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = [],
    )
    argv = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
        variables = variables,
    )
    return macos_min_os_flags(argv)

def _fortran_toolchain_impl(ctx):
    # Collect runtime library files from dependencies
    runtime_lib_files = []
    for dep in ctx.attr.runtime_libraries:
        runtime_lib_files.extend(dep[DefaultInfo].files.to_list())

    # Get C++ toolchain and create CcInfo for runtime libraries
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    # Create CcInfo for runtime libraries (kind of similar to rules_rust stdlib_linkflags)
    runtime_ccinfo = _make_runtime_ccinfo(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_configuration,
        runtime_libs = runtime_lib_files,
    )

    # first, so the toolchain's own flags and copts / linkopts can still override it
    min_os = _cc_macos_min_os_flags(ctx, cc_toolchain, feature_configuration)

    # -c fastbuild / dbg / opt; before compiler_flags so the toolchain's own flags and copts win
    mode_flags = {
        "dbg": ctx.attr.dbg_compiler_flags,
        "opt": ctx.attr.opt_compiler_flags,
    }.get(ctx.var.get("COMPILATION_MODE", "fastbuild"), ctx.attr.fastbuild_compiler_flags)

    toolchain_info = FortranToolchainInfo(
        compiler = ctx.file.compiler,
        linker = ctx.file.linker,
        archiver = ctx.file.archiver,
        compiler_flags = min_os + mode_flags + ctx.attr.compiler_flags,
        linker_flags = min_os + ctx.attr.linker_flags,
        preprocessor_flag = ctx.attr.preprocessor_flag,
        preprocessor_flags = ctx.attr.preprocessor_flags,
        module_flag_format = ctx.attr.module_flag_format,
        runtime_libraries = runtime_lib_files,
        runtime_ccinfo = runtime_ccinfo,
        all_files = depset(
            direct = [
                ctx.file.compiler,
                ctx.file.linker,
                ctx.file.archiver,
            ],
            transitive = [dep[DefaultInfo].files for dep in ctx.attr.tool_deps],
        ),
    )

    return [
        platform_common.ToolchainInfo(
            fortran = toolchain_info,
        ),
        toolchain_info,
    ]

fortran_toolchain = rule(
    implementation = _fortran_toolchain_impl,
    doc = """Defines a Fortran toolchain.
    
    This rule defines a Fortran toolchain with compiler, linker, and archiver
    along with default flags.
    
    Example:
        fortran_toolchain(
            name = "linux_toolchain",
            compiler = "@flang//:bin/flang-new",
            linker = "@flang//:bin/flang-new",
            archiver = "@flang//:bin/llvm-ar",
            compiler_flags = ["-Wall", "-O2"],
            linker_flags = ["-lm"],
        )
    """,
    attrs = {
        "archiver": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The archiver executable (typically 'ar').",
        ),
        "compiler": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The Fortran compiler executable.",
        ),
        "compiler_flags": attr.string_list(
            default = [],
            doc = "Default flags to pass to the compiler.",
        ),
        "dbg_compiler_flags": attr.string_list(
            default = ["-g"],
            doc = "Compiler flags added in the dbg compilation mode (-c dbg), ahead of compiler_flags.",
        ),
        "fastbuild_compiler_flags": attr.string_list(
            default = [],
            doc = "Compiler flags added in the fastbuild compilation mode (the default), ahead of compiler_flags.",
        ),
        "linker": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The linker executable.",
        ),
        "linker_flags": attr.string_list(
            default = [],
            doc = "Default flags to pass to the linker.",
        ),
        "macos_minimum_os_from_cc": attr.bool(
            default = True,
            doc = "On macOS targets, start compile and link flags with the cc toolchain's minimum macOS version " +
                  "(-mmacosx-version-min=), so Fortran and C objects agree. Turn off for a compiler without that flag.",
        ),
        "module_flag_format": attr.string(
            default = "-J{}",
            doc = "Format string for the flag that sets the module output directory. Use {} as placeholder for the path. " +
                  "The compiler must have such a flag: each source writes its .mod files into its own directory.",
        ),
        "opt_compiler_flags": attr.string_list(
            default = ["-O2"],
            doc = "Compiler flags added in the opt compilation mode (-c opt), ahead of compiler_flags.",
        ),
        "preprocessor_flag": attr.string(
            default = "-cpp",
            doc = "Flag to enable preprocessing (e.g., '-cpp' for gfortran/flang, '-fpp' for ifort).",
        ),
        "preprocessor_flags": attr.string_list(
            default = [],
            doc = "Default preprocessor flags (e.g., ['-D_OPENMP', '-DUSE_MPI']).",
        ),
        "runtime_libraries": attr.label_list(
            default = [],
            doc = "flang/clang runtime libraries (flang_rt, clang_rt) for C/Fortran interop.",
        ),
        "tool_deps": attr.label_list(
            allow_files = True,
            doc = "Additional tool dependencies (e.g., runtime libraries).",
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
        "_macos_constraint": attr.label(
            default = Label("@platforms//os:macos"),
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _fortran_toolchain_alias_impl(ctx):
    """Implementation of fortran_toolchain_alias."""
    toolchain = ctx.toolchains["@rules_fortran//fortran:toolchain_type"].fortran
    return [
        DefaultInfo(files = toolchain.all_files),
        toolchain,
    ]

fortran_toolchain_alias = rule(
    implementation = _fortran_toolchain_alias_impl,
    doc = """Creates an alias to the current Fortran toolchain.
    
    This can be used to access toolchain files or information.
    """,
    toolchains = ["@rules_fortran//fortran:toolchain_type"],
)
