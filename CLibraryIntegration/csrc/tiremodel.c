/* SPDX-License-Identifier: MIT */
#include "tiremodel.h"
#include <math.h>
#include <float.h>
#include <stdlib.h>

struct tm_tire { tm_tire_params p; double time, alpha_l, fy; };

double tm_mf_fy(double alpha, double Fz, const tm_mf_params *p) {
    double x = p->B * alpha;
    return p->D * Fz * sin(p->C * atan(x - p->E * (x - atan(x))));
}

double tm_mf_dfy_dalpha(double alpha, double Fz, const tm_mf_params *p) {
    double x = p->B * alpha;
    double q = x - p->E * (x - atan(x));
    double dq = p->B * (1 - p->E + p->E / (1 + x*x));
    return p->D * Fz * cos(p->C * atan(q)) * p->C * dq / (1 + q*q);
}

tm_tire *tm_tire_new(const tm_tire_params *p) {
    if (!p || !(p->sigma > 0) || !isfinite(p->sigma) ||
        !(p->Fz0 >= 0) || !isfinite(p->Fz0)) return NULL;
    tm_tire *tire = calloc(1, sizeof(*tire));
    if (tire) tire->p = *p;
    return tire;
}
void tm_tire_free(tm_tire *tire) { free(tire); }

int tm_tire_reset(tm_tire *tire, double t0, double alpha0) {
    if (!tire || !isfinite(t0) || !isfinite(alpha0)) return TM_INVALID;
    tire->time = t0;
    tire->alpha_l = alpha0;
    tire->fy = tm_mf_fy(alpha0, tire->p.Fz0, &tire->p.mf);
    return TM_OK;
}
int tm_tire_step(tm_tire *tire, double t, double dt, double alpha, double vx, double Fz) {
    if (!tire || !isfinite(t) || !isfinite(dt) || !(dt > 0) ||
        !isfinite(alpha) || !isfinite(vx) || vx < 0 || !isfinite(Fz) || Fz < 0)
        return TM_INVALID;
    if (fabs(t - tire->time) > 32 * DBL_EPSILON * fmax(1, fabs(t))) return TM_TIME;
    /* expm1 retains accuracy for short communication steps. */
    tire->alpha_l += (alpha - tire->alpha_l) * -expm1(-vx * dt / tire->p.sigma);
    tire->fy = tm_mf_fy(tire->alpha_l, Fz, &tire->p.mf);
    tire->time = t + dt;
    return TM_OK;
}
double tm_tire_get_fy(const tm_tire *tire) { return tire ? tire->fy : NAN; }
int tm_tire_get_state(const tm_tire *tire, double *buf, int n) {
    if (!tire || !buf || n != 3) return TM_INVALID;
    buf[0] = tire->time; buf[1] = tire->alpha_l; buf[2] = tire->fy;
    return TM_OK;
}
int tm_tire_set_state(tm_tire *tire, const double *buf, int n) {
    if (!tire || !buf || n != 3 || !isfinite(buf[0]) || !isfinite(buf[1]) || !isfinite(buf[2]))
        return TM_INVALID;
    tire->time = buf[0]; tire->alpha_l = buf[1]; tire->fy = buf[2];
    return TM_OK;
}
