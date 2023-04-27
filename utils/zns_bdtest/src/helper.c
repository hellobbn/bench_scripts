#include <stdarg.h>
#include <stdio.h>

#ifndef NOLOG
void verbose(const char *restrict format, ...) {
    va_list args;
    va_start(args, format);
    // print in blue
    printf("\033[0;34m");
    vprintf(format, args);
    printf("\033[0m");
    va_end(args);
}

void znsinfo(const char *restrict format, ...) {
    va_list args;
    va_start(args, format);
    // print in green
    printf("\033[0;32minfo: \033[0m");
    vprintf(format, args);
    va_end(args);
}
#else
#define verbose(format, ...)
#define znsinfo(format, ...)
#endif

void znswarn(const char *restrict format, ...) {
    va_list args;
    va_start(args, format);
    // print in yellow
    printf("\033[0;33mwarn: \033[0m");
    vprintf(format, args);
    va_end(args);
}

void znserror(const char *restrict format, ...) {
    va_list args;
    va_start(args, format);
    // print in red
    printf("\033[0;31merror: \033[0m");
    vprintf(format, args);
    va_end(args);
}
