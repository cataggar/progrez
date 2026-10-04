#define _DEFAULT_SOURCE

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#define SLEEP_MS(ms) Sleep(ms)
#else
#include <unistd.h>
#define SLEEP_MS(ms) usleep((ms) * 1000)
#endif

#include "progrez.h"

static void completed(const char *message, void *userdata) {
    int *calls = userdata;
    assert(strstr(message, "completed") != NULL);
    assert(strstr(message, "ffi-consumer") != NULL);
    ++*calls;
}

static void test_manual(void) {
    progrez_ctx *ctx = progrez_create(NULL);
    assert(ctx != NULL);
    progrez_set_notify(ctx, 0);
    progrez_set_identity(ctx, "ffi-consumer", "manual rendering");
    progrez_set_label(ctx, "Manual");
    progrez_set_sparkline(ctx, 1);
    progrez_set_gradient(ctx, 0, 255, 255, 128, 0, 255, 255, 0, 255);
    progrez_set_gradient_2(ctx, 0, 255, 255, 255, 0, 255);
    progrez_set_indeterminate(ctx);
    progrez_set_guess(ctx, 10, 1000);

    char buf[4096];
    size_t len = progrez_render_line(ctx, buf, sizeof(buf) - 1, 100);
    assert(len > 0 && len < sizeof(buf));
    progrez_update(ctx, 5, 500);
    progrez_set_determinate(ctx, 10, 1000);
    len = progrez_render_line(ctx, buf, sizeof(buf) - 1, 100);
    buf[len] = '\0';
    assert(strstr(buf, "Manual") != NULL);
    assert(strstr(buf, "50.0%") != NULL);
    assert(strstr(buf, "5/10 files") != NULL);

    char guard[3] = { 'a', 'b', 'c' };
    assert(progrez_render_line(ctx, guard + 1, 0, 80) == 0);
    assert(progrez_render_line(ctx, guard + 1, 1, 80) <= 1);
    assert(guard[0] == 'a' && guard[2] == 'c');
    assert(progrez_render_line(NULL, buf, sizeof(buf), 80) == 0);
    progrez_finish(ctx);
    progrez_destroy(ctx);
}

static void test_thread_and_callback(void) {
    progrez_ctx *ctx = progrez_create("Automatic");
    assert(ctx != NULL);
    progrez_set_identity(ctx, "ffi-consumer", "threaded rendering");
    progrez_set_interval_ms(ctx, 5);
    progrez_set_determinate(ctx, 10, 1000);
    progrez_update(ctx, 5, 500);
    SLEEP_MS(30);

    /* Switching to manual rendering must stop and join an active thread. */
    char buf[4096];
    size_t len = progrez_render_line(ctx, buf, sizeof(buf) - 1, 100);
    buf[len] = '\0';
    assert(strstr(buf, "50.0%") != NULL);

    int calls = 0;
    progrez_set_notify(ctx, 1);
    progrez_set_notify_after(ctx, 0);
    progrez_set_notify_callback(ctx, completed, &calls);
    progrez_update(ctx, 10, 1000);
    progrez_finish(ctx);
#ifndef _WIN32
    /* Windows currently has no environment overrides for non-TTY output. */
    assert(calls == 1);
#endif
    progrez_destroy(ctx);

    ctx = progrez_create("Destroy while rendering");
    assert(ctx != NULL);
    progrez_set_notify(ctx, 0);
    progrez_set_interval_ms(ctx, 5);
    progrez_update(ctx, 1, 100);
    SLEEP_MS(10);
    progrez_destroy(ctx);
}

int main(void) {
#ifndef _WIN32
    assert(setenv("PROGRESS", "true", 1) == 0);
    assert(setenv("PROGREZ_NOTIFY", "false", 1) == 0);
#endif
    test_manual();
    test_thread_and_callback();
    puts("C ABI tests passed");
    return 0;
}
