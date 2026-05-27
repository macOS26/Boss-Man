cmake_minimum_required(VERSION 3.16)
project(boss-man-web VERSION 1.0.0 LANGUAGES CXX)

# Self-contained WEB FORK of the game. Two build modes from one codebase:
#   * DESKTOP (default): real SFML 2.6 — for building & TESTING on this Mac.
#   * WEB (emcmake): is-Engine's SDL2 wrapper provides the sf:: API on SDL2,
#     compiled to WebAssembly. Assets are files (preloaded); SFX are pre-rendered
#     wavs (the wrapper has no loadFromMemory/loadFromSamples).

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(FORK_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

include(FetchContent)

# Box2D + nlohmann/json (both modes, pure C++)
FetchContent_Declare(box2d GIT_REPOSITORY https://github.com/erincatto/box2d.git GIT_TAG v2.4.1)
set(BOX2D_BUILD_TESTBED OFF CACHE BOOL "" FORCE)
set(BOX2D_BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)
FetchContent_Declare(json GIT_REPOSITORY https://github.com/nlohmann/json.git GIT_TAG v3.11.3)
FetchContent_MakeAvailable(box2d json)

file(GLOB FORK_SOURCES CONFIGURE_DEPENDS ${FORK_ROOT}/src/*.cpp)  # includes EmojiTextureStub.cpp

if(APPLE AND NOT EMSCRIPTEN)
    # Desktop macOS test build: use the real CoreText emoji + native window code.
    list(REMOVE_ITEM FORK_SOURCES ${FORK_ROOT}/src/EmojiTextureStub.cpp)
    enable_language(OBJCXX)
    list(APPEND FORK_SOURCES ${FORK_ROOT}/src/EmojiTexture.mm ${FORK_ROOT}/src/MacWindow.mm)
endif()

if(EMSCRIPTEN)
    # is-Engine SDL2 wrapper implementation (the sf:: API on SDL2).
    list(APPEND FORK_SOURCES ${FORK_ROOT}/isengine/isEngineSDLWrapper.cpp)
    list(APPEND FORK_SOURCES ${FORK_ROOT}/isengine/isEngineWrapper.cpp)
endif()

add_executable(boss-man-web ${FORK_SOURCES})
target_include_directories(boss-man-web PRIVATE ${FORK_ROOT}/src)
target_compile_definitions(boss-man-web PRIVATE _USE_MATH_DEFINES)
target_link_libraries(boss-man-web PRIVATE box2d nlohmann_json::nlohmann_json)

if(EMSCRIPTEN)
    # ---- WEB: SDL2 wrapper + WebAssembly ----
    target_compile_definitions(boss-man-web PRIVATE IS_ENGINE_HTML_5)
    # sfml-compat first: routes <SFML/Graphics.hpp> etc. to the SDL2 wrapper.
    target_include_directories(boss-man-web BEFORE PRIVATE ${FORK_ROOT}/sfml-compat ${FORK_ROOT}/isengine)
    set(SDL_FLAGS "-sUSE_SDL=2" "-sUSE_SDL_IMAGE=2" "-sUSE_SDL_TTF=2" "-sUSE_SDL_MIXER=2")
    target_compile_options(boss-man-web PRIVATE ${SDL_FLAGS})
    target_link_options(boss-man-web PRIVATE ${SDL_FLAGS}
        "SHELL:-sSDL2_IMAGE_FORMATS=[png]"
        "-sALLOW_MEMORY_GROWTH=1"
        "SHELL:--preload-file ${FORK_ROOT}/assets@/assets")
    set_target_properties(boss-man-web PROPERTIES OUTPUT_NAME "index" SUFFIX ".html")
else()
    # ---- DESKTOP: real SFML 2.6 (build + test on this machine) ----
    find_package(SFML 2.6 COMPONENTS graphics window system audio QUIET)
    if(NOT SFML_FOUND)
        FetchContent_Declare(sfml GIT_REPOSITORY https://github.com/SFML/SFML.git GIT_TAG 2.6.x)
        FetchContent_MakeAvailable(sfml)
        if(APPLE)
            execute_process(COMMAND sed -i "" "s/m_highDpi = NO;/m_highDpi = YES;/g; s/highDpi:NO];/highDpi:YES];/g"
                "${sfml_SOURCE_DIR}/src/SFML/Window/OSX/SFWindowController.mm")
        endif()
    endif()
    target_link_libraries(boss-man-web PRIVATE sfml-graphics sfml-window sfml-system sfml-audio)
    if(APPLE)
        target_link_libraries(boss-man-web PRIVATE
            "-framework AppKit" "-framework Foundation" "-framework CoreGraphics")
    endif()
    # Assets read from disk relative to the working dir; copy them next to the binary.
    file(COPY ${FORK_ROOT}/assets DESTINATION ${CMAKE_BINARY_DIR})
endif()
