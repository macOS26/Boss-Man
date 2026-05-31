cmake_minimum_required(VERSION 3.16)
# Minimum macOS the universal build targets, so it runs on systems older than
# the build SDK. Set before project() so SFML/Box2D (FetchContent) inherit it.
if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.5" CACHE STRING "Minimum macOS version")
endif()
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

# Android has no static-SFML support and the game ships as a NativeActivity .so,
# so force shared libs there (Gradle packages every built .so into the APK).
if(ANDROID)
    set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
endif()

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

# CMRC — compiles read-only assets into the binary as static data
FetchContent_Declare(cmrc
    GIT_REPOSITORY https://github.com/vector-of-bool/cmrc.git
    GIT_TAG master
)
FetchContent_MakeAvailable(cmrc)

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
    src/LevelStore.cpp
    src/LevelEditor.cpp
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
    src/Assets.cpp
)

# Platform emoji rasterizer: CoreText on macOS, no-op stub elsewhere
if(APPLE)
    list(APPEND SOURCES src/EmojiTexture.mm src/MacWindow.mm)
else()
    list(APPEND SOURCES src/EmojiTextureStub.cpp)
endif()

# macOS app icon — bundled into boss-man-pc.app/Contents/Resources so Finder and
# the Dock show it (CFBundleIconFile = AppIcon).
if(APPLE)
    set(MACOSX_APP_ICON ${CMAKE_CURRENT_SOURCE_DIR}/resources/macos/AppIcon.icns)
    set_source_files_properties(${MACOSX_APP_ICON} PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources")
    list(APPEND SOURCES ${MACOSX_APP_ICON})
endif()

# Windows executable icon (Explorer/taskbar) via a compiled .rc resource. The
# .rc references AppIcon.ico in the same directory.
if(WIN32)
    list(APPEND SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/resources/windows/app.rc)
endif()

# Android: the game is a shared lib the NativeActivity loads (android.app.lib_name
# = sfml-game); everywhere else it's a normal executable.
if(ANDROID)
    add_library(boss-man-pc SHARED ${SOURCES})
    set_target_properties(boss-man-pc PROPERTIES OUTPUT_NAME "sfml-game")
    # sfml-main supplies ANativeActivity_onCreate (which calls our main()).
    target_link_libraries(boss-man-pc PRIVATE sfml-main android log EGL GLESv1_CM OpenSLES)
else()
    add_executable(boss-man-pc ${SOURCES})
    # Per-platform output names: Boss-Man-mac (.app), Boss-Man.exe, Boss-Man (Linux).
    if(APPLE)
        set(BM_OUTPUT_NAME "Boss-Man-mac")
    else()
        set(BM_OUTPUT_NAME "Boss-Man") # Boss-Man.exe on Windows, Boss-Man on Linux
    endif()
    set_target_properties(boss-man-pc PROPERTIES OUTPUT_NAME "${BM_OUTPUT_NAME}")
endif()

if(APPLE)
    set_target_properties(boss-man-pc PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "Boss-Man"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.starplayrx.boss-man"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_ICON_FILE "AppIcon")
    target_link_libraries(boss-man-pc PRIVATE
        "-framework AppKit" "-framework Foundation" "-framework CoreGraphics")
endif()

if(WIN32)
    # GUI app (no console window). sfml-main provides WinMain, which calls main().
    set_target_properties(boss-man-pc PROPERTIES WIN32_EXECUTABLE TRUE)
    target_link_libraries(boss-man-pc PRIVATE sfml-main)
    if(MSVC)
        # Embed a Per-Monitor-V2 DPI-aware manifest so Windows renders at native
        # resolution instead of bitmap-upscaling the window (which blurs text on
        # high-DPI displays — the same problem Retina had on macOS).
        target_link_options(boss-man-pc PRIVATE
            "/MANIFEST:EMBED"
            "/MANIFESTINPUT:${CMAKE_CURRENT_SOURCE_DIR}/resources/windows/dpi.manifest")
    endif()
endif()

target_include_directories(boss-man-pc PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/assets
)

# MSVC's <cmath> hides M_PI and friends unless this is defined.
target_compile_definitions(boss-man-pc PRIVATE _USE_MATH_DEFINES)

target_link_libraries(boss-man-pc PRIVATE
    sfml-graphics
    sfml-window
    sfml-system
    sfml-audio
    sfml-network
    box2d
    nlohmann_json::nlohmann_json
)

# Embed all read-only assets (art, fonts, sounds, bundled levels) into the binary
# so it runs fully self-contained with no external assets/ folder.
file(GLOB_RECURSE EMBEDDED_ASSETS CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts/*.ttf"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/emoji/*.png"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/images/*.png"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/voice/*.wav"
)
cmrc_add_resource_library(bm-assets
    ALIAS bm::assets
    NAMESPACE bmassets
    WHENCE "${CMAKE_CURRENT_SOURCE_DIR}"
    ${EMBEDDED_ASSETS}
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/levels.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/AppIcon.png"
)
target_link_libraries(boss-man-pc PRIVATE bm::assets)

# ---- Linux: install rules + .deb packaging (cpack -G DEB -> Boss-Man.deb) ----
if(UNIX AND NOT APPLE)
    install(TARGETS boss-man-pc RUNTIME DESTINATION bin)
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/resources/linux/boss-man.desktop
            DESTINATION share/applications)
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/AppIcon.png
            DESTINATION share/icons/hicolor/256x256/apps RENAME boss-man.png)

    set(CPACK_GENERATOR "DEB")
    set(CPACK_PACKAGE_NAME "boss-man")
    set(CPACK_PACKAGE_FILE_NAME "Boss-Man")           # -> Boss-Man.deb
    set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "The office maze arcade game")
    set(CPACK_PACKAGE_CONTACT "todd@starplayrx.com")
    set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Todd Bruss <todd@starplayrx.com>")
    set(CPACK_DEBIAN_PACKAGE_SECTION "games")
    # Scan the binary and fill Depends with the system libs it actually needs
    # (X11/GL/OpenAL/FreeType/...), so `apt install ./Boss-Man.deb` resolves them.
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
    include(CPack)
endif()