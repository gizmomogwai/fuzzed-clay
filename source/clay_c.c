// ImportC translation unit for Clay, raylib and stb_truetype: their APIs and the implementations of
// the two header-only libraries, Clay and stb_truetype.

// Nix's compiler wrapper turns on glibc's fortify headers, which use GCC builtins ImportC lacks.
#undef _FORTIFY_SOURCE

#define CLAY_IMPLEMENTATION
#include "clay.h"

#include <raylib.h>

#define STB_TRUETYPE_IMPLEMENTATION
#include <stb/stb_truetype.h>
