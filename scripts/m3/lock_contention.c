// lock_contention.c — Scenario B workload: futex lock contention.
//
// N threads fight over a single pthread mutex for a fixed duration.
// Losing threads block in futex_wait, producing off-CPU time attributed
// to the futex syscall stack.

#define _GNU_SOURCE
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static volatile int stop = 0;

static void *worker(void *arg) {
    (void)arg;
    while (!stop) {
        pthread_mutex_lock(&lock);
        pthread_mutex_unlock(&lock);
    }
    return NULL;
}

int main(int argc, char **argv) {
    int secs = argc > 1 ? atoi(argv[1]) : 8;
    int nthreads = argc > 2 ? atoi(argv[2]) : 8;

    pthread_t *threads = calloc((size_t)nthreads, sizeof(pthread_t));
    if (!threads) {
        perror("calloc");
        return 1;
    }

    for (int i = 0; i < nthreads; i++) {
        if (pthread_create(&threads[i], NULL, worker, NULL) != 0) {
            perror("pthread_create");
            return 1;
        }
    }

    struct timespec ts = { .tv_sec = secs, .tv_nsec = 0 };
    nanosleep(&ts, NULL);
    stop = 1;

    for (int i = 0; i < nthreads; i++)
        pthread_join(threads[i], NULL);

    free(threads);
    return 0;
}
