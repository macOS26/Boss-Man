cmake_minimum_required(VERSION 3.16)
project(boss-man-web VERSION 1.0.0 LANGUAGES CXX)

# WebAssembly build of the Box2D + SFML C++ game. This folder is a SELF-CONTAINED
# FORK: it carries its OWN copy of src/ and assets/ so the VRSFML/web migration
# can be worked on freely without ever touching the shipping native project
# (../boss-man-box2d-sfml-cpp). Configure with the Emscripten toolchain
# (`emcmake cmake ...`).

if(NOT EMSCRIPTEN)
    message(FATAL_ERROR "Configure with the Emscripten toolchain: `emcmake cmake -S . -B build`")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(FORK_ROOT ${CMAKE_CURRENT_SOURCE_DIR}) # this fork's own src/ and assets/

include(FetchContent)

# --- SFML (web-capable fork) -------------------------------------------------
# Stock SFML has no Emscripten support, so use VRSFML (vittorioromeo), the
# Emscripten-ready fork. NOTE: this is the main integration point — its API has
# diverged from SFML 2.6 in places, so some calls in the shared src may need
# small adjustments (tracked in README.md).
FetchContent_Declare(sfml
    GIT_REPOSITORY https://github.com/vittorioromeo/VRSFML.git
    GIT_TAG master
)

# --- Box2D + nlohmann/json (pure C++, compile to wasm unchanged) -------------
FetchContent_Declare(box2d
    GIT_REPOSITORY https://github.com/erincatto/box2d.git
    GIT_TAG v2.4.1
)
set(BOX2D_BUILD_TESTBED OFF CACHE BOOL "" FORCE)
set(BOX2D_BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)

FetchContent_Declare(json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG v3.11.3
)

FetchContent_Declare(cmrc
    GIT_REPOSITORY https://github.com/vector-of-bool/cmrc.git
    GIT_TAG master
)

FetchContent_MakeAvailable(sfml box2d json cmrc)

# --- Game sources (this fork's own copy) -------------------------------------
# All .cpp in this fork's src/. The .mm (macOS) files are excluded by extension;
# EmojiTextureStub.cpp provides the no-op emoji rasterizer for web.
file(GLOB FORK_SOURCES CONFIGURE_DEPENDS ${FORK_ROOT}/src/*.cpp)

add_executable(boss-man-web ${FORK_SOURCES})
target_include_directories(boss-man-web PRIVATE ${FORK_ROOT}/src ${FORK_ROOT}/assets)
target_compile_definitions(boss-man-web PRIVATE _USE_MATH_DEFINES)

target_link_libraries(boss-man-web PRIVATE
    sfml-graphics sfml-window sfml-system sfml-audio
    box2d nlohmann_json::nlohmann_json)

# --- Embed assets (fonts, emoji, sounds, levels) into the wasm ---------------
file(GLOB_RECURSE EMBEDDED_ASSETS CONFIGURE_DEPENDS
    ${FORK_ROOT}/assets/fonts/*.ttf
    ${FORK_ROOT}/assets/emoji/*.png
    ${FORK_ROOT}/assets/images/*.png
    ${FORK_ROOT}/assets/voice/*.wav)
cmrc_add_resource_library(bm-assets
    ALIAS bm::assets
    NAMESPACE bmassets
    WHENCE ${FORK_ROOT}
    ${EMBEDDED_ASSETS}
    ${FORK_ROOT}/assets/levels.json)
target_link_libraries(boss-man-web PRIVATE bm::assets)

# --- Emscripten output: index.html + .js + .wasm -----------------------------
set_target_properties(boss-man-web PROPERTIES OUTPUT_NAME "index" SUFFIX ".html")
target_link_options(boss-man-web PRIVATE
    "-sWASM=1"
    "-sALLOW_MEMORY_GROWTH=1"
    "-sMIN_WEBGL_VERSION=2"
    "-sMAX_WEBGL_VERSION=2"
    "-sFULL_ES3=1"
    "-sASYNCIFY"
    "-sEXIT_RUNTIME=0")
# VRSFML supplies --shell-file pointing at <project>/emscripten/shell.html, so the
# page template lives there (no manual --shell-file flag needed).
