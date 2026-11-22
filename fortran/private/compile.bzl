"""Fortran compilation: the attrs and actions every rule with srcs shares."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":providers.bzl", "FortranInfo")

CompileResultInfo = provider(
    "Compilation outputs for a single Fortran source file.",
    fields = ["object", "module"],
)

# the one place source extensions are listed (without the dot, as File.extension gives them)
_FIXED_FORM_EXTENSIONS = ["f", "F"]
_FREE_FORM_EXTENSIONS = ["f90", "f95", "f03", "f08", "F90", "F95", "F03", "F08"]
_PREPROCESSED_EXTENSIONS = ["F", "F90", "F95", "F03", "F08"]

# attrs of every rule that compiles sources (fortran_library, fortran_binary, fortran_test)
COMPILE_ATTRS = {
    "copts": attr.string_list(
        doc = "Additional compiler options.",
    ),
    "defines": attr.string_list(
        doc = "Preprocessor defines (e.g., ['_OPENMP', 'USE_MPI']). They apply to this target's " +
              "preprocessed sources only, i.e. those with an uppercase extension (.F, .F90, ...).",
    ),
    "deps": attr.label_list(
        providers = [[FortranInfo], [CcInfo]],
        doc = "List of fortran_library or cc_library targets this target depends on. " +
              "Their modules are visible to srcs, and they are linked into the final executable.",
    ),
    "hdrs": attr.label_list(
        allow_files = [".inc", ".mod"],
        doc = "Header/include files (.inc, .mod) for INCLUDE statements and pre-built modules. " +
              "Used by this target's srcs only; they are not passed on to dependents.",
    ),
    "includes": attr.string_list(
        doc = "List of include directories, relative to this package, to add to the compile line. " +
              "They apply to this target only.",
    ),
    "srcs": attr.label_list(
        allow_files = ["." + ext for ext in _FIXED_FORM_EXTENSIONS + _FREE_FORM_EXTENSIONS],
        doc = "List of Fortran source files to compile. Each source is compiled on its own, so a " +
              "source cannot USE a module defined by another source of the same target; put the " +
              "module in a separate fortran_library and depend on it.",
    ),
}

def _is_free_form(src):
    """Check if source file is free-form Fortran."""
    return src.extension in _FREE_FORM_EXTENSIONS

def _needs_preprocessing(src):
    """Check if source file needs preprocessing."""
    return src.extension in _PREPROCESSED_EXTENSIONS

def _output_stem(ctx, src):
    """Package-relative output stem for a source, e.g. `sub/util.f90` -> `sub/util_f90`.

    keeps the source dir so same-basename srcs in one target dont collide.
    """
    path = src.short_path
    prefix = ctx.label.package + "/" if ctx.label.package else ""
    if path.startswith("../"):
        # external repo file: `../repo/pkg/file` -> `repo/pkg/file`
        path = path[len("../"):]
        prefix = ctx.label.workspace_root[len("external/"):] + "/" + prefix
    if path.startswith(prefix):
        # src lives under this target's package
        path = path[len(prefix):]
    dirname, sep, basename = path.rpartition("/")
    return dirname + sep + basename.replace(".", "_")

def check_defines(srcs, defines):
    """Fails when defines are set but no source would see them (see #14).

    Only sources with an uppercase extension are preprocessed. A target may
    mix both kinds; the defines then apply to the preprocessed ones.

    Args:
        srcs: list of source Files of the target
        defines: the target's defines
    """
    if defines and srcs and not [src for src in srcs if _needs_preprocessing(src)]:
        fail(
            "defines = {} specified but no source is preprocessed. ".format(defines) +
            "Use an uppercase extension (.F90, .F95, etc.) on the sources that need them.",
        )

def compile_fortran(ctx, toolchain, src, modules, copts, defines = [], includes = [], hdrs = []):
    """Compile a single Fortran source file.

    Args:
        ctx: Rule context
        toolchain: FortranToolchainInfo provider
        src: Source file to compile
        modules: depset of module directories from deps (FortranInfo.transitive_modules)
        copts: Additional compilation options
        defines: Preprocessor defines (e.g., ['_OPENMP', 'USE_MPI'])
        includes: List of include directories to add to compile line
        hdrs: Header/include files to make available in sandbox

    Returns:
        CompileResultInfo with object and module files
    """

    # Declare output files
    src_base = _output_stem(ctx, src)
    obj = ctx.actions.declare_file(
        "{}_objs/{}.o".format(ctx.label.name, src_base),
    )

    # Declare a directory for module outputs (one per source file)
    # This allows 0 or more .mod files to be created
    module_output_dir = ctx.actions.declare_directory(
        "{}_modules/{}".format(ctx.label.name, src_base),
    )

    # Build arguments
    args = ctx.actions.args()

    # Compiler flags
    args.add_all(toolchain.compiler_flags)
    args.add_all(copts)

    # Free-form or fixed-form
    if _is_free_form(src):
        args.add("-ffree-form")
    else:
        args.add("-ffixed-form")

    # Preprocessing
    if _needs_preprocessing(src):
        # Add preprocessor enable flag (e.g., -cpp or -fpp)
        args.add(toolchain.preprocessor_flag)

        # Add toolchain-level preprocessor flags
        args.add_all(toolchain.preprocessor_flags)

        # Add target-specific preprocessor defines.
        # sources that are not preprocessed get none; check_defines() rejects
        # a target where that leaves the defines unused
        for define in defines:
            args.add("-D" + define)

    # Module output directory - where this compilation writes .mod files
    args.add(toolchain.module_flag_format.format(module_output_dir.path))

    # Module search paths from dependencies.
    # the depset is expanded at execution time, so a large dependency graph
    # is not flattened once per source during analysis
    args.add_all(modules, format_each = "-I%s", expand_directories = False)

    # Include directories (resolved relative to package, like rules_cc)
    # Validate against "." and ".." to protect workspace (see cc_helper.bzl#L827-L833)
    package = ctx.label.package
    for inc in includes:
        if ".." in inc:
            fail("includes cannot contain '..': " + inc)
        if package:
            inc_path = package + "/" + inc
        else:
            inc_path = inc
        if inc_path == "." or inc_path == "":
            fail("includes resolves to workspace root, which would expose the entire workspace")

        # targets in an external repo live under external/<repo> in the execroot
        if ctx.label.workspace_root:
            inc_path = ctx.label.workspace_root + "/" + inc_path
        args.add("-I" + inc_path)

    # Compile command
    args.add("-c")
    args.add(src.path)
    args.add("-o", obj.path)
    # args.add("-###")

    # Use param file to avoid "Argument list too long" errors on Windows/Linux
    # This is especially important for large projects like LAPACK with thousands of module directories
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")

    # Run compilation
    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = [args],
        inputs = depset(
            direct = [src] + hdrs,
            transitive = [modules, toolchain.all_files],
        ),
        outputs = [obj, module_output_dir],
        mnemonic = "FortranCompile",
        progress_message = "Compiling Fortran {}".format(src.short_path),
    )

    return CompileResultInfo(
        object = obj,
        module = module_output_dir,  # Return directory instead of specific file
    )

def compile_sources(ctx, toolchain):
    """Compiles all srcs of a target that has COMPILE_ATTRS.

    Args:
        ctx: Rule context
        toolchain: FortranToolchainInfo provider

    Returns:
        struct with
          objects: list of object files, one per source
          modules: list of module directories, one per source
          dep_modules: list of the deps' transitive module depsets
    """

    # sources that USE a module need its `*.mod` file at compile time
    dep_modules = [dep[FortranInfo].transitive_modules for dep in ctx.attr.deps if FortranInfo in dep]
    modules_from_deps = depset(transitive = dep_modules)

    check_defines(ctx.files.srcs, ctx.attr.defines)

    # `*.f90` -> `*.o` (always) + `*.mod` (if the source defines a MODULE)
    # https://fortran-lang.org/learn/building_programs/include_files/#include-files-and-modules
    objects = []
    modules = []
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

    return struct(
        objects = objects,
        modules = modules,
        dep_modules = dep_modules,
    )
