// Live skeleton twin: renders skeleton.glb with three.js and poses the spine from
// the five sensor pods (spine.js). Five numbered pods sit on C7, T12, L3 and the
// shoulder blades, with leader lines to their live angles.
//
// Host API (called by the Flutter app):
//   skel.setLive({s:[5], f:[5], r:[5], ind:{K,L,N,F,S,R}, lim:{K:[mu,mon,ref],...}, sensors:[5], state, bent})
//   skel.setView('back'|'side'|'three'|'front')      skel.setFocus(bool)  (spine only)
//   skel.setAmplify(1|2)                             skel.setLabels(bool)
// Messages to the host: {type:'ready'}, {type:'pod', index}.
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { NAMES, IDX, REF, region, tiltProfile, sideProfile, twistProfile, rot } from './spine.js';

const LABEL_W = 120;
const VIEWS = { back: Math.PI, side: -Math.PI / 2, three: Math.PI * 0.78, front: 0 };
const d2r = Math.PI / 180;

function post(msg) {
  if (window.SkelHost && window.SkelHost.postMessage) window.SkelHost.postMessage(JSON.stringify(msg));
  else if (window.parent && window.parent !== window) window.parent.postMessage({ skel: msg }, '*');
}

const state = {
  live: null, view: 'three', yaw: VIEWS.three, pitch: 0.06, sinceDrag: 99, yawVel: 0,
  focus: false, amplify: 1, labels: true, t: 0,
  // smoothed angles
  s: REF.s.slice(), f: REF.f.slice(), r: [null, null, null, null, null], bend: 0,
};

// ------------------------------------------------------------------ renderer and stage
const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(22, 1, 0.05, 30);
scene.add(new THREE.HemisphereLight(0xf5f8ff, 0xb3bfb8, 1.25));
const key = new THREE.DirectionalLight(0xfff4e8, 2.3);
key.position.set(-0.45, 4.2, 0.9);
key.castShadow = true;
key.shadow.mapSize.set(1024, 1024);
Object.assign(key.shadow.camera, { left: -0.9, right: 0.9, top: 0.9, bottom: -0.9, near: 1, far: 8 });
key.shadow.radius = 5;
key.shadow.bias = -0.0003;
key.shadow.normalBias = 0.004;
scene.add(key);
const back = new THREE.DirectionalLight(0xdbe8ff, 1.4);
back.position.set(1.5, 2.2, -3.0);
scene.add(back);
const fill = new THREE.DirectionalLight(0xffffff, 0.5);
fill.position.set(2.5, 1.0, 1.0);
scene.add(fill);

// floor: a quiet disc with the shadow, and a ring marking the stance
const floor = new THREE.Mesh(new THREE.CircleGeometry(0.75, 64), new THREE.ShadowMaterial({ opacity: 0.14 }));
floor.rotation.x = -Math.PI / 2;
floor.receiveShadow = true;
scene.add(floor);
const ring = new THREE.Mesh(new THREE.RingGeometry(0.34, 0.345, 96), new THREE.MeshBasicMaterial({ color: 0x9fb0a8, transparent: true, opacity: 0.6 }));
ring.rotation.x = -Math.PI / 2;
ring.position.y = 0.001;
scene.add(ring);

const pivot = new THREE.Group();
scene.add(pivot);

// ------------------------------------------------------------------ model
let model = null;
const vert = {}; // name -> node
const nodes = {};
const vertMats = {}; // name -> material (cloned per vertebra for the status tint)
const rest = {};
let restHip = null, restS1 = null;
const otherMats = [];
const pods = []; // {mesh, label, k}
const BONE = new THREE.Color(0xe8e1cf);
const TINT = { monitor: new THREE.Color(0xd99a17), refer: new THREE.Color(0xd2453b) };
const POD_COLOR = 0xe4467c;

function setup(gltf) {
  model = gltf.scene;
  pivot.add(model);
  model.traverse((o) => {
    if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; }
  });
  for (const n of NAMES) {
    vert[n] = model.getObjectByName(n);
    // one material per vertebra so a region can be tinted
    if (vert[n] && vert[n].isMesh) { vert[n].material = vert[n].material.clone(); vertMats[n] = vert[n].material; }
  }
  for (const n of ['Pelvis', 'S1', 'Arm_L', 'Arm_R', 'Scapula_L', 'Scapula_R', 'Skull', 'Pod1', 'Pod2', 'Pod3', 'Pod4', 'Pod5']) {
    nodes[n] = model.getObjectByName(n);
  }
  model.updateMatrixWorld(true);
  for (const n of NAMES) rest[n] = { p: vert[n].position.clone(), q: vert[n].quaternion.clone() };
  restHip = nodes.Pelvis.getWorldPosition(new THREE.Vector3());
  restS1 = nodes.S1.getWorldPosition(new THREE.Vector3());
  // everything that is not a vertebra or disc fades in spine-focus mode
  const spineSet = new Set();
  for (const n of NAMES) vert[n].traverse((o) => { if (o.isMesh && (o === vert[n] || o.name.startsWith('Disc_'))) spineSet.add(o); });
  model.traverse((o) => {
    if (o.isMesh && !spineSet.has(o)) {
      o.material = o.material.clone();
      o.material.transparent = true;
      otherMats.push(o.material);
    }
  });
  addPods();
  model.updateMatrixWorld(true);
  post({ type: 'ready' });
}

function addPods() {
  const geo = new RoundedBoxGeometry(0.036, 0.026, 0.013, 4, 0.004);
  const mat = new THREE.MeshStandardMaterial({ color: 0x24323c, roughness: 0.35, metalness: 0.1 });
  const capMat = new THREE.MeshStandardMaterial({ color: POD_COLOR, roughness: 0.5 });
  const ledGeo = new THREE.SphereGeometry(0.0034, 12, 8);
  for (let k = 0; k < 5; k++) {
    const site = nodes['Pod' + (k + 1)];
    const g = new THREE.Group();
    const body = new THREE.Mesh(geo, mat);
    const strap = new THREE.Mesh(new RoundedBoxGeometry(0.028, 0.040, 0.004, 2, 0.0015), capMat);
    strap.position.z = 0.007;
    const led = new THREE.Mesh(ledGeo, new THREE.MeshBasicMaterial({ color: 0x4fc3f7 }));
    led.position.set(0.011, 0.007, -0.007);
    body.castShadow = true;
    g.add(strap, body, led);
    site.add(g);
    pods.push({ group: g, led, k });
  }
}

// ------------------------------------------------------------------ pose from the sensors
const tmpM = new THREE.Matrix4();
const tmpQ = new THREE.Quaternion();
const qDown = new THREE.Quaternion();

function toQuat(R) {
  tmpM.set(R[0][0], R[0][1], R[0][2], 0, R[1][0], R[1][1], R[1][2], 0, R[2][0], R[2][1], R[2][2], 0, 0, 0, 0, 1);
  return new THREE.Quaternion().setFromRotationMatrix(tmpM);
}

function smoothAngles(dt) {
  const L = state.live;
  const k = 1 - Math.exp(-dt / 0.12);
  const amp = state.amplify;
  const num = (x) => (x === null || x === undefined || Number.isNaN(x) ? null : x);
  for (let p = 0; p < 5; p++) {
    let ts = L && num(L.s && L.s[p]) !== null ? L.s[p] : REF.s[p];
    let tf = L && num(L.f && L.f[p]) !== null ? L.f[p] : 0;
    // amplify the deviation from the reference posture so small changes are visible
    if (amp !== 1 && state.bend < 0.5) { ts = REF.s[p] + amp * (ts - REF.s[p]); tf *= amp; }
    state.s[p] += (ts - state.s[p]) * k;
    state.f[p] += (tf - state.f[p]) * k;
    const tr = L && L.r ? num(L.r[p]) : null;
    if (tr === null) state.r[p] = null;
    else state.r[p] = state.r[p] === null ? tr * amp : state.r[p] + (tr * amp - state.r[p]) * k;
  }
  state.bend = Math.min(1, Math.max(0, (state.s[1] + 10) / 90));
}

const TH_REF = tiltProfile(REF.s[0], REF.s[1], REF.s[2]);
const vA = new THREE.Vector3(), vB = new THREE.Vector3();
const num0 = (v) => (v === null || v === undefined || Number.isNaN(v) ? 0 : v);

/** The rest pose is real anatomy; the change measured by the pods is added on top. */
function pose() {
  const s = state.s, f = state.f, r = state.r;
  const th = tiltProfile(s[0], s[1], s[2]);
  const ph = sideProfile(f[0], f[1], f[2]);
  const rs = r[3] === null || r[4] === null ? null : (r[3] + r[4]) / 2;
  const tw = r[1] === null ? new Array(24).fill(0) : twistProfile(num0(r[2]), num0(r[1]), num0(rs));
  const D = th.map((t, i) => toQuat(rot(t - TH_REF[i], ph[i], tw[i])));
  // pelvis follows most of the change at L5
  const P = toQuat(rot((th[0] - TH_REF[0]) * 0.7, ph[0] * 0.5, 0));
  nodes.Pelvis.quaternion.copy(P);
  const s1 = vA.copy(restS1).sub(restHip).applyQuaternion(P).add(restHip);
  let prev = s1.clone(), prevRest = restS1.clone(), prevD = D[0];
  NAMES.forEach((n, i) => {
    const R = rest[n];
    const Dm = prevD.clone().slerp(D[i], 0.5);
    const off = vB.copy(R.p).sub(prevRest).applyQuaternion(Dm);
    const c = prev.clone().add(off);
    vert[n].position.copy(c);
    vert[n].quaternion.copy(D[i]).multiply(R.q);
    prev = c; prevRest = R.p; prevD = D[i];
  });
  // scapulae follow the shoulder pods: extra side tilt relative to the trunk
  for (const [name, p, sgn] of [['Scapula_L', 3, 1], ['Scapula_R', 4, -1]]) {
    const sc = nodes[name];
    if (!sc) continue;
    if (!sc.userData.rest) sc.userData.rest = { q: sc.quaternion.clone(), p: sc.position.clone() };
    const rel = (num0(state.f[p]) - num0(state.f[1])) * 0.8;
    sc.quaternion.copy(sc.userData.rest.q).multiply(tmpQ.setFromAxisAngle(new THREE.Vector3(0, 0, 1), rel * d2r));
    sc.position.copy(sc.userData.rest.p);
    sc.position.y += -sgn * Math.sin(rel * d2r) * 0.06;
  }
  // arms hang with gravity whatever the trunk does
  model.updateMatrixWorld(true);
  for (const n of ['Arm_L', 'Arm_R']) {
    const a = nodes[n];
    if (!a) continue;
    a.parent.getWorldQuaternion(tmpQ);
    const target = tmpQ.clone().invert().multiply(qDown);
    a.quaternion.slerp(target, 0.25);
  }
}

// ------------------------------------------------------------------ status tint and focus
function tint() {
  const L = state.live;
  const lvl = {};
  const level = (k) => {
    const lim = L && L.lim && L.lim[k], v = L && L.ind ? L.ind[k] : null;
    if (!lim || v === null || v === undefined || Number.isNaN(v)) return 0;
    const d = Math.abs(v - lim[0]);
    return d >= lim[2] ? 2 : d >= lim[1] ? 1 : 0;
  };
  const bent = state.bend > 0.5;
  const N = bent ? 0 : level('N'), K = bent ? 0 : level('K'), Lv = bent ? 0 : level('L'), F = bent ? 0 : level('F');
  const R = bent ? level('R') : 0;
  NAMES.forEach((n, i) => {
    const reg = region(i);
    let w = 0;
    if (reg === 'C') w = N;
    if (reg === 'T') w = Math.max(K, R, i <= IDX.T10 ? F : 0);
    if (reg === 'L') w = Math.max(Lv, F);
    lvl[n] = w;
    const m = vertMats[n];
    if (!m) return;
    const target = w === 2 ? TINT.refer : w === 1 ? TINT.monitor : BONE;
    m.color.lerp(target, 0.15);
  });
  const op = state.focus ? 0.1 : 1;
  for (const m of otherMats) {
    m.opacity += (op - m.opacity) * 0.15;
    m.depthWrite = m.opacity > 0.95;
  }
}

// ------------------------------------------------------------------ labels with leader lines
const overlay = document.getElementById('overlay');
const svg = document.getElementById('lines');
const SITES = ['C7', 'T12', 'L3', 'L scapula', 'R scapula'];
const labelEls = SITES.map((site, k) => {
  const d = document.createElement('div');
  d.className = 'lab';
  d.innerHTML = `<div class="hd"><span class="num">${k + 1}</span><span class="nm">${site}</span></div><div class="vals"></div>`;
  d.addEventListener('click', () => post({ type: 'pod', index: k }));
  overlay.appendChild(d);
  return d;
});
const lineEls = SITES.map(() => {
  const l = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  svg.appendChild(l);
  return l;
});
const dotEls = SITES.map(() => {
  const c = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
  c.setAttribute('r', '4');
  svg.appendChild(c);
  return c;
});

function deg(v) {
  return v === null || v === undefined || Number.isNaN(v) ? '<i>—</i>' : `${v >= 0 ? '' : '−'}${Math.abs(v).toFixed(1)}°`;
}

const v3 = new THREE.Vector3();
function updateLabels() {
  const W = canvas.clientWidth, H = canvas.clientHeight;
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  const show = state.labels && model && W > 260;
  overlay.style.display = show ? 'block' : 'none';
  svg.style.display = show ? 'block' : 'none';
  if (!show) return;
  const L = state.live;
  const sensors = (L && L.sensors) || [1, 1, 1, 1, 1];
  const pts = pods.map((p, k) => {
    p.group.getWorldPosition(v3);
    v3.project(camera);
    return { k, x: (v3.x * 0.5 + 0.5) * W, y: (-v3.y * 0.5 + 0.5) * H };
  });
  // spine pods alternate sides; shoulder pods go to the side they appear on
  const cx = W / 2;
  const side = pts.map((p) => (p.k === 0 ? 'L' : p.k === 1 ? 'R' : p.k === 2 ? 'L' : (p.x < cx ? 'L' : 'R')));
  if (side[3] === side[4]) side[3] = side[3] === 'L' ? 'R' : 'L';
  const colW = LABEL_W;
  const placed = { L: [], R: [] };
  const order = pts.slice().sort((a, b) => a.y - b.y);
  for (const p of order) {
    const s = side[p.k];
    const el = labelEls[p.k];
    const h = el.offsetHeight || 54;
    let y = Math.max(8, Math.min(H - h - 8, p.y - h / 2));
    for (const q of placed[s]) if (y < q.y + q.h + 8 && y + h > q.y - 8) y = q.y + q.h + 8;
    placed[s].push({ y, h });
    const x = s === 'L' ? 8 : W - colW - 8;
    el.style.left = `${x}px`;
    el.style.top = `${y}px`;
    el.style.width = `${colW}px`;
    const fault = sensors[p.k] === 0;
    el.classList.toggle('fault', fault);
    const sV = L && L.s ? L.s[p.k] : null, fV = L && L.f ? L.f[p.k] : null, rV = L && L.r ? L.r[p.k] : null;
    el.querySelector('.vals').innerHTML = fault ? '<b class="bad">Not responding</b>'
      : (state.bend > 0.5 && rV !== null && rV !== undefined
        ? `<span>Forward <b>${deg(sV)}</b></span><span>Roll <b>${deg(rV)}</b></span>`
        : `<span>Forward <b>${deg(sV)}</b></span><span>Side <b>${deg(fV)}</b></span>`);
    const ax = s === 'L' ? x + colW : x;
    const ay = y + 16;
    const midx = s === 'L' ? ax + 14 : ax - 14;
    lineEls[p.k].setAttribute('d', `M${ax},${ay} L${midx},${ay} L${p.x},${p.y}`);
    lineEls[p.k].setAttribute('class', fault ? 'ln bad' : 'ln');
    dotEls[p.k].setAttribute('cx', p.x);
    dotEls[p.k].setAttribute('cy', p.y);
    dotEls[p.k].setAttribute('class', fault ? 'dt bad' : 'dt');
  }
  pods.forEach((p, k) => p.led.material.color.set(sensors[k] === 0 ? 0xff5a5f : 0x4fc3f7));
}

// ------------------------------------------------------------------ input and camera
let down = null;
canvas.addEventListener('pointerdown', (e) => { down = { last: e.clientX, lastY: e.clientY, moved: 0 }; canvas.setPointerCapture(e.pointerId); });
canvas.addEventListener('pointermove', (e) => {
  if (!down) return;
  const dx = e.clientX - down.last, dy = e.clientY - down.lastY;
  down.last = e.clientX; down.lastY = e.clientY; down.moved += Math.abs(dx) + Math.abs(dy);
  if (down.moved > 6) {
    state.yaw -= dx * 0.011; state.yawVel = -dx * 0.6; state.sinceDrag = 0;
    state.pitch = Math.max(-0.15, Math.min(0.6, state.pitch + dy * 0.004));
  }
});
canvas.addEventListener('pointerup', () => { down = null; });

let debugCam = null;
let fitBox = null, lastDt = 1 / 60;
function frameCamera() {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (debugCam) {
    const pr0 = renderer.getPixelRatio();
    if (canvas.width !== Math.round(w * pr0)) renderer.setSize(w, h, false);
    camera.aspect = w / h; camera.position.set(...debugCam.slice(0, 3)); camera.lookAt(...debugCam.slice(3)); camera.updateProjectionMatrix();
    return;
  }
  const pr = renderer.getPixelRatio();
  if (canvas.width !== Math.round(w * pr) || canvas.height !== Math.round(h * pr)) renderer.setSize(w, h, false);
  camera.aspect = w / h;
  // fit the posed skeleton's bounding box into the space between the label columns
  if (model) {
    const bb = new THREE.Box3().setFromObject(model);
    if (!bb.isEmpty()) {
      const c = bb.getCenter(new THREE.Vector3()), sz = bb.getSize(new THREE.Vector3());
      fitBox = fitBox || { c: c.clone(), sz: sz.clone() };
      const k = 1 - Math.exp(-lastDt / 0.25);
      fitBox.c.lerp(c, k); fitBox.sz.lerp(sz, k);
    }
  }
  const fb = fitBox || { c: new THREE.Vector3(0, 0.85, 0), sz: new THREE.Vector3(0.6, 1.7, 0.4) };
  const vfov = camera.fov * d2r, tv = Math.tan(vfov / 2);
  const side = state.labels && w > 260 ? 2 * (LABEL_W + 16) : 24;
  const usable = Math.max(0.3, (w - side) / w);
  const distH = (fb.sz.y * 1.06) / (2 * tv);
  const distW = (Math.max(fb.sz.x, 0.3) * 1.06) / (2 * tv * camera.aspect * usable);
  const dist = Math.max(distH, distW) + fb.sz.z * 0.5;
  camera.position.set(fb.c.x, fb.c.y + Math.sin(state.pitch) * dist, fb.c.z + Math.cos(state.pitch) * dist);
  camera.lookAt(fb.c.x, fb.c.y, fb.c.z);
  camera.updateProjectionMatrix();
}

let last = performance.now();
let paused = false;
function frame(now) {
  if (paused) { last = now; requestAnimationFrame(frame); return; }
  let dt = (now - last) / 1000; last = now;
  if (!(dt > 0)) dt = 1 / 60;
  dt = Math.min(dt, 0.25);
  state.t += dt; state.sinceDrag += dt; lastDt = dt;
  if (model) {
    if (state.sinceDrag < 3) { state.yaw += state.yawVel * dt; state.yawVel *= Math.pow(0.03, dt); }
    else if (state.view !== 'free') {
      let d = (VIEWS[state.view] - state.yaw) % (2 * Math.PI);
      if (d > Math.PI) d -= 2 * Math.PI; if (d < -Math.PI) d += 2 * Math.PI;
      state.yaw += d * (1 - Math.pow(0.08, dt));
    }
    pivot.rotation.y = state.yaw;
    smoothAngles(dt);
    pose();
    tint();
  }
  frameCamera();
  renderer.render(scene, camera);
  updateLabels();
  requestAnimationFrame(frame);
}

window.skel = {
  setLive(l) { state.live = l; },
  setView(v) { if (v in VIEWS || v === 'free') { state.view = v; state.sinceDrag = 99; } },
  setFocus(f) { state.focus = !!f; },
  setAmplify(a) { state.amplify = a === 2 ? 2 : 1; },
  setLabels(b) { state.labels = !!b; },
  setPaused(p) { paused = !!p; },
  _debugCam(a) { debugCam = a; },
  _high() { const out = []; model.traverse((o) => { if (o.isMesh) { const b = new THREE.Box3().setFromObject(o); if (b.max.y > 1.2) out.push([o.name, o.parent && o.parent.name, b.max.y]); } }); return out; },
  _debug() { const bb = new THREE.Box3().setFromObject(model); const sk = model.getObjectByName('Skull'); const p = sk ? sk.getWorldPosition(new THREE.Vector3()) : null; return { min: bb.min.toArray(), max: bb.max.toArray(), skull: p && p.toArray(), fit: fitBox && [fitBox.c.toArray(), fitBox.sz.toArray()], cam: camera.position.toArray() }; },
};
const params = new URLSearchParams(location.search);
if (params.get('view')) { state.view = params.get('view'); state.yaw = VIEWS[state.view] ?? state.yaw; }
if (params.get('labels') === '0') state.labels = false;

function b64ToBuf(b64) {
  const bin = atob(b64); const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u.buffer;
}
new GLTFLoader().parse(b64ToBuf(window.SKELETON_GLB), '', setup, (e) => post({ type: 'error', message: String(e) }));
requestAnimationFrame(frame);
