// Bundles the viewer and the model into one self-contained HTML file:
//   node build.mjs  ->  ../buko.html (also copied into the Flutter app assets)
import { build } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync } from 'fs';

const res = await build({ entryPoints: ['src/buko.js'], bundle: true, minify: true, format: 'iife', write: false, target: 'es2019' });
const js = res.outputFiles[0].text;
const glb = readFileSync('../buko.glb').toString('base64');
const html = `<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Buko</title>
<style>
html,body{margin:0;height:100%;background:transparent;overflow:hidden;-webkit-tap-highlight-color:transparent;touch-action:pan-y}
#c{width:100%;height:100%;display:block;touch-action:pan-y}
#tip{position:absolute;display:none;max-width:220px;padding:8px 11px;border-radius:10px;background:rgba(29,42,51,.94);color:#fff;
font:13px/1.4 system-ui,-apple-system,Roboto,sans-serif;pointer-events:none;box-shadow:0 4px 14px rgba(0,0,0,.18)}
#tip b{color:#ff8db3}
</style></head>
<body><canvas id="c"></canvas><div id="tip"></div>
<script>window.BUKO_GLB="${glb}";</script>
<script>${js}</script>
</body></html>`;
writeFileSync('../buko.html', html);
mkdirSync('../../app/assets/mascot', { recursive: true });
writeFileSync('../../app/assets/mascot/buko.html', html);
console.log('buko.html', (html.length / 1024).toFixed(0), 'KB');
