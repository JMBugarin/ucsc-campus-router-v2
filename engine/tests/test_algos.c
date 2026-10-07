#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "geo.h"
#include "graph.h"
#include "search.h"
#include "testutil.h"

#ifndef REAL_GRAPH_DIR
#define REAL_GRAPH_DIR "../graph/ucsc"
#endif

static const Algo ALGOS[2] = {ALGO_DIJKSTRA, ALGO_ASTAR};

/* Cheapest edge u -> v, or -1 if there is none. */
static double edge_cost(const Graph *g, int32_t u, int32_t v)
{
    double best = -1.0;
    for (int32_t i = g->offsets[u]; i < g->offsets[u + 1]; i++)
        if (g->edges[i].to == v && (best < 0 || g->edges[i].length_m < best))
            best = g->edges[i].length_m;
    return best;
}

/* Checks that a result is a real path from src to dst whose edges add up to
 * the reported cost. */
static void check_path(const Graph *g, const SearchResult *r, int32_t src, int32_t dst)
{
    CHECK(r->found && r->path_len >= 1);
    if (!r->found || r->path_len < 1)
        return;
    CHECK(r->path[0] == src && r->path[r->path_len - 1] == dst);
    double sum = 0.0;
    for (int32_t i = 0; i + 1 < r->path_len; i++) {
        double c = edge_cost(g, r->path[i], r->path[i + 1]);
        CHECK(c >= 0.0);
        sum += c;
    }
    CHECK_NEAR(sum, r->cost_m, 1e-6);
}

/* Runs both algorithms and checks that they agree with each other (and with
 * want_cost when it is >= 0; pass -1 for "no path expected"). */
static void check_both(const Graph *g, int32_t src, int32_t dst, double want_cost,
                       const int32_t *want_path, int32_t want_len)
{
    SearchResult r[2];
    for (int a = 0; a < 2; a++) {
        CHECK(search_run(g, ALGOS[a], src, dst, &r[a]) == 0);
        if (want_cost < 0) {
            CHECK(!r[a].found && r[a].path == NULL);
            continue;
        }
        CHECK(r[a].found);
        CHECK_NEAR(r[a].cost_m, want_cost, 1e-6);
        check_path(g, &r[a], src, dst);
        if (want_path) {
            CHECK(r[a].path_len == want_len);
            for (int32_t i = 0; i < want_len && i < r[a].path_len; i++)
                CHECK(r[a].path[i] == want_path[i]);
        }
        CHECK(r[a].nodes_explored >= 1 && r[a].heap_pushes >= 1 && r[a].time_us >= 0);
    }
    search_result_free(&r[0]);
    search_result_free(&r[1]);
}

/* ---- hand-made graph with known answers ------------------------------- */

/* The classic textbook shortest-path graph, undirected, with edge lengths
 *   0-1: 7   0-2: 9   0-5: 14   1-2: 10   1-3: 15
 *   2-3: 11  2-5: 2   3-4: 6    4-5: 9
 * The nodes sit within ~1 m of each other, so every edge is far longer than
 * the straight line between its endpoints and these lengths are what the
 * router sees. Known answers: 0->5 is 11 (via 2, beating the direct 14),
 * 0->4 is 20 (0-2-5-4), 0->3 is 20 (0-2-3). */
static void build_textbook(Graph *g, int n_nodes)
{
    double lat[8], lon[8];
    for (int i = 0; i < n_nodes; i++) {
        lat[i] = 37.0 + i * 0.000002;
        lon[i] = -122.0;
    }
    const struct { int a, b; double w; } und[] = {
        {0, 1, 7}, {0, 2, 9}, {0, 5, 14}, {1, 2, 10}, {1, 3, 15},
        {2, 3, 11}, {2, 5, 2}, {3, 4, 6}, {4, 5, 9},
    };
    EdgeRec edges[18];
    int n = 0;
    for (size_t i = 0; i < sizeof und / sizeof und[0]; i++) {
        edges[n++] = (EdgeRec){und[i].a, und[i].b, und[i].w, 0};
        edges[n++] = (EdgeRec){und[i].b, und[i].a, und[i].w, 0};
    }
    char err[128];
    CHECK(graph_build(g, n_nodes, lat, lon, edges, n, err, sizeof err) == 0);
}

static void test_textbook_graph(void)
{
    Graph g;
    build_textbook(&g, 6);

    /* Direct edge 0-5 costs 14, but 0-2-5 costs 11: the detour wins. */
    const int32_t p05[] = {0, 2, 5};
    check_both(&g, 0, 5, 11.0, p05, 3);

    const int32_t p04[] = {0, 2, 5, 4};
    check_both(&g, 0, 4, 20.0, p04, 4);
    const int32_t p40[] = {4, 5, 2, 0};
    check_both(&g, 4, 0, 20.0, p40, 4);

    const int32_t p03[] = {0, 2, 3};
    check_both(&g, 0, 3, 20.0, p03, 3);

    const int32_t p13[] = {1, 3};
    check_both(&g, 1, 3, 15.0, p13, 2);
    graph_free(&g);
}

static void test_same_start_and_end(void)
{
    Graph g;
    build_textbook(&g, 6);
    const int32_t p[] = {3};
    check_both(&g, 3, 3, 0.0, p, 1);
    graph_free(&g);
}

static void test_unreachable(void)
{
    Graph g;
    build_textbook(&g, 7); /* node 6 has no edges */
    check_both(&g, 0, 6, -1.0, NULL, 0);
    check_both(&g, 6, 0, -1.0, NULL, 0);
    graph_free(&g);
}

static void test_edges_are_directed(void)
{
    Graph g;
    char err[128];
    double lat[3] = {37.0, 37.000002, 37.000004}, lon[3] = {-122.0, -122.0, -122.0};
    EdgeRec edges[] = {{0, 1, 5.0, 0}, {1, 2, 5.0, 0}, {2, 0, 100.0, 0}};
    CHECK(graph_build(&g, 3, lat, lon, edges, 3, err, sizeof err) == 0);
    const int32_t fwd[] = {0, 1, 2};
    check_both(&g, 0, 2, 10.0, fwd, 3);
    const int32_t back[] = {2, 0};
    check_both(&g, 2, 0, 100.0, back, 2);
    check_both(&g, 1, 0, 105.0, NULL, 0); /* 1 -> 2 -> 0, there is no 1 -> 0 edge */
    graph_free(&g);
}

static void test_invalid_node_ids(void)
{
    Graph g;
    SearchResult r;
    build_textbook(&g, 6);
    for (int a = 0; a < 2; a++) {
        CHECK(search_run(&g, ALGOS[a], -1, 2, &r) == -1);
        CHECK(search_run(&g, ALGOS[a], 0, 6, &r) == -1);
    }
    graph_free(&g);
}

/* ---- Dijkstra and A* must agree --------------------------------------- */

/* Compare both algorithms over many random pairs; returns the totals of
 * nodes explored so callers can check A* does less work. */
static void compare_random_pairs(const Graph *g, int n_queries, long *explored_dij,
                                 long *explored_astar, int *n_found)
{
    *explored_dij = *explored_astar = 0;
    *n_found = 0;
    for (int q = 0; q < n_queries; q++) {
        int32_t s = rand() % g->n_nodes, e = rand() % g->n_nodes;
        SearchResult d, a;
        CHECK(search_run(g, ALGO_DIJKSTRA, s, e, &d) == 0);
        CHECK(search_run(g, ALGO_ASTAR, s, e, &a) == 0);
        CHECK(d.found == a.found);
        if (d.found && a.found) {
            CHECK_NEAR(d.cost_m, a.cost_m, 1e-6);
            check_path(g, &d, s, e);
            check_path(g, &a, s, e);
            (*n_found)++;
        }
        *explored_dij += d.nodes_explored;
        *explored_astar += a.nodes_explored;
        search_result_free(&d);
        search_result_free(&a);
    }
}

/* Random geometric graph with directed edges of unequal cost in each
 * direction, each at least as long as the straight line. */
static void test_random_graph(void)
{
    enum { N = 400, K = 5 };
    double lat[N], lon[N];
    EdgeRec *edges = malloc((size_t)N * K * sizeof *edges);
    char err[128];
    Graph g;
    int n = 0;

    CHECK(edges != NULL);
    srand(2024);
    for (int i = 0; i < N; i++) {
        lat[i] = 36.99 + 0.009 * rand() / RAND_MAX;
        lon[i] = -122.06 + 0.011 * rand() / RAND_MAX;
    }
    for (int i = 0; i < N; i++) {
        /* connect to the K nearest other nodes */
        double best_d[K];
        int best_j[K];
        for (int k = 0; k < K; k++) {
            best_d[k] = INFINITY;
            best_j[k] = -1;
        }
        for (int j = 0; j < N; j++) {
            if (j == i)
                continue;
            double d = haversine_m(lat[i], lon[i], lat[j], lon[j]);
            int k = K - 1;
            if (d >= best_d[k])
                continue;
            while (k > 0 && d < best_d[k - 1]) {
                best_d[k] = best_d[k - 1];
                best_j[k] = best_j[k - 1];
                k--;
            }
            best_d[k] = d;
            best_j[k] = j;
        }
        for (int k = 0; k < K; k++) {
            double stretch = 1.0 + 0.6 * rand() / RAND_MAX;
            edges[n++] = (EdgeRec){i, best_j[k], best_d[k] * stretch, 0};
        }
    }
    CHECK(graph_build(&g, N, lat, lon, edges, n, err, sizeof err) == 0);
    free(edges);

    long dij, astar;
    int found;
    compare_random_pairs(&g, 500, &dij, &astar, &found);
    CHECK(found > 100);
    CHECK(astar <= dij); /* a consistent heuristic never makes the search explore more */
    graph_free(&g);
}

static void test_real_graph(void)
{
    Graph g;
    char err[256] = "";
    FILE *probe = fopen(REAL_GRAPH_DIR "/nodes.csv", "r");
    if (!probe) {
        printf("(skipping real-graph test: %s not found)\n", REAL_GRAPH_DIR);
        return;
    }
    fclose(probe);

    CHECK(graph_load(&g, REAL_GRAPH_DIR, err, sizeof err) == 0);
    if (g.n_nodes == 0)
        return;
    srand(7);
    long dij, astar;
    int found;
    compare_random_pairs(&g, 300, &dij, &astar, &found);
    CHECK(found == 300); /* the exported graph is strongly connected */
    CHECK(astar < dij);
    graph_free(&g);
}

/* The explored list is the settle order: starts at the source, ends at the
 * destination, has no repeats, and has one entry per nodes_explored. */
static void test_explored_order(void)
{
    Graph g;
    build_textbook(&g, 6);
    for (int a = 0; a < 2; a++) {
        SearchResult r;
        CHECK(search_run_opts(&g, ALGOS[a], 0, 4, true, &r) == 0);
        CHECK(r.found && r.explored != NULL);
        CHECK(r.nodes_explored >= r.path_len);
        if (r.explored && r.nodes_explored >= 1) {
            CHECK(r.explored[0] == 0);
            CHECK(r.explored[r.nodes_explored - 1] == 4);
            bool seen[6] = {false};
            for (long i = 0; i < r.nodes_explored; i++) {
                CHECK(r.explored[i] >= 0 && r.explored[i] < 6 && !seen[r.explored[i]]);
                seen[r.explored[i]] = true;
            }
            /* every node on the shortest path was settled */
            for (int32_t i = 0; i < r.path_len; i++)
                CHECK(seen[r.path[i]]);
        }
        search_result_free(&r);

        CHECK(search_run(&g, ALGOS[a], 0, 4, &r) == 0);
        CHECK(r.explored == NULL); /* not recorded unless asked for */
        search_result_free(&r);
    }
    graph_free(&g);
}

int main(void)
{
    test_textbook_graph();
    test_same_start_and_end();
    test_unreachable();
    test_edges_are_directed();
    test_invalid_node_ids();
    test_explored_order();
    test_random_graph();
    test_real_graph();
    return TEST_RESULT();
}
