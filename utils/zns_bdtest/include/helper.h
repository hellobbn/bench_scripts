#pragma once

#ifndef NOLOG
void verbose(const char *restrict format, ...);
void znsinfo(const char *fmt, ...);
#else
#define verbose(...)
#define znsinfo(...)
#endif

void znswarn(const char *fmt, ...);
void znserror(const char *fmt, ...);

#define KB(x) ((x) << 10)
#define MB(x) ((x) << 20)
#define GB(x) ((x) << 30)

#define TO_KB(x) ((x) >> 10)
#define TO_MB(x) ((x) >> 20)
#define TO_GB(x) ((x) >> 30)
