""" Cython versions of low-level functions for computing vector geometry. """

import numpy as np
cimport numpy as np
from cpython cimport bool
from libc.math cimport sqrt, sin, cos, tan, asin, acos, atan, atan2
from coordstring cimport CoordString

def isleft(tuple pt0, tuple pt1, tuple pt2):
    return (pt1[0]-pt0[0])*(pt2[1]-pt0[1]) - (pt1[1]-pt0[1])*(pt2[0]-pt0[0]) > 0.0

def polarangle(tuple pt0, tuple pt1):
    """ Return the polar angle from pt0 to pt1 """
    return atan2(pt1[1]-pt0[1], pt1[0]-pt0[0])

cdef struct Vector2:
    double x
    double y

cdef struct Vector3:
    double x
    double y
    double z

cdef inline double dot2(Vector2 u, Vector2 v) nogil:
    return u.x*v.x + u.y*v.y

cdef inline double dot3(Vector3 u, Vector3 v) nogil:
    return u.x*v.x + u.y*v.y + u.z*v.z

cdef inline double cross2(Vector2 u, Vector2 v) nogil:
    return u.x*v.y - u.y*v.x

cdef inline Vector3 cross3(Vector3 u, Vector3 v):
    return Vector3(u.y*v.z - u.z*v.y, u.z*v.x - u.x*v.z, u.x*v.y - u.y*v.x)

cdef Vector2 proj2(Vector2 u, Vector2 v):
    cdef double uv_vv
    uv_vv = dot2(u, v) / dot2(v, v)
    return Vector2(uv_vv*v.x, uv_vv*v.y)

cdef inline double dist2(Vector2 pt0, Vector2 pt1) nogil:
    return sqrt((pt0.x-pt1.x)**2 + (pt0.y-pt1.y)**2)

cdef inline double mind(double a, double b) nogil:
    if a <= b:
        return a
    else:
        return b

cdef inline double maxd(double a, double b) nogil:
    if a >= b:
        return a
    else:
        return b

cdef inline double absd(double a) nogil:
    if a < 0:
        return -a
    else:
        return a

cdef inline Vector3 sph2cart(Vector2 a):
    """ Convert a (lambda, phi) coordinate on a sphere with an origin at
    (0, 0, 0) to an (x, y, z) coordinate. """
    cdef double theta = 90.0 - a.y
    return Vector3(sin(np.pi*theta/180.0)*cos(np.pi*a.x/180.0),
                   sin(np.pi*theta/180.0)*sin(np.pi*a.x/180.0),
                   cos(np.pi*theta/180.0))

cdef inline Vector2 cart2sph(Vector3 a):
    """ Convert an (x, y, z) coordinate to a (lambda, phi) coordinate on a
    sphere with an origin at (0, 0, 0). """
    cdef double lon = 0.0
    cdef double lat = 0.0
    if absd(a.x) > 1e-8:
        lon = atan2(a.y, a.x)
    else:
        lon = asin(a.y / sqrt(a.x*a.x + a.y*a.y))
    if absd(a.z) > 1e-8:
        lat = 0.5*np.pi - atan(sqrt(a.x*a.x + a.y*a.y)/a.z)
    else:
        lat = 0.5*np.pi - acos(a.z / sqrt(a.x*a.x + a.y*a.y + a.z*a.z))
    return Vector2(lon*180.0/np.pi, lat*180.0/np.pi)

cdef Vector3 eulerpole_cart(Vector3 a, Vector3 b):
    return cross3(a, b)

cdef Vector3 eulerpole(Vector2 a, Vector2 b):
    cdef Vector3 ac = sph2cart(a)
    cdef Vector3 bc = sph2cart(b)
    cdef ep = cross3(ac, bc)
    return ep

cdef double azimuth(Vector2 pt1, Vector2 pt2):
    return atan2(pt2.x-pt1.x, pt2.y-pt1.y)

cdef double azimuth_sph(Vector2 pt1, Vector2 pt2):
    cdef double dlon = pt2.x - pt1.x
    cdef az = 0.0
    if (cos(pt1.y) * tan(pt2.y) - sin(pt1.y) * cos(dlon)) == 0:
        az = 0.5*np.pi
    else:
        az = atan2(sin(dlon), cos(pt1.y) * tan(pt2.y) - sin(pt1.y) * cos(dlon))
    return az

def length(CoordString cs):
    """ Compute planar length of CoordString """
    cdef int n = len(cs)
    if cs.ring:
        n += 1
    cdef int i = 0
    cdef double d = 0.0
    cdef double x0, y0, x1, y1
    x0 = cs.getX(i)
    y0 = cs.getY(i)
    while i != (n-1):
        x1 = cs.getX(i+1)
        y1 = cs.getY(i+1)
        d += sqrt((x1-x0)*(x1-x0) + (y1-y0)*(y1-y0))
        x0 = x1
        y0 = y1
        i += 1
    return d

def pt_nearest_planar(double x, double y,
                      double endpt0_0, double endpt0_1,
                      double endpt1_0, double endpt1_1):
    """ Determines the point on a segment defined by pairs endpt1
    and endpt2 nearest to a point defined by x, y.
    Returns the a nested tuple of (point, distance)
    """

    cdef double u0, u1, v0, v1
    cdef Vector2 u_on_v, u_int, pt, pt0, pt1
    cdef Vector2 u, v

    pt = Vector2(x, y)
    pt0 = Vector2(endpt0_0, endpt0_1)
    pt1 = Vector2(endpt1_0, endpt1_1)

    u = Vector2(x - pt0.x, y - pt0.y)
    v = Vector2(pt1.x - pt0.x, pt1.y - pt0.y)
    u_on_v = proj2(u, v)
    u_int = Vector2(u_on_v.x + pt0.x, u_on_v.y + pt0.y)

    # Determine whether u_int is inside the segment
    # Otherwise return the nearest endpoint
    if absd(pt0.x - pt1.x) < 1e-4:  # Segment is near vertical
        if u_int.y > maxd(pt0.y, pt1.y):
            if pt0.y > pt1.y:
                return ((pt0.x, pt0.y), dist2(pt0, pt))
            else:
                return ((pt1.x, pt1.y), dist2(pt1, pt))

        elif u_int.y < mind(pt0.y, pt1.y):
            if pt0.y < pt1.y:
                return ((pt0.x, pt0.y), dist2(pt0, pt))
            else:
                return ((pt1.x, pt1.y), dist2(pt1, pt))

        else:
            return ((u_int.x, u_int.y), dist2(u_int, pt))

    else:

        if u_int.x > maxd(pt0.x, pt1.x):
            if pt0.x > pt1.x:
                return ((pt0.x, pt0.y), dist2(pt0, pt))
            else:
                return ((pt1.x, pt1.y), dist2(pt1, pt))

        elif u_int.x < mind(pt0.x, pt1.x):
            if pt0.x < pt1.x:
                return ((pt0.x, pt0.y), dist2(pt0, pt))
            else:
                return ((pt1.x, pt1.y), dist2(pt1, pt))

        else:
            return ((u_int.x, u_int.y), dist2(u_int, pt))

# Currently unused, but could be employed to optimize pyproj function calls
ctypedef tuple (*fwd_t)(double, double, double, double)
ctypedef tuple (*inv_t)(double, double, double, double)

cdef double _along_distance(object fwd, object inv, double x0, double y0,
        double xp, double yp, double az, double f):
    """ Return the distance between a point distance f along azimuth az away
    from (x0, y0) from (xp, yp). """
    cdef double trialx, trialy, _, d
    (trialx, trialy, _) = fwd(x0, y0, az, f)
    (_, _, d) = inv(trialx, trialy, xp, yp)
    return d

cdef double _along_distance_gradient(object fwd, object inv, double x0, double y0,
        double xp, double yp, double az, double f, double dx):
    """ Return the numerical gradient in terms of f of _along_distance """
    cdef double d1, d2
    d1 = _along_distance(fwd, inv, x0, y0, xp, yp, az, f)
    d2 = _along_distance(fwd, inv, x0, y0, xp, yp, az, f+dx)
    return (d2-d1)/dx

def pt_nearest_proj(object fwd, object inv, tuple pt, double[:] endpt0, double[:] endpt1,
        float tol=0.1, int maxiter=100):
    """ Given geodetic functions *fwd* and *inv*, a *pt*, and an arc from
    *endpt1* to *endpt2*, return the point on the arc that is nearest *pt*.

    Scheme employs a bisection minimization method. Iteration continues until a
    tolerance *tol* in meters is reached, or *maxiter* iterations are
    exhausted. If the iteration limit is reached, a ConvergenceError is raised.
    """
    cdef double az, az2, L
    (az, az2, L) = inv(endpt0[0], endpt0[1], endpt1[0], endpt1[1])

    # Detect whether the nearest point is at an endpoint
    cdef double grad0, grad1, d
    grad0 = _along_distance_gradient(fwd, inv, endpt0[0], endpt0[1], pt[0], pt[1], az, 0, 1e-7*L)
    grad1 = _along_distance_gradient(fwd, inv, endpt0[0], endpt0[1], pt[0], pt[1], az, L, 1e-7*L)
    if grad0 > 0:
        d = _along_distance(fwd, inv, endpt0[0], endpt0[1], pt[0], pt[1], az, 0)
        return endpt0, d
    elif grad1 < 0:
        d = _along_distance(fwd, inv, endpt0[0], endpt0[1], pt[0], pt[1], az, L)
        return endpt1, d

    # Bisection iteration
    cdef double x0 = 0.0, x1 = 1.0, xm = 0.0, xn = 0.0, yn = 0.0
    cdef int i = 0
    cdef double dx = tol + 1.0
    cdef double grad

    while dx > tol:
        if i == maxiter:
            raise ConvergenceError("Maximum iterations exhausted in bisection "
                                   "method.")
        xm = 0.5 * (x0 + x1)
        grad = _along_distance_gradient(fwd, inv, endpt0[0], endpt0[1], pt[0], pt[1], az, xm*L, 1e-7*L)
        if grad > 0:
            dx = absd(x1-xm) * L
            x1 = xm
        else:
            dx = absd(x0-xm) * L
            x0 = xm
        i += 1

    (xn, yn, _) = fwd(endpt0[0], endpt0[1], az, xm*L)
    d = _along_distance(fwd, inv, endpt0[0], endpt0[1], pt[0], pt[1], az, xm*L)
    return (xn, yn), d

class ConvergenceError(Exception):
    def __init__(self, message=''):
        self.message = message
    def __str__(self):
        return self.message
