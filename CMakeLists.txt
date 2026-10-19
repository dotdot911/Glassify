cmake_minimum_required(VERSION 3.20)
project(glassify CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# The C++ core of Sources/Glassify, built on the host for the unit tests.
add_library(glassify_core STATIC
  Sources/Glassify/Core/glass_inputs.cpp
  Sources/Glassify/Core/color_matrix.cpp
  Sources/Glassify/Core/pack.cpp
  Sources/Glassify/Core/press.cpp)
target_include_directories(glassify_core PUBLIC Sources/Glassify/Core/include)
target_compile_options(glassify_core PRIVATE -Wall -Wextra -Werror)

enable_testing()
add_executable(glassify_tests Tests/Core/main.cpp Tests/Core/test_laws.cpp Tests/Core/test_pack.cpp Tests/Core/test_press.cpp)
target_link_libraries(glassify_tests PRIVATE glassify_core)
target_compile_definitions(glassify_tests PRIVATE GLS_TEST_DATA="${CMAKE_CURRENT_SOURCE_DIR}/Tests/Core/data")
add_test(NAME glassify_tests COMMAND glassify_tests)
