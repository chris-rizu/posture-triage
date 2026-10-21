// How the measured tilts are spread along the spine (used by skeleton.js).
// IMU3 -> L3, IMU2 -> T12, IMU1 -> C7; linear in between, extrapolated below L3,
// easing toward an upright head above C7. The viewer applies the change from the
// reference posture (REF) on top of the real anatomy of the model.
// Coordinates: +Y up, +Z anterior, +X the person's left. Degrees.

export const NAMES = ['L5', 'L4', 'L3', 'L2', 'L1',
  'T12', 'T11', 'T10', 'T9', 'T8', 'T7', 'T6', 'T5', 'T4', 'T3', 'T2', 'T1',
  'C7', 'C6', 'C5', 'C4', 'C3', 'C2', 'C1'];
export const IDX = Object.fromEntries(NAMES.map((n, i) => [n, i]));
const I_L3 = IDX.L3, I_T12 = IDX.T12, I_T5 = IDX.T5, I_C7 = IDX.C7;

export const region = (i) => (i < 5 ? 'L' : i < 17 ? 'T' : 'C');
export function bodyHeight(i) {
  if (i < 5) return 0.027;
  if (i < 17) return 0.023 - 0.007 * ((i - 5) / 11);
  return i < 23 ? 0.012 : 0.010;
}
export const disc = (i) => (i < 5 ? 0.010 : i < 17 ? 0.005 : 0.0045);
export const seg = (i) => bodyHeight(i) + disc(i);

export const REF = { s: [28, -10, 12, 20, 20], f: [0, 0, 0, 0, 0] };
const lerp = (a, b, t) => a + (b - a) * t;

export function tiltProfile(s1, s2, s3) {
  const th = new Array(24).fill(0);
  const m = (s3 - s2) / (I_T12 - I_L3);
  for (let i = 0; i < 24; i++) {
    if (i <= I_L3) th[i] = s3 + m * (I_L3 - i) * 0.9;
    else if (i <= I_T12) th[i] = lerp(s3, s2, (i - I_L3) / (I_T12 - I_L3));
    else if (i <= I_C7) th[i] = lerp(s2, s1, (i - I_T12) / (I_C7 - I_T12));
    else th[i] = lerp(s1, s1 - 30, (i - I_C7) / (23 - I_C7));
  }
  return th;
}

export function sideProfile(f1, f2, f3) {
  const ph = new Array(24).fill(0);
  for (let i = 0; i < 24; i++) {
    if (i <= I_L3) ph[i] = f3;
    else if (i <= I_T12) ph[i] = lerp(f3, f2, (i - I_L3) / (I_T12 - I_L3));
    else if (i <= I_C7) ph[i] = lerp(f2, f1, (i - I_T12) / (I_C7 - I_T12));
    else ph[i] = lerp(f1, f1 * 0.4, (i - I_C7) / (23 - I_C7));
  }
  return ph;
}

export function twistProfile(rL3, rT12, rScap) {
  const tw = new Array(24).fill(0);
  for (let i = 0; i < 24; i++) {
    if (i <= I_L3) tw[i] = rL3 * (i / I_L3);
    else if (i <= I_T12) tw[i] = lerp(rL3, rT12, (i - I_L3) / (I_T12 - I_L3));
    else if (i <= I_T5) tw[i] = lerp(rT12, rScap, (i - I_T12) / (I_T5 - I_T12));
    else if (i <= I_C7) tw[i] = lerp(rScap, rScap * 0.4, (i - I_T5) / (I_C7 - I_T5));
    else tw[i] = rScap * 0.4 * (1 - (i - I_C7) / (23 - I_C7));
  }
  return tw;
}

const d2r = Math.PI / 180;
/** Rz(phi) * Rx(theta) * Ry(psi) as a row-major 3x3 array. */
export function rot(theta, phi, psi) {
  const t = theta * d2r, p = phi * d2r, s = psi * d2r;
  const ct = Math.cos(t), st = Math.sin(t), cp = Math.cos(p), sp = Math.sin(p), cs = Math.cos(s), ss = Math.sin(s);
  const rz = [[cp, -sp, 0], [sp, cp, 0], [0, 0, 1]];
  const rx = [[1, 0, 0], [0, ct, -st], [0, st, ct]];
  const ry = [[cs, 0, ss], [0, 1, 0], [-ss, 0, cs]];
  const mul = (a, b) => a.map((row, i) => [0, 1, 2].map((j) => row[0] * b[0][j] + row[1] * b[1][j] + row[2] * b[2][j]));
  return mul(mul(rz, rx), ry);
}
export const apply = (m, v) => [0, 1, 2].map((i) => m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2]);
