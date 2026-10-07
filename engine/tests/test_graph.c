#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "geo.h"
#include "graph.h"
#include "testutil.h"

#ifndef FIXTURE_DIR
#define FIXTURE_DIR "tests/fixtures"
#endif
#ifndef REAL_GRAPH_DIR
#define REAL_GRAPH_DIR "../graph/ucsc"
#endif

static void test_haversine(void)
{
    CHECK_NEAR(haversine_m(37.0, -122.0, 37.0, -122.0), 0.0, 1e-9);
    /* One degree of latitude is about 111.2 km. */
    CHECK_NEAR(haversine_m(37.0, -122.0, 38.0, -122.0), 111195.0, 100.0);
    /* Symmetric. */
    CHECK_NEAR(haversine_m(36.99, -122.06, 37.00, -122.05),
               haversine_m(37.00, -122.05, 36.99, -122.06), 1e-9);
}

static void test_load_tiny(void)
{
    Graph g;
    char err[256] = "";
    CHECK(graph_load(&g, FIXTURE_DIR "/tiny", err, sizeof err) == 0);
    if (g.n_nodes != 4) {
        CHECK(!"tiny graph has 4 nodes");
        graph_free(&g);
        return;
    }
    CHECK(g.n_edges == 6);

    /* CSR layout: node 0 has 1 edge, node 1 has 2, node 2 has 2, node 3 has 1. */
    const int32_t want_offsets[5] = {0, 1, 3, 5, 6};
    for (int i = 0; i < 5; i++)
        CHECK(g.offsets[i] == want_offsets[i]);

    CHECK(g.edges[g.offsets[0]].to == 1);
    CHECK_NEAR(g.edges[g.offsets[0]].length_m, 12.0, 1e-9);
    CHECK(!(g.edges[g.offsets[0]].flags & EDGE_STAIRS));

    /* Node 1: edges to 0 (footway) and 2 (steps), in file order. */
    CHECK(g.edges[g.offsets[1]].to == 0);
    CHECK(g.edges[g.offsets[1] + 1].to == 2);
    CHECK(g.edges[g.offsets[1] + 1].flags & EDGE_STAIRS);

    /* 3 -> 0 is listed as 8.50 m but the nodes are ~8.9 m apart: lengthened. */
    CHECK(g.n_clamped == 1);
    CHECK(g.max_clamp_m > 0.3 && g.max_clamp_m < 0.5);
    double straight = haversine_m(g.lat[3], g.lon[3], g.lat[0], g.lon[0]);
    CHECK(g.edges[g.offsets[3]].to == 0);
    CHECK(g.edges[g.offsets[3]].length_m >= straight);
    CHECK_NEAR(g.edges[g.offsets[3]].length_m, straight, 1e-9);

    CHECK_NEAR(g.lat[1], 37.0001, 1e-9);
    CHECK_NEAR(g.lon[2], -122.0001, 1e-9);
    graph_free(&g);
}

static void expect_load_failure(const char *dir, const char *needle)
{
    Graph g;
    char err[256] = "";
    char path[256];
    snprintf(path, sizeof path, FIXTURE_DIR "/%s", dir);
    int rc = graph_load(&g, path, err, sizeof err);
    if (rc != -1 || strstr(err, needle) == NULL) {
        fprintf(stderr, "%s: expected failure mentioning \"%s\", got rc=%d err=\"%s\"\n", dir,
                needle, rc, err);
        g_failures++;
    }
    CHECK(g.edges == NULL && g.offsets == NULL); /* nothing left allocated */
}

static void test_load_rejects_bad_input(void)
{
    expect_load_failure("does_not_exist", "cannot open");
    expect_load_failure("bad_header", "expected header");
    expect_load_failure("bad_node_ids", "node ids must be");
    expect_load_failure("bad_edge_ref", "outside");
    expect_load_failure("bad_length", "non-positive length");
    expect_load_failure("bad_geometry", "apart");
    expect_load_failure("bad_fields", "expected 5 fields");
}

static void test_build_directly(void)
{
    Graph g;
    char err[128];
    const double lat[3] = {37.0, 37.0, 37.0};
    const double lon[3] = {-122.0, -122.00001, -122.00002};
    /* Edges deliberately out of source order: the CSR build must group them. */
    const EdgeRec edges[3] = {{2, 0, 5.0, 0}, {0, 1, 5.0, EDGE_STAIRS}, {0, 2, 5.0, 0}};
    CHECK(graph_build(&g, 3, lat, lon, edges, 3, err, sizeof err) == 0);
    CHECK(g.offsets[0] == 0 && g.offsets[1] == 2 && g.offsets[2] == 2 && g.offsets[3] == 3);
    CHECK(g.edges[0].to == 1 && (g.edges[0].flags & EDGE_STAIRS));
    CHECK(g.edges[1].to == 2);
    CHECK(g.edges[2].to == 0);
    graph_free(&g);

    CHECK(graph_build(&g, 0, lat, lon, edges, 0, err, sizeof err) == 0);
    CHECK(g.n_nodes == 0 && g.n_edges == 0);
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
    CHECK(g.n_nodes > 1000 && g.n_edges > g.n_nodes);
    CHECK(g.offsets[0] == 0 && g.offsets[g.n_nodes] == g.n_edges);

    for (int32_t u = 0; u < g.n_nodes; u++) {
        CHECK(g.offsets[u] <= g.offsets[u + 1]);
        for (int32_t i = g.offsets[u]; i < g.offsets[u + 1]; i++) {
            const Edge *e = &g.edges[i];
            CHECK(e->to >= 0 && e->to < g.n_nodes);
            /* The A* heuristic is only admissible if no edge is shorter than
             * the straight line between its endpoints. */
            CHECK(e->length_m >= haversine_m(g.lat[u], g.lon[u], g.lat[e->to], g.lon[e->to]));
        }
    }
    /* Many short straight edges fall a hair under the straight line because
     * the CSV rounds lengths to 0.01 m, but clamping must never move an edge
     * by more than that rounding. */
    CHECK(g.max_clamp_m <= 0.01);
    graph_free(&g);
}

int main(void)
{
    test_haversine();
    test_load_tiny();
    test_load_rejects_bad_input();
    test_build_directly();
    test_real_graph();
    return TEST_RESULT();
}
