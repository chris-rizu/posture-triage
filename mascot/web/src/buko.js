// Buko viewer: renders buko.glb with three.js and poses its skeleton.
//
// Host API (called from the Flutter app):
//   buko.setMode('wave'|'idle'|'calibrate'|'stand'|'bendDemo'|'live'|'celebrate'|'thinking'|'concerned')
//   buko.setLive({s:[5], f:[5], r:[5], ind:{K,L,N,F,S,R}, mu:{K,L,N}, lim:{K:[mu,mon,ref],...}, sensors:[5]})
//   buko.setReduceMotion(bool)
// Messages to the host: {type:'ready'} and {type:'pod', index} (tap on a sensor pod).
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

const PREF_YAW = { wave: 0.35, idle: 0.35, celebrate: 0.2, thinking: 0.45, concerned: 0.3,
  calibrate: Math.PI * 0.92, stand: Math.PI * 0.72, live: Math.PI * 0.74, bendDemo: Math.PI * 0.5 };

function post(msg) {
  const s = JSON.stringify(msg);
  if (window.BukoHost && window.BukoHost.postMessage) window.BukoHost.postMessage(s);
  else if (window.parent && window.parent !== window) window.parent.postMessage({ buko: msg }, '*');
}

const state = {
  mode: 'wave', live: null, reduce: false,
  yaw: PREF_YAW.wave, yawVel: 0, sinceDrag: 99, react: -1, t: 0,
  blinkAt: 2, blinkT: -1, lookAt: 0, look: [0, 0], podTip: null, podTipT: 0,
};

// ------------------------------------------------------------------ renderer
const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(24, 1, 0.05, 20);

const hemi = new THREE.HemisphereLight(0xf4f7ff, 0xa9b8ae, 1.35);
scene.add(hemi);
const key = new THREE.DirectionalLight(0xfff1e2, 2.6);
key.position.set(-0.9, 3.2, 1.6);
key.castShadow = true;
key.shadow.mapSize.set(1024, 1024);
key.shadow.camera.left = -0.8; key.shadow.camera.right = 0.8;
key.shadow.camera.top = 1.4; key.shadow.camera.bottom = -0.4;
key.shadow.camera.near = 0.5; key.shadow.camera.far = 6;
key.shadow.radius = 6;
key.shadow.bias = -0.0004;
key.shadow.normalBias = 0.01;
scene.add(key);
const rim = new THREE.DirectionalLight(0xcfe3ff, 1.6);
rim.position.set(1.6, 1.6, -2.2);
scene.add(rim);

const ground = new THREE.Mesh(new THREE.CircleGeometry(0.9, 48), new THREE.ShadowMaterial({ opacity: 0.16 }));
ground.rotation.x = -Math.PI / 2;
ground.receiveShadow = true;
scene.add(ground);
// soft contact blob under the feet
const blobTex = (() => {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const g = c.getContext('2d');
  const gr = g.createRadialGradient(64, 64, 4, 64, 64, 64);
  gr.addColorStop(0, 'rgba(30,42,51,0.35)'); gr.addColorStop(1, 'rgba(30,42,51,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  return new THREE.CanvasTexture(c);
})();
const blob = new THREE.Mesh(new THREE.PlaneGeometry(0.42, 0.3), new THREE.MeshBasicMaterial({ map: blobTex, transparent: true, depthWrite: false }));
blob.rotation.x = -Math.PI / 2; blob.position.y = 0.001;
scene.add(blob);

// ------------------------------------------------------------------ model
const pivot = new THREE.Group();
scene.add(pivot);
let model = null;
const B = {}; // bones
const O = {}; // named objects
const rest = new Map(); // bone -> {q, axes}
const pods = [];

const san = (n) => n.replace(/[\s.\[\]:/]/g, '');
function find(name) { return model.getObjectByName(name) || model.getObjectByName(san(name)); }

function setup(gltf) {
  model = gltf.scene;
  pivot.add(model);
  model.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = true;
      o.receiveShadow = true;
      if (o.material && o.material.name === 'Shirt') o.material.roughness = 0.9;
    }
  });
  for (const n of ['root', 'pelvis', 'seg1', 'seg2', 'seg3', 'head', 'arm.L', 'arm.R']) {
    B[n] = find(n);
  }
  for (const n of ['EyeL', 'EyeR', 'GlintL', 'GlintR', 'BrowL', 'BrowR', 'MouthSmile', 'MouthFlat', 'MouthFrown', 'Head']) O[n] = find(n);
  {
    const pod = find('Pod'), led = find('LED');
    if (pod && led) {
      led.traverse((m) => { if (m.isMesh) { m.material = m.material.clone(); m.castShadow = false; } });
      pods.push({ pod, led });
    }
  }
  model.updateMatrixWorld(true);
  // rest pose and, per bone, the world axes expressed in the bone's local frame
  const wq = new THREE.Quaternion();
  for (const [n, b] of Object.entries(B)) {
    if (!b) continue;
    b.getWorldQuaternion(wq);
    const inv = wq.clone().invert();
    rest.set(b, {
      q: b.quaternion.clone(),
      x: new THREE.Vector3(1, 0, 0).applyQuaternion(inv),
      y: new THREE.Vector3(0, 1, 0).applyQuaternion(inv),
      z: new THREE.Vector3(0, 0, 1).applyQuaternion(inv),
      p: b.position.clone(),
    });
  }
  for (const n of Object.keys(O)) {
    const o = O[n]; if (!o) continue;
    // world "up" and "forward" expressed in the parent's frame, for moving face parts
    const pq = new THREE.Quaternion(); o.parent.getWorldQuaternion(pq); pq.invert();
    o.userData.rest = { s: o.scale.clone(), p: o.position.clone(), q: o.quaternion.clone(),
      up: new THREE.Vector3(0, 1, 0).applyQuaternion(pq), fwd: new THREE.Vector3(0, 0, 1).applyQuaternion(pq) };
  }
  model.userData.restY = model.position.y;
  post({ type: 'ready' });
}

// ------------------------------------------------------------------ pose
const P0 = () => ({ hipFlex: 0, lumbar: 0, thoracic: 0, neck: 0, lean: 0, shoulderTilt: 0, twist: 0,
  headYaw: 0, headPitch: 0, headRoll: 0, armLUp: 6, armRUp: 6, armLFwd: 0, armRFwd: 0, elbowL: 8, elbowR: 8, foreLUp: 0, foreRUp: 0,
  jump: 0, squash: 0, breathe: 0, blink: 0, smile: 0.7, brow: 0 });
const cur = P0(), vel = Object.fromEntries(Object.keys(cur).map((k) => [k, 0]));
const DIRECT = new Set(['jump', 'squash', 'breathe', 'blink']);
const d2r = Math.PI / 180;
const qTmp = new THREE.Quaternion();
const headW = new THREE.Vector3();

function applyBone(b, rots) {
  if (!b) return;
  const r = rest.get(b);
  b.quaternion.copy(r.q);
  for (const [axis, deg] of rots) {
    if (!deg) continue;
    qTmp.setFromAxisAngle(r[axis], deg * d2r);
    b.quaternion.multiply(qTmp);
  }
}

function target() {
  const p = P0();
  const anim = !state.reduce, t = state.t;
  p.breathe = anim ? 0.5 + 0.5 * Math.sin(t * 2 * Math.PI / 3.6) : 0.5;
  if (anim && t > state.blinkAt && state.blinkT < 0) state.blinkT = 0;
  if (state.blinkT >= 0) {
    p.blink = Math.sin(Math.min(1, state.blinkT / 0.15) * Math.PI);
    if (state.blinkT > 0.15) { state.blinkT = -1; state.blinkAt = t + 2.5 + Math.random() * 3; }
  }
  switch (state.mode) {
    case 'wave':
      p.armRUp = 150 + (anim ? 16 * Math.sin(t * 9) : 0); p.armRFwd = 12;
      p.headRoll = 7; p.lean = -4; p.smile = 1; break;
    case 'idle':
      if (anim && t > state.lookAt) { state.lookAt = t + 2.5 + Math.random() * 2.5; state.look = [(Math.random() - 0.5) * 40, (Math.random() - 0.5) * 12]; }
      p.headYaw = state.look[0]; p.headPitch = state.look[1]; break;
    case 'calibrate': p.smile = 0.3; break;
    case 'stand': p.smile = 0.35; break;
    case 'bendDemo': p.hipFlex = 70; p.thoracic = 20; p.neck = -10; p.headPitch = -10; p.smile = 0.35; break;
    case 'live': applyLive(p); break;
    case 'celebrate': {
      p.smile = 1; p.armLUp = 150; p.armRUp = 150; p.armLFwd = 15; p.armRFwd = 15;
      if (anim) {
        const c = (t % 2.2) / 2.2;
        if (c < 0.55) { const h = Math.abs(Math.sin((c / 0.55) * 2 * Math.PI)); p.jump = 0.09 * h; p.squash = h < 0.12 ? 0.5 : -0.25; }
      }
      break;
    }
    case 'thinking':
      p.smile = 0.15; p.brow = 0.5; p.headRoll = -12; p.headPitch = 6; p.lean = 4;
      p.armLFwd = 105; p.armLUp = 25; break;
    case 'concerned':
      p.smile = -0.6; p.brow = 1; p.headPitch = 10; p.armLFwd = 12; p.armRFwd = 12; break;
  }
  if (state.react >= 0) {
    const r = state.react;
    if (anim && r < 0.5) { const h = Math.sin((r / 0.5) * Math.PI); p.jump = Math.max(p.jump, 0.08 * h); p.squash = r < 0.05 || r > 0.45 ? 0.45 : -0.2; }
    if (r < 1.6 && state.mode !== 'live' && state.mode !== 'bendDemo') {
      p.armRUp = 150 + (anim ? 18 * Math.sin(r * 11) : 0); p.armRFwd = 12; p.smile = 1;
    }
    if (r > 1.6) state.react = -1;
  }
  return p;
}

function applyLive(p) {
  const L = state.live;
  if (!L || !L.s) return;
  const num = (x) => (x === null || x === undefined || Number.isNaN(x) ? NaN : x);
  const ok = (x) => (Number.isNaN(x) ? 0 : x);
  const s2 = num(L.s[1]);
  const b = Number.isNaN(s2) ? 0 : Math.min(1, Math.max(0, (s2 + 10) / 90));
  const mu = L.mu || { K: 38, L: -22, N: 28 };
  const ind = L.ind || {};
  const dK = ok(num(ind.K) - mu.K), dL = ok(num(ind.L) - mu.L), dN = ok(num(ind.N) - mu.N);
  const clamp = (x, a, c) => Math.min(c, Math.max(a, x));
  p.hipFlex = 80 * b;
  p.thoracic = clamp(dK * 1.2, -20, 50) * (1 - b) + 14 * b;
  p.lumbar = clamp(-dL * 0.8, -20, 30) * (1 - b);
  p.neck = clamp(dN * 0.9, -20, 40) * (1 - b) - 8 * b;
  p.lean = clamp(ok(num(ind.F)) * 2, -15, 15) * (1 - b);
  p.shoulderTilt = clamp(ok(num(ind.S)) * 2, -12, 12) * (1 - b);
  const r4 = num(L.r && L.r[3]), r5 = num(L.r && L.r[4]);
  p.twist = (Number.isNaN(r4) || Number.isNaN(r5) ? 0 : clamp((r4 + r5), -20, 20)) * b;
  // expression from how far the watched indicators are from their usual range
  let worst = 0;
  for (const k of ['K', 'N', 'F', 'S']) {
    const lim = L.lim && L.lim[k], v = num(ind[k]);
    if (!lim || Number.isNaN(v)) continue;
    const d = Math.abs(v - lim[0]);
    worst = Math.max(worst, d >= lim[2] ? 2 : d >= lim[1] ? 1 : 0);
  }
  p.smile = [0.7, 0.1, -0.5][worst];
  p.brow = [0, 0.5, 1][worst];
}

function pose(p) {
  // the column bends a little at every disc, like a spine
  const hf = p.hipFlex, lu = p.lumbar, th = p.thoracic, le = p.lean, tw = p.twist;
  applyBone(B.pelvis, [['x', hf * 0.30 + lu * 0.25], ['z', le * 0.25]]);
  applyBone(B.seg1, [['x', hf * 0.25 + lu * 0.40], ['z', le * 0.25], ['y', tw * 0.25]]);
  applyBone(B.seg2, [['x', hf * 0.25 + lu * 0.35 + th * 0.35], ['z', le * 0.25], ['y', tw * 0.35]]);
  applyBone(B.seg3, [['x', hf * 0.20 + th * 0.65], ['z', le * 0.25 + p.shoulderTilt], ['y', tw * 0.40]]);
  applyBone(B.head, [['x', p.neck + p.headPitch], ['y', p.headYaw], ['z', p.headRoll]]);
  const flex = hf + lu + th;
  // arms hang with gravity when the column bends; raise sideways with *Up, forward with *Fwd
  applyBone(B['arm.L'], [['x', -flex * 0.85 + p.armLFwd], ['z', p.armLUp]]);
  applyBone(B['arm.R'], [['x', -flex * 0.85 + p.armRFwd], ['z', -p.armRUp]]);
  // breathing: chest rises a touch
  if (B.seg3) B.seg3.scale.setScalar(1 + 0.010 * p.breathe);
  // hop and squash
  model.position.y = model.userData.restY + p.jump;
  model.scale.set(1 + 0.06 * p.squash, 1 - 0.08 * p.squash, 1 + 0.06 * p.squash);
  blob.scale.setScalar(1 - p.jump * 3);
  blob.material.opacity = 1 - p.jump * 4;
  // face
  const open = Math.max(0.1, 1 - p.blink);
  for (const n of ['EyeL', 'EyeR']) if (O[n]) O[n].scale.set(O[n].userData.rest.s.x, O[n].userData.rest.s.y * open, O[n].userData.rest.s.z);
  for (const n of ['GlintL', 'GlintR']) if (O[n]) O[n].visible = open > 0.5;
  const m = p.smile > 0.4 ? 'MouthSmile' : p.smile < -0.2 ? 'MouthFrown' : 'MouthFlat';
  for (const n of ['MouthSmile', 'MouthFlat', 'MouthFrown']) if (O[n]) O[n].visible = n === m;
  for (const [n, s] of [['BrowL', 1], ['BrowR', -1]]) {
    const o = O[n]; if (!o) continue;
    const r = o.userData.rest;
    o.position.copy(r.p).addScaledVector(r.up, 0.010 * p.brow);
    o.quaternion.copy(r.q);
    qTmp.setFromAxisAngle(r.fwd, -s * 0.4 * p.brow); // inner ends up: a worried look
    o.quaternion.premultiply(qTmp);
  }
}

// ------------------------------------------------------------------ LEDs and pod tips
const LED_OK = new THREE.Color(0x4fc3f7), LED_OFF = new THREE.Color(0x4a5560), LED_BAD = new THREE.Color(0xff5a5f);
function updateLeds() {
  const sensors = (state.live && state.live.sensors) || [1, 1, 1, 1, 1];
  pods.forEach(({ led }) => {
    let c = sensors.some((x) => x === 0) ? LED_BAD : LED_OK;
    if (state.mode === 'calibrate' && !state.reduce) c = Math.floor(state.t * 4) % 2 ? LED_OK : LED_OFF;
    led.traverse((m) => { if (m.isMesh) { m.material.color.copy(c); m.material.emissive.copy(c); } });
  });
}

const tip = document.getElementById('tip');
const podSites = ['C7–T1, base of the neck', 'T12–L1', 'L3–L4, lower back', 'left shoulder blade', 'right shoulder blade'];
function updateTip() {
  if (state.podTip === null) { tip.style.display = 'none'; return; }
  const k = state.podTip, L = state.live;
  const v = new THREE.Vector3();
  pods[k].pod.getWorldPosition(v); v.project(camera);
  const x = (v.x * 0.5 + 0.5) * canvas.clientWidth, y = (-v.y * 0.5 + 0.5) * canvas.clientHeight;
  const deg = (a) => (a === null || a === undefined || Number.isNaN(a) ? 'not defined in this pose' : `${a.toFixed(1)}°`);
  tip.innerHTML = `<b>IMU${k + 1}</b>, ${podSites[k]}` + (L && L.s ? `<br>Forward tilt ${deg(L.s[k])}<br>Sideways tilt ${deg(L.f[k])}` : '<br>No live data');
  tip.style.display = 'block';
  const w = tip.offsetWidth, h = tip.offsetHeight;
  let tx = x + 14, ty = y - h - 12;
  if (tx + w > canvas.clientWidth - 6) tx = x - w - 14;
  if (ty < 4) ty = y + 14;
  tip.style.left = `${tx}px`; tip.style.top = `${ty}px`;
}

// ------------------------------------------------------------------ input
let down = null;
canvas.addEventListener('pointerdown', (e) => { down = { x: e.clientX, y: e.clientY, last: e.clientX, moved: 0, t: performance.now() }; canvas.setPointerCapture(e.pointerId); });
canvas.addEventListener('pointermove', (e) => {
  if (!down) return;
  const dx = e.clientX - down.last; down.last = e.clientX; down.moved += Math.abs(dx);
  if (down.moved > 6) { state.yaw += dx * 0.012; state.yawVel = dx * 0.7; state.sinceDrag = 0; }
});
canvas.addEventListener('pointerup', (e) => {
  if (down && down.moved <= 6) tap(e);
  down = null;
});
const ray = new THREE.Raycaster();
function tap(e) {
  if (!model) return;
  const r = canvas.getBoundingClientRect();
  const v = new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
  ray.setFromCamera(v, camera);
  const hits = ray.intersectObject(model, true);
  if (!hits.length) return;
  state.react = 0;
  post({ type: 'tap' });
}

// ------------------------------------------------------------------ loop
function resize() {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (canvas.width !== Math.round(w * renderer.getPixelRatio()) || canvas.height !== Math.round(h * renderer.getPixelRatio())) {
    renderer.setSize(w, h, false);
  }
  camera.aspect = w / h;
  // frame the whole figure (about 1.0 tall), with room for raised arms
  // widen the frame as Buko bends forward (the head then sticks out in front)
  const bend = Math.min(1, Math.max(0, cur.hipFlex / 80));
  const fit = Math.max(1.32 + 0.3 * bend, (1.0 + 0.6 * bend) / camera.aspect * 0.78);
  const dist = fit / (2 * Math.tan((camera.fov * d2r) / 2));
  // aim between the feet and the head, so a bent-over Buko stays in frame
  let tx = 0;
  if (B.head) { B.head.getWorldPosition(headW); tx = headW.x * 0.5 * bend; }
  camera.position.set(tx, 0.62 - 0.14 * bend + dist * 0.12, dist);
  camera.lookAt(tx, 0.5 - 0.14 * bend, 0);
  camera.updateProjectionMatrix();
}

let last = performance.now();
let paused = false;
function frame(now) {
  if (paused) { last = now; requestAnimationFrame(frame); return; }
  let dt = (now - last) / 1000; last = now;
  if (!(dt > 0) || dt > 0.1) dt = 1 / 60;
  state.t += dt; state.sinceDrag += dt;
  if (state.blinkT >= 0) state.blinkT += dt;
  if (state.react >= 0) state.react += dt;
  if (state.podTip !== null && (state.podTipT -= dt) <= 0) state.podTip = null;
  resize();
  if (model) {
    if (state.sinceDrag < 2.5) { state.yaw += state.yawVel * dt; state.yawVel *= Math.pow(0.04, dt); }
    else {
      let d = ((PREF_YAW[state.mode] ?? 0.35) - state.yaw) % (2 * Math.PI);
      if (d > Math.PI) d -= 2 * Math.PI; if (d < -Math.PI) d += 2 * Math.PI;
      state.yaw += d * (1 - Math.pow(0.12, dt));
    }
    pivot.rotation.y = state.yaw;
    const tg = target();
    const w = state.reduce ? 30 : 9;
    for (const k of Object.keys(cur)) {
      if (DIRECT.has(k)) { cur[k] = tg[k]; vel[k] = 0; continue; }
      const a = -w * w * (cur[k] - tg[k]) - 2 * w * vel[k];
      vel[k] += a * dt; cur[k] += vel[k] * dt;
    }
    pose(cur);
    updateLeds();
  }
  renderer.render(scene, camera);
  updateTip();
  requestAnimationFrame(frame);
}

// ------------------------------------------------------------------ boot
window.buko = {
  setMode(m) { if (m && m !== state.mode) { state.mode = m; state.react = -1; } },
  setLive(l) { state.live = l; },
  setReduceMotion(r) { state.reduce = !!r; },
  setPaused(p) { paused = !!p; },
  react() { state.react = 0; },
  setYaw(y) { state.yaw = y; state.sinceDrag = 0; },
};
const params = new URLSearchParams(location.search);
if (params.get('mode')) state.mode = params.get('mode');
state.yaw = PREF_YAW[state.mode] ?? 0.35;

function b64ToBuf(b64) {
  const bin = atob(b64); const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u.buffer;
}
new GLTFLoader().parse(b64ToBuf(window.BUKO_GLB), '', setup, (e) => post({ type: 'error', message: String(e) }));
requestAnimationFrame(frame);
