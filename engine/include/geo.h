#ifndef GEO_H
#define GEO_H

/* Same radius osmnx uses, so straight-line distances are comparable to the
 * edge lengths exported by the data pipeline. */
#define EARTH_RADIUS_M 6371009.0

/* Great-circle distance in meters between two lat/lon points (degrees). */
double haversine_m(double lat1, double lon1, double lat2, double lon2);

/* Walking-effort multiplier for an edge climbing `slope` (rise over run, signed).
 * Tobler's hiking function, relative to flat ground, never below 1: a gentle
 * downhill is not credited as faster than flat, so estimated times stay on the
 * safe side and cost >= length keeps the haversine heuristic admissible.
 * |slope| is capped so one noisy elevation sample cannot dominate a route. */
#define SLOPE_CAP 0.30
double grade_factor(double slope);

#endif
