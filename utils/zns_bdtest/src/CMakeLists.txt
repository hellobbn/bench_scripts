add_executable(zns_bdtest main.c helper.c)
target_link_libraries(zns_bdtest LINK_PUBLIC zbd)
target_include_directories(zns_bdtest PUBLIC ${CMAKE_SOURCE_DIR}/include)
