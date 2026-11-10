cmake_minimum_required(VERSION 3.21)
project(LiveWeather VERSION 1.1.6 LANGUAGES CXX)

# Live Weather for Windows and macOS: runs the same QML wallpaper as the KDE
# plugin (../package) in a window behind the desktop icons on every screen.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Widgets Network)
qt_standard_project_setup()

# Some Qt builds still link Apple's AGL framework, which current Xcode SDKs no
# longer have; drop it (nothing here uses it)
if(APPLE AND TARGET WrapOpenGL::WrapOpenGL)
    get_target_property(_gl_libs WrapOpenGL::WrapOpenGL INTERFACE_LINK_LIBRARIES)
    if(_gl_libs)
        list(FILTER _gl_libs EXCLUDE REGEX "AGL")
        set_target_properties(WrapOpenGL::WrapOpenGL PROPERTIES INTERFACE_LINK_LIBRARIES "${_gl_libs}")
    endif()
endif()

set(SOURCES src/main.cpp src/config.cpp src/config.h src/desktop.h src/autostart.cpp src/autostart.h)
if(WIN32)
    list(APPEND SOURCES src/desktop_win.cpp icons/app.rc)
elseif(APPLE)
    enable_language(OBJCXX)
    list(APPEND SOURCES src/desktop_mac.mm)
    set(MACOSX_BUNDLE_ICON_FILE app.icns)
    set_source_files_properties(icons/app.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    list(APPEND SOURCES icons/app.icns)
else()
    list(APPEND SOURCES src/desktop_other.cpp)
endif()

qt_add_executable(LiveWeather WIN32 MACOSX_BUNDLE ${SOURCES})
qt_add_resources(LiveWeather "ui" PREFIX "/" FILES qml/Settings.qml icons/tray.png icons/tray-mac.png)

set_target_properties(LiveWeather PROPERTIES
    OUTPUT_NAME "Live Weather"
    MACOSX_BUNDLE_GUI_IDENTIFIER com.matvaughn.weatherwall
    MACOSX_BUNDLE_BUNDLE_NAME "Live Weather"
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/mac/Info.plist.in)

target_link_libraries(LiveWeather PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Widgets Qt6::Network)
if(WIN32)
    target_link_libraries(LiveWeather PRIVATE user32)
elseif(APPLE)
    target_link_libraries(LiveWeather PRIVATE "-framework AppKit")
endif()
