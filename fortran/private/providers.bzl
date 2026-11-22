"""Fortran providers."""

FortranInfo = provider(
    doc = """What a Fortran target offers to the compile step of its dependents.

    Only compile-time information lives here. Everything needed to link
    (archives, linkopts, the Fortran runtime) is carried by CcInfo, which
    fortran_library also provides.
    """,
    fields = {
        "transitive_modules": "depset of Files from this target and its transitive deps, each either a directory " +
                              "of .mod files or a single .mod file. " +
                              "A target with several sources gives one directory holding all its .mod files; " +
                              "a target with a single source gives the directory that source was compiled into; " +
                              "fortran_import gives its prebuilt .mod files. " +
                              "To compile against them, search each directory, and the directory of each file.",
    },
)

FortranToolchainInfo = provider(
    doc = "Information about the Fortran toolchain.",
    fields = {
        "all_files": "All toolchain files",
        "archiver": "The archiver executable (ar)",
        "compiler": "The Fortran compiler executable",
        "compiler_flags": "Default compiler flags",
        "linker": "The linker executable",
        "linker_flags": "Default linker flags",
        "module_flag_format": "Format string for module path flag (e.g., '-J{}', '-module {}')",
        "preprocessor_flag": "Flag to enable preprocessing (e.g., '-cpp', '-fpp')",
        "preprocessor_flags": "Default preprocessor flags (e.g., ['-D_OPENMP'])",
        "runtime_ccinfo": "CcInfo provider containing Fortran runtime libraries",
        "runtime_libraries": "flang/clang runtime libraries needed for C/Fortran interop",
    },
)
