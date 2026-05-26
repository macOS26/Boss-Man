cmake_minimum_required(VERSION 3.16)
project(boss-man-pc VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Objective-C++ (CoreText emoji + native fullscreen) on macOS. Enabled up front so
# reconfigures stay stable.
if(APPLE)
    enable_language(OBJCXX)
endif()

# Dependencies via FetchContent
include(FetchContent)

# SFML
find_package(SFML 2.6 COMPONENTS graphics window system audio network QUIET)
if(NOT SFML_FOUND)
    FetchContent_Declare(sfml
        GIT_REPOSITORY https://github.com/SFML/SFML.git
        GIT_TAG 2.6.x
    )
    FetchContent_MakeAvailable(sfml)
    # SFML hardcodes highDpi:NO on macOS, so it renders at 1x and the OS upscales to
    # Retina (blurry/jagged). Patch it on to render at native backing resolution.
    # (SFML exposes no API for this.) Idempotent; macOS-only file.
    if(APPLE)
        execute_process(COMMAND sed -i "" "s/m_highDpi = NO;/m_highDpi = YES;/g; s/highDpi:NO];/highDpi:YES];/g"
            "${sfml_SOURCE_DIR}/src/SFML/Window/OSX/SFWindowController.mm")
    endif()
endif()

# Box2D
find_package(Box2D QUIET)
if(NOT Box2D_FOUND)
    FetchContent_Declare(box2d
        GIT_REPOSITORY https://github.com/erincatto/box2d.git
        GIT_TAG v2.4.1
    )
    set(BOX2D_BUILD_TESTBED OFF CACHE BOOL "" FORCE)
    set(BOX2D_BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(box2d)
endif()

# nlohmann/json
FetchContent_Declare(json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG v3.11.3
)
FetchContent_MakeAvailable(json)

# Source files
set(SOURCES
    src/main.cpp
    src/Game.cpp
    src/GridMap.cpp
    src/Pathfinder.cpp
    src/WorkerController.cpp
    src/BossController.cpp
    src/BossAI.cpp
    src/MazeRenderer.cpp
    src/PixelPersonRenderer.cpp
    src/EmojiText.cpp
    src/TitleScreen.cpp
    src/HUDRenderer.cpp
    src/ScorePopup.cpp
    src/PhysicsWorld.cpp
    src/ContactRouter.cpp
    src/RoundState.cpp
    src/SoundManager.cpp
    src/LevelLoader.cpp
    src/InputController.cpp
    src/TravelerSpawner.cpp
    src/WaterDroplet.cpp
    src/WaterGunState.cpp
)

# Platform emoji rasterizer: CoreText on macOS, no-op stub elsewhere
if(APPLE)
    list(APPEND SOURCES src/EmojiTexture.mm src/MacWindow.mm)
else()
    list(APPEND SOURCES src/EmojiTextureStub.cpp)
endif()

add_executable(boss-man-pc ${SOURCES})

if(APPLE)
    target_link_libraries(boss-man-pc PRIVATE
        "-framework AppKit" "-framework Foundation" "-framework CoreGraphics")
endif()

target_include_directories(boss-man-pc PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/assets
)

target_link_libraries(boss-man-pc PRIVATE
    sfml-graphics
    sfml-window
    sfml-system
    sfml-audio
    sfml-network
    box2d
    nlohmann_json::nlohmann_json
)

# Copy assets to build directory
file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/assets DESTINATION ${CMAKE_BINARY_DIR})