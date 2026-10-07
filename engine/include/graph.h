#ifndef GRAPH_H
#define GRAPH_H

#include <stddef.h>
#include <stdint.h>

#define EDGE_STAIRS 0x01

/* Directed edge. */
typedef struct {
    int32_t to;
    uint8_t flags; /* EDGE_* bits */
    double length_m;
} Edge;

/* Edge as read from a file or supplied by a test, before the CSR build. */
typedef struct {
    int32_t from, to;
    double length_m;
    uint8_t flags;
} EdgeRec;

/* Directed graph in compressed sparse row form. The out-edges of node u are
 * edges[offsets[u]] .. edges[offsets[u + 1] - 1]. */
typedef struct {
    int32_t n_nodes, n_edges;
    double *lat, *lon;
    int32_t *offsets; /* n_nodes + 1 entries */
    Edge *edges;
    int32_t n_clamped;  /* edges lengthened to the straight-line distance */
    double max_clamp_m; /* largest such lengthening, in meters */
} Graph;

/* Build a graph from arrays. Copies lat/lon. Validates node references and
 * lengths. An edge shorter than the straight-line distance between its
 * endpoints by up to 1 m (CSV rounding) is lengthened to that distance, which
 * keeps the haversine A* heuristic admissible and consistent; a larger gap is
 * treated as corrupt data. Returns 0 on success, -1 with a message in err. */
int graph_build(Graph *g, int32_t n_nodes, const double *lat, const double *lon,
                const EdgeRec *edges, int32_t n_edges, char *err, size_t errlen);

/* Load <dir>/nodes.csv and <dir>/edges.csv (format written by
 * data-pipeline/build_graph.py). Returns 0 on success, -1 with a message. */
int graph_load(Graph *g, const char *dir, char *err, size_t errlen);

void graph_free(Graph *g);

#endif
