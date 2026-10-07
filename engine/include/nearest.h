#ifndef NEAREST_H
#define NEAREST_H

#include <stdint.h>

#include "graph.h"

/* Node closest to (lat, lon) by great-circle distance, or -1 if the graph is
 * empty. If dist_m is non-NULL it receives the distance in meters. Linear
 * scan: fine for a campus-sized graph, replace with a grid index if needed. */
int32_t nearest_node(const Graph *g, double lat, double lon, double *dist_m);

#endif
