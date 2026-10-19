#ifndef SEARCH_H
#define SEARCH_H

#include <stdbool.h>
#include <stdint.h>

#include "graph.h"

typedef enum { ALGO_DIJKSTRA, ALGO_ASTAR } Algo;

typedef struct {
    bool found;
    double cost_m;       /* what the search minimised (see SearchOpts), valid when found */
    double length_m;     /* physical length of the path */
    double effective_m;  /* flat-ground-equivalent length: length scaled for climbs, no stairs penalty */
    double stairs_m;     /* how much of the path is stairs */
    int32_t *path;       /* node ids from source to destination; free with search_result_free */
    int32_t path_len;
    long nodes_explored; /* nodes settled (popped with their final distance) */
    int32_t *explored;   /* settled nodes in order, only if requested; nodes_explored entries */
    long heap_pushes;
    double time_us;      /* wall time for the whole query */
} SearchResult;

typedef struct {
    bool record_explored; /* fill SearchResult.explored */
    bool avoid_stairs;    /* stairs edges cost STAIRS_AVOID_FACTOR times more, so any alternative wins */
} SearchOpts;

#define STAIRS_AVOID_FACTOR 20.0

const char *algo_name(Algo a);

/* Shortest path from src to dst. Returns 0 on success (including "no path":
 * check out->found), -1 on invalid node ids or out of memory. */
int search_run(const Graph *g, Algo algo, int32_t src, int32_t dst, SearchResult *out);

/* Same, and when record_explored is true also fills out->explored with the
 * settled nodes in the order they were settled (for visualizing the search). */
int search_run_opts(const Graph *g, Algo algo, int32_t src, int32_t dst, bool record_explored,
                    SearchResult *out);

/* The general form of the above. Costs are edge cost_m (grade-adjusted when the graph has
 * elevations), times STAIRS_AVOID_FACTOR on stairs when avoid_stairs is set; both only raise an
 * edge above its length, so the straight-line heuristic stays admissible. */
int search_run_ex(const Graph *g, Algo algo, int32_t src, int32_t dst, const SearchOpts *opts,
                  SearchResult *out);

void search_result_free(SearchResult *r);

#endif
