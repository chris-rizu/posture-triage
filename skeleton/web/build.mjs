// Bundles the skeleton viewer and model into one offline HTML file:
//   node build.mjs  ->  ../skeleton.html and app/assets/skeleton/skeleton.html
import { build } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync } from 'fs';

const res = await build({ entryPoints: ['src/skeleton.js'], bundle: true, minify: true, format: 'iife', write: false, target: 'es2019' });
const js = res.outputFiles[0].text;
const glb = readFileSync('../skeleton.glb').toString('base64');
const html = `<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Live skeleton</title>
<style>
html,body{margin:0;height:100%;background:transparent;overflow:hidden;-webkit-tap-highlight-color:transparent;touch-action:pan-y}
#c{position:absolute;inset:0;width:100%;height:100%;display:block;touch-action:pan-y}
#lines{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}
#lines .ln{fill:none;stroke:#1D2A33;stroke-width:1.2;opacity:.55}
#lines .dt{fill:#E4467C;stroke:#fff;stroke-width:1.5}
#lines .bad{stroke:#C8323C;opacity:.9}
#lines .dt.bad{fill:#C8323C}
#overlay{position:absolute;inset:0;pointer-events:none}
.lab{position:absolute;pointer-events:auto;box-sizing:border-box;padding:6px 8px 7px;border-radius:10px;
background:rgba(247,249,247,.94);box-shadow:0 1px 0 rgba(29,42,51,.06),0 6px 18px rgba(29,42,51,.08);
font:12px/1.3 "Atkinson Hyperlegible",system-ui,-apple-system,Roboto,sans-serif;color:#1D2A33;transition:top .12s linear}
.lab .hd{display:flex;align-items:center;gap:6px;margin-bottom:2px;white-space:nowrap;overflow:hidden}
.lab .num{display:inline-grid;place-items:center;width:17px;height:17px;border-radius:50%;background:#E4467C;color:#fff;font-weight:700;font-size:11px;flex:none}
.lab .nm{font-weight:700}
.lab .st{color:#51606B;overflow:hidden;text-overflow:ellipsis}
.lab .vals{display:flex;flex-direction:column;gap:1px;font-variant-numeric:tabular-nums}
.lab .vals span{display:flex;justify-content:space-between;gap:6px;color:#51606B;white-space:nowrap}
.lab .vals b{color:#1D2A33;font-size:13px}
.lab .vals i{color:#8a969e;font-style:normal}
.lab.fault{background:#fbe9e8}
.lab .bad{color:#C8323C}
</style></head>
<body><canvas id="c"></canvas><svg id="lines"></svg><div id="overlay"></div>
<script>window.SKELETON_GLB="${glb}";</script>
<script>${js}</script>
</body></html>`;
writeFileSync('../skeleton.html', html);
mkdirSync('../../app/assets/skeleton', { recursive: true });
writeFileSync('../../app/assets/skeleton/skeleton.html', html);
console.log('skeleton.html', (html.length / 1024 / 1024).toFixed(2), 'MB');
