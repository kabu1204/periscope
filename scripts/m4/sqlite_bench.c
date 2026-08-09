// sqlite_bench.c — sqlite insert benchmark for the M4 case study.
//
// Inserts N rows one transaction at a time (each commit fsyncs the
// journal), which makes the workload sensitive to block IO latency.
// This is the "synchronous commit" path that the case study analyzes.
//
// Usage: sqlite_bench <db-path> <n-rows> [row-size-bytes]

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>
#include <time.h>

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <db-path> <n-rows> [row-size-bytes]\n", argv[0]);
        return 1;
    }
    const char *dbpath = argv[1];
    int nrows = atoi(argv[2]);
    int rowsize = argc > 3 ? atoi(argv[3]) : 100;

    sqlite3 *db;
    if (sqlite3_open(dbpath, &db) != SQLITE_OK) {
        fprintf(stderr, "open: %s\n", sqlite3_errmsg(db));
        return 1;
    }

    // Delete journal mode forces a journal file + fsync per commit,
    // maximizing sensitivity to block IO latency.
    sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA synchronous=FULL;", NULL, NULL, NULL);
    sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, data TEXT);",
                 NULL, NULL, NULL);

    // Build a row payload of the requested size.
    char *payload = malloc((size_t)rowsize + 1);
    memset(payload, 'x', (size_t)rowsize);
    payload[rowsize] = '\0';

    sqlite3_stmt *ins;
    sqlite3_prepare_v2(db, "INSERT INTO t(data) VALUES(?1);", -1, &ins, NULL);

    double t0 = now_s();
    for (int i = 0; i < nrows; i++) {
        sqlite3_exec(db, "BEGIN;", NULL, NULL, NULL);
        sqlite3_bind_text(ins, 1, payload, rowsize, SQLITE_STATIC);
        sqlite3_step(ins);
        sqlite3_reset(ins);
        sqlite3_exec(db, "COMMIT;", NULL, NULL, NULL);
    }
    double t1 = now_s();

    double elapsed = t1 - t0;
    printf("rows=%d elapsed=%.3fs rows_per_sec=%.0f\n",
           nrows, elapsed, nrows / elapsed);

    sqlite3_finalize(ins);
    sqlite3_close(db);
    free(payload);
    return 0;
}
