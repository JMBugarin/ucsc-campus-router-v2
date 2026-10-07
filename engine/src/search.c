#include "search.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "geo.h"
#include "heap.h"

const char *algo_name(Algo a) { return a == ALGO_ASTAR ? "astar" : "dijkstra"; }

static double now_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}

/* Dijkstra and A* are the same loop; A* just orders the heap by
 * dist + h(node) instead of dist. With h(n) = straight-line distance to the
 * goal the heuristic is admissible, and because graph_build guarantees every
 * edge is at least as long as the straight line between its endpoints it is
 * also consistent, so a settled node never needs to be reopened. */
int search_run_opts(const Graph *g, Algo algo, int32_t src, int32_t dst, bool record_explored,
                    SearchResult *out)
{
    memset(out, 0, sizeof *out);
    if (src < 0 || src >= g->n_nodes || dst < 0 || dst >= g->n_nodes)
        return -1;

    double t0 = now_us();
    size_t n = (size_t)g->n_nodes;
    double *dist = malloc(n * sizeof *dist);
    int32_t *prev = malloc(n * sizeof *prev);
    bool *settled = calloc(n, sizeof *settled);
    MinHeap heap;
    int rc = -1;

    if (record_explored)
        out->explored = malloc(n * sizeof *out->explored);
    if (!dist || !prev || !settled || (record_explored && !out->explored) ||
        heap_init(&heap, 64) != 0) {
        free(dist);
        free(prev);
        free(settled);
        search_result_free(out);
        return -1;
    }
    for (size_t i = 0; i < n; i++) {
        dist[i] = INFINITY;
        prev[i] = -1;
    }

    bool use_h = (algo == ALGO_ASTAR);
    double goal_lat = g->lat[dst], goal_lon = g->lon[dst];
#define H(v) (use_h ? haversine_m(g->lat[v], g->lon[v], goal_lat, goal_lon) : 0.0)

    dist[src] = 0.0;
    if (heap_push(&heap, src, H(src)) != 0)
        goto done;
    out->heap_pushes++;

    HeapItem item;
    while (heap_pop(&heap, &item)) {
        int32_t u = item.node;
        if (settled[u])
            continue; /* stale entry left behind by lazy deletion */
        settled[u] = true;
        if (out->explored)
            out->explored[out->nodes_explored] = u;
        out->nodes_explored++;
        if (u == dst)
            break;

        for (int32_t i = g->offsets[u]; i < g->offsets[u + 1]; i++) {
            const Edge *e = &g->edges[i];
            if (settled[e->to])
                continue;
            double nd = dist[u] + e->length_m;
            if (nd < dist[e->to]) {
                dist[e->to] = nd;
                prev[e->to] = u;
                if (heap_push(&heap, e->to, nd + H(e->to)) != 0)
                    goto done;
                out->heap_pushes++;
            }
        }
    }
#undef H

    if (settled[dst]) {
        int32_t len = 1;
        for (int32_t v = dst; v != src; v = prev[v])
            len++;
        out->path = malloc((size_t)len * sizeof *out->path);
        if (!out->path)
            goto done;
        int32_t v = dst;
        for (int32_t i = len - 1; i >= 0; i--) {
            out->path[i] = v;
            v = prev[v];
        }
        out->path_len = len;
        out->cost_m = dist[dst];
        out->found = true;
    }
    rc = 0;

done:
    heap_free(&heap);
    free(dist);
    free(prev);
    free(settled);
    out->time_us = now_us() - t0;
    return rc;
}

void search_result_free(SearchResult *r)
{
    free(r->path);
    free(r->explored);
    r->path = NULL;
    r->explored = NULL;
    r->path_len = 0;
}

int search_run(const Graph *g, Algo algo, int32_t src, int32_t dst, SearchResult *out)
{
    return search_run_opts(g, algo, src, dst, false, out);
}
