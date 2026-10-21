"""Builds the live-twin skeleton from BodyParts3D anatomy and exports skeleton.glb.

  BodyParts3D, Copyright (c) 2008 Life Science Integrated Database Center,
  licensed under CC BY-SA 2.1 Japan (http://lifesciencedb.jp/bp3d).
  This model is an adaptation (decimated, regrouped) and is shared under the same licence.

Run:  python build_from_bodyparts3d.py <path to BodyParts3D_data/stl>

Every bone is decimated to a budget suited to a mid-range phone. Each vertebra
becomes its own node whose origin is the centre of its vertebral body and whose
axes follow the spine there (+Y along the spine, +Z anterior, +X the person's
left). Ribs, cartilage, sternum, shoulder girdle, arms and skull hang under the
vertebrae they move with; the hip bones and sacrum under a "Pelvis" node at the
hip-joint centre. The rest pose is the dataset's own posture, so the curve shown
at rest is real anatomy; the viewer adds the measured changes on top.

Extra nodes for the viewer: S1 (top of the sacrum), Pod1..Pod5 (where the sensor
pods sit on the skin), Arm_L / Arm_R (shoulder joints).
"""
import math
import os
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Matrix, Vector

STL = sys.argv[-1] if sys.argv[-1].endswith("stl") else "stl"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "skeleton.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# three.js (x, y, z) <-> Blender (x, -z, y); the dataset is already in Blender axes (mm)
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
CI = C.inverted()

VERTS = ["fifth lumbar vertebra", "fourth lumbar vertebra", "third lumbar vertebra", "second lumbar vertebra", "first lumbar vertebra",
         "twelfth thoracic vertebra", "eleventh thoracic vertebra", "tenth thoracic vertebra", "ninth thoracic vertebra",
         "eighth thoracic vertebra", "seventh thoracic vertebra", "sixth thoracic vertebra", "fifth thoracic vertebra",
         "fourth thoracic vertebra", "third thoracic vertebra", "second thoracic vertebra", "first thoracic vertebra",
         "seventh cervical vertebra", "sixth cervical vertebra", "fifth cervical vertebra", "fourth cervical vertebra",
         "third cervical vertebra", "axis", "atlas"]
VNAMES = ["L5", "L4", "L3", "L2", "L1", "T12", "T11", "T10", "T9", "T8", "T7", "T6", "T5", "T4", "T3", "T2", "T1",
          "C7", "C6", "C5", "C4", "C3", "C2", "C1"]
ORD = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth"]

# ---------------------------------------------------------------- names -> files
names = {}
for line in open(os.path.join(STL, "..", "parts_list_e.txt"), encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 2:
        names[p[1]] = p[0]
have = {f[:-4] for f in os.listdir(STL) if f.endswith(".stl")}


def fid(name):
    k = names.get(name)
    if k is None or k not in have:
        raise KeyError(f"no STL for '{name}'")
    return k


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, hexcol, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(hexcol), 1)
    b.inputs["Roughness"].default_value = rough
    return m


MAT = {"bone": material("Bone", "#E8E1CF", 0.62), "cart": material("Cartilage", "#B9CCDB", 0.45),
       "disc": material("Disc", "#9FB6C9", 0.5), "teeth": material("Teeth", "#F3EFE4", 0.35)}

# ---------------------------------------------------------------- import + decimate
_offset = Vector((0, 0, 0))


def load(name, tris, mat="bone", obj_name=None):
    """Imports one part (mm, dataset axes), merges duplicate STL vertices, decimates to ~tris."""
    path = os.path.join(STL, fid(name) + ".stl")
    bpy.ops.wm.stl_import(filepath=path)
    o = bpy.context.selected_objects[0]
    o.name = obj_name or name
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.02)
    for v in bm.verts:
        v.co = (v.co * 0.001) - _offset
    bm.to_mesh(me)
    bm.free()
    n = len(me.polygons)
    if n > tris:
        d = o.modifiers.new("Dec", "DECIMATE")
        d.ratio = tris / n
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier="Dec")
    me.validate()
    me.materials.clear()
    me.materials.append(MAT[mat])
    for p in me.polygons:
        p.use_smooth = True
    return o


def verts_three(o):
    """World vertices in three.js coordinates (x, y, z) = (x, z, -y)."""
    mw = o.matrix_world
    return [(v.x, v.z, -v.y) for v in (mw @ vv.co for vv in o.data.vertices)]


def centroid(pts):
    n = len(pts)
    return tuple(sum(p[k] for p in pts) / n for k in range(3))


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def empty(name, p_three):
    e = bpy.data.objects.new(name, None)
    scene.collection.objects.link(e)
    e.matrix_world = Matrix.Translation(Vector((p_three[0], -p_three[2], p_three[1])))
    return e


def parent_keep(child, parent):
    bpy.context.view_layer.update()
    mw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_world = mw


# ---------------------------------------------------------------- global placement
# floor at the lowest heel point; hip-joint centre on the vertical axis
fl, fr = load("left femur", 2600), load("right femur", 2600)
heads = []
for f in (fl, fr):
    pts = verts_three(f)
    top = max(p[1] for p in pts)
    near = [p for p in pts if p[1] > top - 0.045 and abs(p[0]) < 0.105]
    heads.append(centroid(near))
hip = centroid(heads)
calc = load("left calcaneus", 400)
floor = min(p[1] for p in verts_three(calc))
bpy.data.objects.remove(calc)  # loaded again with the foot below
shift = Vector((hip[0], -hip[2], floor))  # Blender axes
for o in list(scene.objects):
    o.data.transform(Matrix.Translation(-shift))
_offset = shift
HIP = (0.0, hip[1] - floor, 0.0)
print("hip joint centre", HIP)

# ---------------------------------------------------------------- vertebrae
vobj = {}
centres = []
for full, short in zip(VERTS, VNAMES):
    o = load(full, 2200 if short[0] in "LT" else 1500, obj_name=short)
    pts = verts_three(o)
    xs = [p[0] for p in pts]
    zs = [p[2] for p in pts]
    if short == "C1":  # atlas has no body: use the middle of the anterior arch and lateral masses
        c = centroid([p for p in pts if abs(p[0]) < 0.03])
    else:
        zmax, zmin = max(zs), min(zs)
        w = max(abs(x) for x in xs)
        body = [p for p in pts if p[2] > zmax - 0.42 * (zmax - zmin) and abs(p[0]) < 0.5 * w]
        c = centroid(body)
    vobj[short] = o
    centres.append(c)

frames = []
for i, c in enumerate(centres):
    a = centres[max(0, i - 1)]
    b = centres[min(len(centres) - 1, i + 1)]
    up = Vector((b[0] - a[0], b[1] - a[1], b[2] - a[2])).normalized()
    x = Vector((1, 0, 0))
    x = (x - up * x.dot(up)).normalized()
    z = x.cross(up)
    R = Matrix(((x.x, up.x, z.x), (x.y, up.y, z.y), (x.z, up.z, z.z)))
    frames.append((c, R))


def frame_b(c, R):
    m = Matrix(((R[0][0], R[0][1], R[0][2], c[0]), (R[1][0], R[1][1], R[1][2], c[1]),
                (R[2][0], R[2][1], R[2][2], c[2]), (0, 0, 0, 1)))
    return C @ m @ CI


for (c, R), short in zip(frames, VNAMES):
    o = vobj[short]
    M = frame_b(c, R)
    o.data.transform(M.inverted())
    o.matrix_world = M

# discs: each moves with the vertebra it is named after
for full, short in zip(VERTS, VNAMES):
    dname = f"intervertebral disk of {full}" if short not in ("C2",) else "intervertebral disk of axis"
    if short == "C1" or dname not in names or names[dname] not in have:
        continue
    d = load(dname, 500, mat="disc", obj_name=f"Disc_{short}")
    parent_keep(d, vobj[short])

# ---------------------------------------------------------------- pelvis and sacrum
pel = empty("Pelvis", HIP)
sac = load("sacrum", 3000, obj_name="Sacrum")
sp = verts_three(sac)
ytop = max(p[1] for p in sp)
s1 = centroid([p for p in sp if p[1] > ytop - 0.012 and abs(p[0]) < 0.03])
parent_keep(sac, pel)
parent_keep(empty("S1", s1), pel)
for side in ("left", "right"):
    h = load(f"{side} hip bone", 5000, obj_name=f"Hip_{side[0].upper()}")
    parent_keep(h, pel)

# ---------------------------------------------------------------- thorax
for n in range(1, 13):
    tv = vobj[f"T{n}"]
    for side in ("left", "right"):
        r = load(f"{side} {ORD[n - 1]} rib", 1100, obj_name=f"Rib_{side[0].upper()}{n}")
        parent_keep(r, tv)
        cname = f"{side} {ORD[n - 1]} costal cartilage"
        if n <= 7 and cname in names and names[cname] in have:
            cc = load(cname, 450, mat="cart", obj_name=f"Cart_{side[0].upper()}{n}")
            parent_keep(cc, tv)
for side, comp in (("L", "left costal cartilage"), ("R", "right costal cartilage")):
    # composite of all costal cartilages: keep only the lower ones (8-10), below the 7th
    try:
        cc = load(comp, 2500, mat="cart", obj_name=f"Cart_{side}low")
    except KeyError:
        continue
    y7 = min(p[1] for p in verts_three(bpy.data.objects[f"Cart_{side}7"]))
    bm = bmesh.new()
    bm.from_mesh(cc.data)
    kill = [f for f in bm.faces if (cc.matrix_world @ f.calc_center_median()).z > y7 + 0.004]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(cc.data)
    bm.free()
    parent_keep(cc, vobj["T9"])
st = join("Sternum", [load("manubrium", 1200), load("body of sternum", 1600), load("xiphoid process", 300)])
parent_keep(st, vobj["T6"])

# shoulder girdle and arms
for side, S in (("left", "L"), ("right", "R")):
    cl = load(f"{side} clavicle", 1200, obj_name=f"Clavicle_{S}")
    parent_keep(cl, vobj["T2"])
    sc = load(f"{side} scapula", 3200, obj_name=f"Scapula_{S}")
    parent_keep(sc, vobj["T4"])
    hum = load(f"{side} humerus", 2400, obj_name=f"Humerus_{S}")
    hp = verts_three(hum)
    top = max(p[1] for p in hp)
    head = centroid([p for p in hp if p[1] > top - 0.035])
    arm = empty(f"Arm_{S}", head)
    parent_keep(arm, vobj["T3"])
    parent_keep(hum, arm)
    fore = [load(f"{side} radius", 1300, obj_name=f"Radius_{S}"), load(f"{side} ulna", 1300, obj_name=f"Ulna_{S}")]
    hand = []
    for b in ("scaphoid", "lunate", "triquetral", "pisiform", "trapezium", "capitate", "hamate"):
        try:
            hand.append(load(f"{side} {b}", 120))
        except KeyError:
            pass
    for k in ORD[:5]:
        hand.append(load(f"{side} {k} metacarpal bone", 160))
    for f in ("thumb", "index finger", "middle finger", "ring finger", "little finger"):
        for ph in ("proximal", "middle", "distal"):
            try:
                hand.append(load(f"{ph} phalanx of {side} {f}", 110))
            except KeyError:
                pass
    for o in fore + [join(f"Hand_{S}", hand)]:
        parent_keep(o, arm)

# skull and jaw, carried by C1
skull = []
for b in ("frontal bone", "occipital bone", "sphenoid bone", "mandible", "vomer"):
    skull.append(load(b, {"frontal bone": 4500, "occipital bone": 3500, "sphenoid bone": 2200, "mandible": 3000, "vomer": 200}[b]))
for side in ("left", "right"):
    for b, t in (("parietal bone", 3500), ("temporal bone", 3000), ("maxilla", 2200), ("zygomatic bone", 900),
                 ("nasal bone", 200), ("lacrimal bone", 120)):
        skull.append(load(f"{side} {b}", t))
sk = join("Skull", skull)
parent_keep(sk, vobj["C1"])
teeth = []
for nm, k in names.items():
    if ("secondary" in nm and "tooth" in nm) and k in have:
        teeth.append(load(nm, 140, mat="teeth"))
if teeth:
    parent_keep(join("Teeth", teeth), vobj["C1"])

# legs and feet (static)
legs = [fl, fr]
for side in ("left", "right"):
    legs += [load(f"{side} patella", 500), load(f"{side} tibia", 2600), load(f"{side} fibula", 1200)]
    for b in ("talus", "calcaneus", "cuboid bone", "medial cuneiform bone", "intermediate cuneiform bone", "lateral cuneiform bone"):
        legs.append(load(f"{side} {b}", 250))
    legs.append(load(f"navicular bone of {side} foot", 200))
    for k in ORD[:5]:
        legs.append(load(f"{side} {k} metatarsal bone", 180))
    for t in ("big toe", "second toe", "third toe", "fourth toe", "little toe"):
        for ph in ("proximal", "middle", "distal"):
            try:
                legs.append(load(f"{ph} phalanx of {side} {t}", 90))
            except KeyError:
                pass
join("Legs", legs)

# ---------------------------------------------------------------- sensor pod sites (on the skin)
def back_point(o, xmax=0.012):
    pts = verts_three(o)
    pts = [p for p in pts if abs(p[0]) < xmax]
    p = min(pts, key=lambda q: q[2])  # most posterior
    return (p[0], p[1], p[2] - 0.016)


for k, vname in ((1, "C7"), (2, "T12"), (3, "L3")):
    parent_keep(empty(f"Pod{k}", back_point(vobj[vname])), vobj[vname])
for k, S in ((4, "L"), (5, "R")):
    sc = bpy.data.objects[f"Scapula_{S}"]
    pts = verts_three(sc)
    zmin = min(p[2] for p in pts)
    surf = [p for p in pts if p[2] < zmin + 0.018]
    c = centroid(surf)
    parent_keep(empty(f"Pod{k}", (c[0], c[1] + 0.005, zmin - 0.012)), sc)

# ---------------------------------------------------------------- export
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=False,
                          export_normals=True, export_animations=False, export_materials="EXPORT",
                          export_cameras=False, export_lights=False)
faces = sum(len(o.data.polygons) for o in scene.objects if o.type == "MESH")
print("WROTE", OUT, os.path.getsize(OUT), "bytes,", faces, "faces")
