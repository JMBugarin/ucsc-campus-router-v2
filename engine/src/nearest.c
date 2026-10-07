#include "nearest.h"

#include "geo.h"

int32_t nearest_node(const Graph *g, double lat, double lon, double *dist_m)
{
    int32_t best = -1;
    double best_d = 0.0;
    for (int32_t i = 0; i < g->n_nodes; i++) {
        double d = haversine_m(lat, lon, g->lat[i], g->lon[i]);
        if (best < 0 || d < best_d) {
            best = i;
            best_d = d;
        }
    }
    if (dist_m)
        *dist_m = best_d;
    return best;
}
