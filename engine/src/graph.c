#include "graph.h"

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "geo.h"

#define NODES_HEADER "id,osm_id,lat,lon,elev_m"
#define EDGES_HEADER "from,to,length_m,is_stairs,highway"
#define NODE_FIELDS 5
#define EDGE_FIELDS 5

/* Largest amount an edge may be shorter than the straight line between its
 * endpoints and still be accepted as rounding noise. */
#define CLAMP_TOLERANCE_M 1.0

static void set_err(char *err, size_t errlen, const char *fmt, ...)
{
    va_list ap;
    if (!err || errlen == 0)
        return;
    va_start(ap, fmt);
    vsnprintf(err, errlen, fmt, ap);
    va_end(ap);
}

void graph_free(Graph *g)
{
    free(g->lat);
    free(g->lon);
    free(g->offsets);
    free(g->edges);
    memset(g, 0, sizeof *g);
}

int graph_build(Graph *g, int32_t n_nodes, const double *lat, const double *lon,
                const EdgeRec *edges, int32_t n_edges, char *err, size_t errlen)
{
    memset(g, 0, sizeof *g);
    if (n_nodes < 0 || n_edges < 0) {
        set_err(err, errlen, "negative node or edge count");
        return -1;
    }

    for (int32_t i = 0; i < n_edges; i++) {
        const EdgeRec *e = &edges[i];
        if (e->from < 0 || e->from >= n_nodes || e->to < 0 || e->to >= n_nodes) {
            set_err(err, errlen, "edge %d references node outside 0..%d", i, n_nodes - 1);
            return -1;
        }
        if (!(e->length_m > 0.0) || !isfinite(e->length_m)) {
            set_err(err, errlen, "edge %d has non-positive length", i);
            return -1;
        }
        double straight = haversine_m(lat[e->from], lon[e->from], lat[e->to], lon[e->to]);
        if (e->length_m < straight - CLAMP_TOLERANCE_M) {
            set_err(err, errlen,
                    "edge %d (%d->%d) is %.1f m but its endpoints are %.1f m apart",
                    i, e->from, e->to, e->length_m, straight);
            return -1;
        }
    }

    g->n_nodes = n_nodes;
    g->n_edges = n_edges;
    g->lat = malloc((size_t)(n_nodes ? n_nodes : 1) * sizeof *g->lat);
    g->lon = malloc((size_t)(n_nodes ? n_nodes : 1) * sizeof *g->lon);
    g->offsets = calloc((size_t)n_nodes + 1, sizeof *g->offsets);
    g->edges = malloc((size_t)(n_edges ? n_edges : 1) * sizeof *g->edges);
    int32_t *cursor = malloc((size_t)(n_nodes ? n_nodes : 1) * sizeof *cursor);
    if (!g->lat || !g->lon || !g->offsets || !g->edges || !cursor) {
        set_err(err, errlen, "out of memory");
        free(cursor);
        graph_free(g);
        return -1;
    }
    memcpy(g->lat, lat, (size_t)n_nodes * sizeof *lat);
    memcpy(g->lon, lon, (size_t)n_nodes * sizeof *lon);

    /* Counting sort of edges by source node. */
    for (int32_t i = 0; i < n_edges; i++)
        g->offsets[edges[i].from + 1]++;
    for (int32_t u = 0; u < n_nodes; u++)
        g->offsets[u + 1] += g->offsets[u];
    memcpy(cursor, g->offsets, (size_t)n_nodes * sizeof *cursor);

    for (int32_t i = 0; i < n_edges; i++) {
        const EdgeRec *e = &edges[i];
        double straight = haversine_m(lat[e->from], lon[e->from], lat[e->to], lon[e->to]);
        double len = e->length_m;
        if (len < straight) {
            if (straight - len > g->max_clamp_m)
                g->max_clamp_m = straight - len;
            len = straight;
            g->n_clamped++;
        }
        Edge *out = &g->edges[cursor[e->from]++];
        out->to = e->to;
        out->flags = e->flags;
        out->length_m = len;
    }
    free(cursor);
    return 0;
}

/* ---- CSV loading ------------------------------------------------------ */

typedef struct {
    FILE *f;
    char *buf;
    size_t cap;
    long line;
    char path[1100];
} Csv;

static int csv_open(Csv *c, const char *dir, const char *name, const char *header,
                    char *err, size_t errlen)
{
    memset(c, 0, sizeof *c);
    snprintf(c->path, sizeof c->path, "%s/%s", dir, name);
    c->f = fopen(c->path, "r");
    if (!c->f) {
        set_err(err, errlen, "cannot open %s", c->path);
        return -1;
    }
    ssize_t n = getline(&c->buf, &c->cap, c->f);
    c->line = 1;
    while (n > 0 && (c->buf[n - 1] == '\n' || c->buf[n - 1] == '\r'))
        c->buf[--n] = '\0';
    if (n <= 0 || strcmp(c->buf, header) != 0) {
        set_err(err, errlen, "%s: expected header \"%s\"", c->path, header);
        return -1;
    }
    return 0;
}

static void csv_close(Csv *c)
{
    if (c->f)
        fclose(c->f);
    free(c->buf);
    memset(c, 0, sizeof *c);
}

/* Reads the next non-blank row and splits it into exactly nfields fields
 * (modifying the line in place). Returns 1 for a row, 0 at end of file,
 * -1 on error. */
static int csv_next(Csv *c, char **fields, int nfields, char *err, size_t errlen)
{
    for (;;) {
        ssize_t n = getline(&c->buf, &c->cap, c->f);
        if (n < 0)
            return 0;
        c->line++;
        while (n > 0 && (c->buf[n - 1] == '\n' || c->buf[n - 1] == '\r'))
            c->buf[--n] = '\0';
        if (n == 0)
            continue;

        int count = 0;
        char *p = c->buf;
        fields[count++] = p;
        for (; *p; p++) {
            if (*p == ',') {
                *p = '\0';
                if (count == nfields) {
                    set_err(err, errlen, "%s:%ld: too many fields", c->path, c->line);
                    return -1;
                }
                fields[count++] = p + 1;
            }
        }
        if (count != nfields) {
            set_err(err, errlen, "%s:%ld: expected %d fields, got %d", c->path, c->line,
                    nfields, count);
            return -1;
        }
        return 1;
    }
}

static int parse_long(const char *s, long *out)
{
    char *end;
    if (*s == '\0')
        return -1;
    *out = strtol(s, &end, 10);
    return *end == '\0' ? 0 : -1;
}

static int parse_double(const char *s, double *out)
{
    char *end;
    if (*s == '\0')
        return -1;
    *out = strtod(s, &end);
    return (*end == '\0' && isfinite(*out)) ? 0 : -1;
}

typedef struct {
    double *lat, *lon;
    int32_t n, cap;
} NodeVec;

typedef struct {
    EdgeRec *v;
    int32_t n, cap;
} EdgeVec;

static int load_nodes(const char *dir, NodeVec *nv, char *err, size_t errlen)
{
    Csv csv;
    char *f[NODE_FIELDS];
    int rc;

    if (csv_open(&csv, dir, "nodes.csv", NODES_HEADER, err, errlen) != 0) {
        csv_close(&csv);
        return -1;
    }
    while ((rc = csv_next(&csv, f, NODE_FIELDS, err, errlen)) == 1) {
        long id;
        double la, lo;
        if (parse_long(f[0], &id) != 0 || id != nv->n) {
            set_err(err, errlen, "%s:%ld: node ids must be 0,1,2,... in order", csv.path,
                    csv.line);
            rc = -1;
            break;
        }
        if (parse_double(f[2], &la) != 0 || parse_double(f[3], &lo) != 0 || la < -90.0 ||
            la > 90.0 || lo < -180.0 || lo > 180.0) {
            set_err(err, errlen, "%s:%ld: bad lat/lon", csv.path, csv.line);
            rc = -1;
            break;
        }
        if (nv->n == nv->cap) {
            int32_t cap = nv->cap ? nv->cap * 2 : 1024;
            double *a = realloc(nv->lat, (size_t)cap * sizeof *a);
            if (a)
                nv->lat = a;
            double *b = realloc(nv->lon, (size_t)cap * sizeof *b);
            if (b)
                nv->lon = b;
            if (!a || !b) {
                set_err(err, errlen, "out of memory");
                rc = -1;
                break;
            }
            nv->cap = cap;
        }
        nv->lat[nv->n] = la;
        nv->lon[nv->n] = lo;
        nv->n++;
    }
    csv_close(&csv);
    return rc;
}

static int load_edges(const char *dir, EdgeVec *ev, char *err, size_t errlen)
{
    Csv csv;
    char *f[EDGE_FIELDS];
    int rc;

    if (csv_open(&csv, dir, "edges.csv", EDGES_HEADER, err, errlen) != 0) {
        csv_close(&csv);
        return -1;
    }
    while ((rc = csv_next(&csv, f, EDGE_FIELDS, err, errlen)) == 1) {
        long from, to;
        double len;
        if (parse_long(f[0], &from) != 0 || parse_long(f[1], &to) != 0 ||
            parse_double(f[2], &len) != 0 || (strcmp(f[3], "0") != 0 && strcmp(f[3], "1") != 0)) {
            set_err(err, errlen, "%s:%ld: malformed edge row", csv.path, csv.line);
            rc = -1;
            break;
        }
        if (ev->n == ev->cap) {
            int32_t cap = ev->cap ? ev->cap * 2 : 4096;
            EdgeRec *v = realloc(ev->v, (size_t)cap * sizeof *v);
            if (!v) {
                set_err(err, errlen, "out of memory");
                rc = -1;
                break;
            }
            ev->v = v;
            ev->cap = cap;
        }
        EdgeRec *e = &ev->v[ev->n++];
        e->from = (int32_t)from;
        e->to = (int32_t)to;
        e->length_m = len;
        e->flags = f[3][0] == '1' ? EDGE_STAIRS : 0;
    }
    csv_close(&csv);
    return rc;
}

int graph_load(Graph *g, const char *dir, char *err, size_t errlen)
{
    NodeVec nv = {0};
    EdgeVec ev = {0};
    int rc = -1;

    memset(g, 0, sizeof *g);
    if (load_nodes(dir, &nv, err, errlen) == 0 && load_edges(dir, &ev, err, errlen) == 0)
        rc = graph_build(g, nv.n, nv.lat, nv.lon, ev.v, ev.n, err, errlen);

    free(nv.lat);
    free(nv.lon);
    free(ev.v);
    return rc;
}
