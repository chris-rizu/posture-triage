# Live skeleton twin

The skeleton on the home, assessment and monitoring screens is built from real anatomy and posed
live from the five sensor pods.

## Source and licence

Bone meshes: **BodyParts3D**, Copyright © 2008 Life Science Integrated Database Center,
licensed under Creative Commons Attribution-Share Alike 2.1 Japan
(http://lifesciencedb.jp/bp3d). The STL files come from the
[BodyParts3D repository by K. M. Moerman](https://github.com/Kevin-Mattheus-Moerman/BodyParts3D).
`skeleton.glb` is an adaptation (decimated, regrouped, re-centred) and is shared under the same
licence. The app shows this credit under the skeleton; keep it there.

## How it is built

`build_from_bodyparts3d.py` (Blender as a Python module, `pip install bpy`):

1. imports about 200 bones, merges the duplicate STL vertices and decimates each to a budget
   (≈200k triangles in total, fine for a mid-range phone);
2. makes each vertebra (C1–L5) its own node, with its origin at the centre of its vertebral body
   and its axes along the spine there; discs, ribs, costal cartilage, sternum, shoulder girdle,
   arms and skull hang under the vertebrae they move with; hip bones and sacrum under `Pelvis`;
3. adds marker nodes: `S1` (top of the sacrum), `Pod1`..`Pod5` (where the pods sit on the skin)
   and `Arm_L` / `Arm_R` (shoulder joints);
4. exports `skeleton.glb`.

```
git clone --depth 1 https://github.com/Kevin-Mattheus-Moerman/BodyParts3D
python build_from_bodyparts3d.py BodyParts3D/assets/BodyParts3D_data/stl
cd web && npm install && node build.mjs     # -> app/assets/skeleton/skeleton.html
```

## How the sensors move it (`web/src/spine.js`, `web/src/skeleton.js`)

- IMU1, IMU2 and IMU3 give the forward tilt at C7, T12 and L3. The tilt of every vertebra is
  interpolated between those levels, extrapolated below L3 and eased toward an upright head above
  C7. Sideways tilt is spread the same way; in the forward bend, the roll of IMU2 and the shoulder
  pods becomes axial rotation of the thoracic vertebrae, so the ribs show a rib hump.
- The rest pose is the dataset's real anatomy. Each frame the change from the reference posture
  (C7 28°, T12 −10°, L3 12°) is applied on top: every vertebra turns by its change and the chain
  is re-linked from the sacrum, which tilts with most of the change at L5. Arms always hang.
- IMU4 and IMU5 tilt the shoulder blades relative to the trunk.
- A spine region turns amber (monitor) or red (refer) only when its indicator is past the limit:
  cervical ← neck-base tilt, thoracic ← upper-back rounding (and trunk rotation in the bend),
  lumbar ← lower-back curve and trunk lean.

Viewer API: `skel.setLive({s, f, r, ind, lim, sensors})`, `skel.setView('back'|'side'|'three'|'front')`,
`skel.setFocus(bool)`, `skel.setAmplify(1|2)`, `skel.setLabels(bool)`. Open
`skeleton.html?view=side` in a browser to try it.
