#ifndef GEO_H
#define GEO_H

/* Same radius osmnx uses, so straight-line distances are comparable to the
 * edge lengths exported by the data pipeline. */
#define EARTH_RADIUS_M 6371009.0

/* Great-circle distance in meters between two lat/lon points (degrees). */
double haversine_m(double lat1, double lon1, double lat2, double lon2);

#endif
