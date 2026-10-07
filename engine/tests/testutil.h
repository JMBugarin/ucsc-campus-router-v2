#ifndef TESTUTIL_H
#define TESTUTIL_H

#include <math.h>
#include <stdio.h>

/* Minimal test harness: CHECK records a failure and keeps going; main returns
 * TEST_RESULT() so the process exit code reflects whether anything failed. */
static int g_failures;

#define CHECK(cond)                                                                    \
    do {                                                                               \
        if (!(cond)) {                                                                 \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond);   \
            g_failures++;                                                              \
        }                                                                              \
    } while (0)

#define CHECK_NEAR(a, b, eps) CHECK(fabs((a) - (b)) <= (eps))

#define TEST_RESULT()                                                                  \
    (g_failures ? (fprintf(stderr, "%d check(s) failed\n", g_failures), 1)             \
                : (printf("ok\n"), 0))

#endif
