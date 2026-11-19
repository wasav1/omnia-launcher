cmake_minimum_required(VERSION 3.21)
project(omnia-installer LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Widgets)
add_executable(omnia-installer main.cpp)
target_compile_features(omnia-installer PRIVATE cxx_std_17)
target_link_libraries(omnia-installer PRIVATE Qt6::Widgets)

set(OMNIA_LUCIDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../ui/qml/images/lucide")
file(GLOB OMNIA_LUCIDE_ASSETS CONFIGURE_DEPENDS "${OMNIA_LUCIDE_DIR}/*.svg")
qt_add_resources(omnia-installer "lucide"
    PREFIX "/lucide"
    BASE "${OMNIA_LUCIDE_DIR}"
    FILES ${OMNIA_LUCIDE_ASSETS} "${OMNIA_LUCIDE_DIR}/LICENSE")
