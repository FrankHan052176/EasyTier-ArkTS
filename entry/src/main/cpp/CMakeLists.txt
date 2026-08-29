cmake_minimum_required(VERSION 3.5.0)
project(easytier_ui)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(easytier_ui SHARED napi_init.cpp)
target_link_libraries(easytier_ui PUBLIC libace_napi.z.so libace_ndk.z.so libhitrace_ndk.z.so)
