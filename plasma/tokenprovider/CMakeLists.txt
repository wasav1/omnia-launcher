cmake_minimum_required(VERSION 3.21)
project(omnia-session-qml LANGUAGES CXX)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Qml)
include(GNUInstallDirs)
set(CMAKE_AUTOMOC ON)

add_library(omnia_sessionplugin MODULE
    plugin.cpp
    sessiontoken.cpp
    sessiontoken.h
)
target_compile_features(omnia_sessionplugin PRIVATE cxx_std_17)
target_link_libraries(omnia_sessionplugin PRIVATE Qt6::Core Qt6::Qml)

install(TARGETS omnia_sessionplugin LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/org/omnia/session)
install(FILES qmldir omnia_session.qmltypes DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/org/omnia/session)
