#include "geo.h"

#include <math.h>

#define PI 3.14159265358979323846 /* M_PI is not part of strict C11 */

static double deg2rad(double d) { return d * (PI / 180.0); }

double haversine_m(double lat1, double lon1, double lat2, double lon2)
{
    double p1 = deg2rad(lat1), p2 = deg2rad(lat2);
    double dp = p2 - p1;
    double dl = deg2rad(lon2 - lon1);
    double s1 = sin(dp / 2.0), s2 = sin(dl / 2.0);
    double a = s1 * s1 + cos(p1) * cos(p2) * s2 * s2;
    if (a > 1.0)
        a = 1.0;
    return 2.0 * EARTH_RADIUS_M * asin(sqrt(a));
}
