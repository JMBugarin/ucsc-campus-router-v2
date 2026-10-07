/* route: shortest walking route on the UCSC graph.
 *
 *   route <graph_dir> <start_lat> <start_lon> <end_lat> <end_lon>
 *         [--algo dijkstra|astar] [--json [--explored]]
 *   route <graph_dir> --bench [N] [--seed S]
 */
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "graph.h"
#include "nearest.h"
#include "search.h"

static void usage(void)
{
    fprintf(stderr,
            "usage: route <graph_dir> <start_lat> <start_lon> <end_lat> <end_lon>\n"
            "             [--algo dijkstra|astar] [--json [--explored]]\n"
            "       route <graph_dir> --bench [N] [--seed S]\n");
}

static bool parse_double_arg(const char *s, double *out)
{
    char *end;
    *out = strtod(s, &end);
    return *s != '\0' && *end == '\0' && isfinite(*out);
}

static bool parse_ulong_arg(const char *s, unsigned long *out)
{
    char *end;
    *out = strtoul(s, &end, 10);
    return *s != '\0' && *end == '\0' && *s != '-';
}

/* ---- single query ----------------------------------------------------- */

static void print_text(Algo algo, const SearchResult *r, int32_t s, int32_t e, double sd,
                       double ed)
{
    printf("algorithm:       %s\n", algo_name(algo));
    printf("start snapped:   node %d (%.1f m from input)\n", s, sd);
    printf("end snapped:     node %d (%.1f m from input)\n", e, ed);
    if (!r->found) {
        printf("result:          no path\n");
        return;
    }
    printf("distance:        %.1f m\n", r->cost_m);
    printf("path nodes:      %d\n", r->path_len);
    printf("nodes explored:  %ld\n", r->nodes_explored);
    printf("heap pushes:     %ld\n", r->heap_pushes);
    printf("query time:      %.0f us\n", r->time_us);
}

static void print_json(const Graph *g, Algo algo, const SearchResult *r, int32_t s, int32_t e,
                       double sd, double ed)
{
    printf("{\"algorithm\":\"%s\",\"found\":%s,", algo_name(algo), r->found ? "true" : "false");
    printf("\"start_node\":%d,\"end_node\":%d,", s, e);
    printf("\"start_snap_m\":%.2f,\"end_snap_m\":%.2f,", sd, ed);
    printf("\"distance_m\":%.2f,\"nodes_explored\":%ld,\"heap_pushes\":%ld,\"time_us\":%.0f,",
           r->found ? r->cost_m : 0.0, r->nodes_explored, r->heap_pushes, r->time_us);
    printf("\"path\":[");
    for (int32_t i = 0; i < r->path_len; i++)
        printf("%s[%.7f,%.7f]", i ? "," : "", g->lat[r->path[i]], g->lon[r->path[i]]);
    printf("]");
    if (r->explored) { /* settled nodes, in the order they were settled */
        printf(",\"explored\":[");
        for (long i = 0; i < r->nodes_explored; i++)
            printf("%s[%.7f,%.7f]", i ? "," : "", g->lat[r->explored[i]],
                   g->lon[r->explored[i]]);
        printf("]");
    }
    printf("}\n");
}

static int run_query(const Graph *g, int argc, char **argv)
{
    double c[4];
    Algo algo = ALGO_ASTAR;
    bool json = false, explored = false;

    if (argc < 6) {
        usage();
        return 1;
    }
    for (int i = 0; i < 4; i++) {
        if (!parse_double_arg(argv[2 + i], &c[i])) {
            fprintf(stderr, "route: bad coordinate \"%s\"\n", argv[2 + i]);
            return 1;
        }
    }
    for (int i = 6; i < argc; i++) {
        if (strcmp(argv[i], "--json") == 0) {
            json = true;
        } else if (strcmp(argv[i], "--explored") == 0) {
            explored = true;
        } else if (strcmp(argv[i], "--algo") == 0 && i + 1 < argc) {
            i++;
            if (strcmp(argv[i], "dijkstra") == 0)
                algo = ALGO_DIJKSTRA;
            else if (strcmp(argv[i], "astar") == 0)
                algo = ALGO_ASTAR;
            else {
                fprintf(stderr, "route: unknown algorithm \"%s\"\n", argv[i]);
                return 1;
            }
        } else {
            usage();
            return 1;
        }
    }

    if (explored && !json) {
        fprintf(stderr, "route: --explored requires --json\n");
        return 1;
    }

    double sd, ed;
    int32_t s = nearest_node(g, c[0], c[1], &sd);
    int32_t e = nearest_node(g, c[2], c[3], &ed);
    SearchResult r;
    if (s < 0 || e < 0 || search_run_opts(g, algo, s, e, explored, &r) != 0) {
        fprintf(stderr, "route: search failed\n");
        return 1;
    }
    if (json)
        print_json(g, algo, &r, s, e, sd, ed);
    else
        print_text(algo, &r, s, e, sd, ed);
    int rc = r.found ? 0 : 2;
    search_result_free(&r);
    return rc;
}

/* ---- benchmark -------------------------------------------------------- */

static uint64_t rng_state;

static uint64_t rng_next(void) /* xorshift64 */
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}

typedef struct {
    double explored, time_us, pushes, path_m;
    long found;
} Totals;

static int run_bench(const Graph *g, unsigned long n_queries, unsigned long seed)
{
    Totals tot[2];
    const Algo algos[2] = {ALGO_DIJKSTRA, ALGO_ASTAR};
    long mismatches = 0;

    memset(tot, 0, sizeof tot);
    if (g->n_nodes < 2) {
        fprintf(stderr, "route: graph too small to benchmark\n");
        return 1;
    }
    rng_state = seed ? seed : 1;

    for (unsigned long q = 0; q < n_queries; q++) {
        int32_t s = (int32_t)(rng_next() % (uint64_t)g->n_nodes);
        int32_t e = (int32_t)(rng_next() % (uint64_t)g->n_nodes);
        SearchResult r[2];
        for (int a = 0; a < 2; a++) {
            if (search_run(g, algos[a], s, e, &r[a]) != 0) {
                fprintf(stderr, "route: search failed\n");
                return 1;
            }
            if (r[a].found) {
                tot[a].found++;
                tot[a].path_m += r[a].cost_m;
            }
            tot[a].explored += (double)r[a].nodes_explored;
            tot[a].pushes += (double)r[a].heap_pushes;
            tot[a].time_us += r[a].time_us;
        }
        if (r[0].found != r[1].found || (r[0].found && fabs(r[0].cost_m - r[1].cost_m) > 1e-6))
            mismatches++;
        search_result_free(&r[0]);
        search_result_free(&r[1]);
    }

    double n = (double)n_queries;
    printf("Benchmark: %lu random queries, %d nodes, %d edges, seed %lu\n\n", n_queries,
           g->n_nodes, g->n_edges, seed);
    printf("%-10s %14s %14s %14s %16s\n", "algorithm", "avg explored", "avg pushes",
           "avg time (us)", "avg path (m)");
    for (int a = 0; a < 2; a++) {
        double found = tot[a].found ? (double)tot[a].found : 1.0;
        printf("%-10s %14.1f %14.1f %14.1f %16.1f\n", algo_name(algos[a]), tot[a].explored / n,
               tot[a].pushes / n, tot[a].time_us / n, tot[a].path_m / found);
    }
    if (tot[0].explored > 0)
        printf("\nA* explored %.1f%% fewer nodes and took %.1f%% less time than Dijkstra.\n",
               100.0 * (1.0 - tot[1].explored / tot[0].explored),
               100.0 * (1.0 - tot[1].time_us / tot[0].time_us));
    printf("Cost mismatches between the two algorithms: %ld\n", mismatches);
    return mismatches ? 1 : 0;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        usage();
        return 1;
    }

    Graph g;
    char err[256];
    if (graph_load(&g, argv[1], err, sizeof err) != 0) {
        fprintf(stderr, "route: %s\n", err);
        return 1;
    }

    int rc;
    if (strcmp(argv[2], "--bench") == 0) {
        unsigned long n = 1000, seed = 42;
        int i = 3;
        if (i < argc && argv[i][0] != '-') {
            if (!parse_ulong_arg(argv[i], &n) || n == 0) {
                usage();
                graph_free(&g);
                return 1;
            }
            i++;
        }
        if (i < argc && strcmp(argv[i], "--seed") == 0 && i + 1 < argc) {
            if (!parse_ulong_arg(argv[i + 1], &seed)) {
                usage();
                graph_free(&g);
                return 1;
            }
            i += 2;
        }
        if (i != argc) {
            usage();
            graph_free(&g);
            return 1;
        }
        rc = run_bench(&g, n, seed);
    } else {
        rc = run_query(&g, argc, argv);
    }
    graph_free(&g);
    return rc;
}
