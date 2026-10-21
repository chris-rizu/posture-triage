# Buko, the 3D mascot

Buko (from Cebuano *bukobuko*, "back") is a small spine character: three vertebra blocks on a
pelvis block with blue discs between them, a vertebra-shaped head with a face, short arms and
shoes. It wears the study harness on its back (pink straps, belt and a sensor pod with a light).
In the app it greets on Home and reacts on the result screen. It is secondary to the live
skeleton and is due for more work.

## How it is made

1. `build_buko.py` builds the character in Blender (no manual modelling):
   - each segment is a bevelled superellipse block (`vertebra_block`) with a spinous nub at the
     back; discs, head, arms, shoes, straps, belt and pod are separate meshes;
   - face parts (eyes, glints, brows, blush, three mouths) are placed by ray casts on the head;
   - an armature (root, pelvis, seg1, seg2, seg3, head, arm.L, arm.R); every part is rigidly
     parented to one bone, so the blocks stay crisp as the spine bends.
   It exports `buko.glb` (glTF 2.0, about 44k faces).
2. `web/src/buko.js` renders it with three.js (soft shadows, ACES tone mapping) and poses the
   bones every frame: scripted moods (wave, idle, calibrate, stand, bendDemo, celebrate,
   thinking, concerned) or the live sensor angles, through critically damped springs. Tapping
   Buko makes it react. `buko.setPaused(true)` stops rendering while it is off screen.
3. `web/build.mjs` bundles three.js, the viewer and the model into one offline HTML file and
   copies it to `app/assets/mascot/buko.html`.

```
pip install bpy                 # Blender as a Python module (Python 3.11)
python build_buko.py
cd web && npm install && node build.mjs
```

Open `buko.html?mode=wave` in a browser to preview it. In the console:
`buko.setMode('celebrate')`, `buko.setLive({...})` (format in `src/buko.js`).
