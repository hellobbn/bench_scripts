#include <stdarg.h>
#include <stdio.h>

void info(const char *restrict format, ...) {
    va_list args;
    va_start(args, format);
    // print in green
    printf("\033[0;32minfo: \033[0m");
    vprintf(format, args);
    va_end(args);
}

void warn(const char *restrict format, ...) {
    va_list args;
    va_start(args, format);
    // print in yellow
    printf("\033[0;33mwarn: \033[0m");
    vprintf(format, args);
    va_end(args);
}

void error(const char *restrict format, ...) {
    va_list args;
    va_start(args, format);
    // print in red
    printf("\033[0;31merror: \033[0m");
    vprintf(format, args);
    va_end(args);
}

