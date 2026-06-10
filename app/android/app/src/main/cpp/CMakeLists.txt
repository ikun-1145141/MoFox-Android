cmake_minimum_required(VERSION 3.22.1)

project(mofoxpty LANGUAGES C)

add_library(mofoxpty SHARED mofoxpty.c)

target_link_libraries(mofoxpty log)