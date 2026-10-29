/* Stage 1. SPDX-License-Identifier: MIT */
#ifndef TIREMODEL_H
#define TIREMODEL_H

typedef struct { double B, C, D, E; } tm_mf_params;
/* D is a friction coefficient; peak force is D * Fz. */
double tm_mf_fy(double alpha, double Fz, const tm_mf_params *p);
double tm_mf_dfy_dalpha(double alpha, double Fz, const tm_mf_params *p);

typedef struct { tm_mf_params mf; double sigma, Fz0; } tm_tire_params;
typedef struct tm_tire tm_tire;
enum { TM_OK = 0, TM_INVALID = 1, TM_TIME = 2 };
tm_tire *tm_tire_new(const tm_tire_params *p);
void tm_tire_free(tm_tire *tire);
int tm_tire_reset(tm_tire *tire, double t0, double alpha0);
int tm_tire_step(tm_tire *tire, double t, double dt, double alpha, double vx, double Fz);
double tm_tire_get_fy(const tm_tire *tire);
/* Snapshot layout: [time, lagged slip, force]; n must be 3. */
int tm_tire_get_state(const tm_tire *tire, double *buf, int n);
int tm_tire_set_state(tm_tire *tire, const double *buf, int n);
#endif
