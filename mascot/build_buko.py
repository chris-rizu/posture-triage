"""Builds Buko, the posture mascot, in Blender and exports buko.glb.

Run:  python build_buko.py            (needs the `bpy` module: pip install bpy)

Buko is a little backbone: a stack of rounded vertebra segments with blue discs
between them, a large vertebra for a head, stubby arms and feet, and the harness
(pink strap, belt and one sensor pod) on its back. Every segment is rigid and
hangs on its own bone, so bending the bones bends the column like a spine.

Blender axes: Z up, Buko faces -Y (its back is +Y). Height ~1.0.
Bones (bottom to top): root, pelvis, seg1, seg2, seg3, head; arm.L / arm.R on seg3.
"""
import math
import os

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "buko.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mat(name, hexcol, rough=0.6, emit=None, coat=0.0, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(hexcol), 1)
    b.inputs["Roughness"].default_value = rough
    if coat:
        b.inputs["Coat Weight"].default_value = coat
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(emit), 1)
        b.inputs["Emission Strength"].default_value = 3.0
    return m


M = {
    "bone": mat("Bone", "#EFE7D4", 0.55),
    "bone2": mat("BoneShade", "#E2D6BC", 0.6),
    "disc": mat("Disc", "#8FB0CC", 0.35, coat=0.4),
    "shoe": mat("Shoe", "#2E4057", 0.5),
    "sole": mat("Sole", "#F4F1EA", 0.7),
    "strap": mat("Strap", "#E4467C", 0.55),
    "pod": mat("Pod", "#24323C", 0.3, coat=0.6),
    "led": mat("LED", "#4FC3F7", 0.3, emit="#4FC3F7"),
    "eye": mat("Eye", "#1B2630", 0.12, coat=1.0),
    "glint": mat("Glint", "#FFFFFF", 0.2, emit="#FFFFFF"),
    "blush": mat("Blush", "#F0A39B", 0.8),
    "mouth": mat("Mouth", "#5E2A2F", 0.5),
    "brow": mat("Brow", "#6B5A47", 0.6),
}


def link(o):
    scene.collection.objects.link(o)
    return o


def select_only(*objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply_mods(o):
    select_only(o)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def from_bm(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    o.data.materials.append(M[material])
    smooth(o)
    return o


def sphere(name, loc, r, material, seg=32, ring=16, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=ring, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2]))
    o = from_bm(name, bm, material)
    o.location = loc
    o.rotation_euler = rot
    return o


def vertebra_block(name, z0, height, rx, ry, material="bone", n=0.42, notch=0.10, bevel=0.40):
    """A rounded vertebral body: superelliptic in plan, kidney notch at the back, soft rims."""
    bm = bmesh.new()
    seg = 56
    rings = []
    for k, z in enumerate((0.0, height)):
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            c, s = math.cos(a), math.sin(a)
            x = rx * math.copysign(abs(c) ** n, c)
            y = ry * math.copysign(abs(s) ** n, s)
            if y > 0:  # back side (+Y): a shallow notch in the middle, like the spinal canal side
                y -= notch * ry * math.exp(-(x / (0.45 * rx)) ** 2)
            ring.append(bm.verts.new((x, y, z0 + z)))
        rings.append(ring)
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = from_bm(name, bm, material)
    bv = o.modifiers.new("Bevel", "BEVEL")
    bv.width = height * bevel
    bv.segments = 5
    bv.limit_method = "ANGLE"
    sb = o.modifiers.new("Sub", "SUBSURF")
    sb.levels = 1
    apply_mods(o)
    smooth(o)
    return o


def nub(name, base, tip, r0, r1, material="bone"):
    """A soft process (spinous / transverse) as a tapered blob between two points."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(base), Vector(tip)], [(0, 1)], [])
    o = link(bpy.data.objects.new(name, me))
    sk = o.modifiers.new("Skin", "SKIN")
    for v, r in zip(o.data.skin_vertices[0].data, (r0, r1)):
        v.radius = (r, r)
    o.data.skin_vertices[0].data[0].use_root = True
    sb = o.modifiers.new("Sub", "SUBSURF")
    sb.levels = 3
    apply_mods(o)
    o.data.materials.append(M[material])
    smooth(o)
    return o


def join(name, objs):
    select_only(*objs)
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


# ---------------------------------------------------------------- the column
# (name, bottom z, height, half-width, half-depth)
SEGS = [("Pelvis", 0.075, 0.150, 0.180, 0.135),
        ("Seg1", 0.262, 0.110, 0.160, 0.122),
        ("Seg2", 0.410, 0.110, 0.158, 0.120),
        ("Seg3", 0.558, 0.110, 0.165, 0.124)]
DISC_H = 0.034
segs = {}
bodies = {}
for name, z0, h, rx, ry in SEGS:
    body = vertebra_block(f"{name}_body", z0, h, rx, ry)
    bodies[name] = body
    parts = [body]
    # spinous process at the back, pointing back and down; small transverse nubs at the sides
    if name != "Seg3":  # the pod sits on the back of the top segment
        parts.append(nub(f"{name}_sp", (0, ry * 0.75, z0 + h * 0.55), (0, ry + 0.055, z0 + h * 0.30), 0.040, 0.030))
    for s in (1, -1):
        parts.append(nub(f"{name}_tr{s}", (s * rx * 0.80, ry * 0.25, z0 + h * 0.55), (s * (rx + 0.040), ry * 0.40, z0 + h * 0.58),
                         0.032, 0.026))
    segs[name] = parts  # joined after the strap is laid on the plain body
discs = {}
for (name, z0, h, rx, ry), nxt in zip(SEGS, SEGS[1:] + [("Head", 0.706, 0, 0, 0)]):
    top = z0 + h
    discs[name] = vertebra_block(f"Disc_{name}", top - 0.004, DISC_H + 0.008, rx * 0.93, ry * 0.93, material="disc",
                                 n=0.5, notch=0.08, bevel=0.45)

# head: a big, soft vertebra
HZ0, HH, HRX, HRY = 0.700, 0.345, 0.235, 0.195
head = vertebra_block("Head", HZ0, HH, HRX, HRY, n=0.55, notch=0.05, bevel=0.50)
head_parts = [head,
              nub("Head_sp", (0, HRY * 0.8, HZ0 + HH * 0.45), (0, HRY + 0.07, HZ0 + HH * 0.32), 0.055, 0.042)]
for s in (1, -1):  # transverse processes as little ears
    head_parts.append(nub(f"Head_ear{s}", (s * HRX * 0.85, 0.02, HZ0 + HH * 0.58), (s * (HRX + 0.055), 0.04, HZ0 + HH * 0.64),
                          0.045, 0.036))
head = join("Head", head_parts)
HEAD_FRONT = -HRY  # y of the face plane


def face_point(x, z, lift=0.0):
    """Point on the face of the head (ray cast from the front)."""
    deps = bpy.context.evaluated_depsgraph_get()
    hit, loc, nrm, _ = head.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)), depsgraph=deps)
    if not hit:
        raise RuntimeError("face miss")
    return loc + nrm * lift, nrm


def facing(nrm):
    return (-nrm).to_track_quat("Y", "Z").to_euler()


EYE_Z = HZ0 + HH * 0.56
face = []
for s, side in ((1, "L"), (-1, "R")):
    p, n = face_point(s * 0.090, EYE_Z, -0.004)
    face.append(sphere(f"Eye{side}", p, (0.040, 0.020, 0.055), "eye", rot=facing(n)))
    g, _ = face_point(s * 0.090 - 0.012, EYE_Z + 0.022, 0.014)
    face.append(sphere(f"Glint{side}", g, (0.013, 0.007, 0.015), "glint", seg=16, ring=8))
    b, n2 = face_point(s * 0.094, EYE_Z + 0.082, 0.004)
    brow = nub(f"Brow{side}", (-0.026, 0, 0), (0.026, 0, 0), 0.0085, 0.0075, material="brow")
    brow.location = b
    brow.rotation_euler = facing(n2)
    face.append(brow)
    c, n3 = face_point(s * 0.150, EYE_Z - 0.060, -0.003)
    face.append(sphere(f"Blush{side}", c, (0.038, 0.004, 0.022), "blush", rot=facing(n3)))


def mouth(name, curve_up, width=0.040):
    bm = bmesh.new()
    n, k = 14, 10
    r = 0.0085
    rings = []
    for i in range(n + 1):
        u = i / n * 2 - 1
        x, z = u * width, curve_up * (u * u - 0.4)
        taper = 1 - 0.45 * abs(u) ** 2
        rings.append([bm.verts.new((x, r * 0.6 * math.sin(2 * math.pi * j / k) * taper,
                                    z + r * math.cos(2 * math.pi * j / k) * taper)) for j in range(k)])
    for i in range(n):
        for j in range(k):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % k], rings[i + 1][(j + 1) % k], rings[i + 1][j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    o = from_bm(name, bm, "mouth")
    p, nrm = face_point(0, EYE_Z - 0.095, 0.002)
    o.location = p
    o.rotation_euler = facing(nrm)
    return o


mouths = [mouth("MouthSmile", 0.032), mouth("MouthFlat", 0.004), mouth("MouthFrown", -0.024)]

# arms on the top body segment, feet under the pelvis
arms = {}
for s, side in ((1, "L"), (-1, "R")):
    sz = SEGS[3][1] + 0.075
    sh = (s * 0.165, 0.0, sz)
    hand = (s * 0.250, -0.020, sz - 0.200)
    upper = nub(f"Arm{side}", sh, hand, 0.050, 0.044)
    mit = sphere(f"Hand{side}", hand, (0.058, 0.052, 0.062), "bone")
    arms[side] = join(f"Arm{side}", [upper, mit])
feet = []
for s, side in ((1, "L"), (-1, "R")):
    feet.append(sphere(f"Shoe{side}", (s * 0.105, -0.030, 0.050), (0.085, 0.120, 0.055), "shoe"))
    feet.append(sphere(f"Sole{side}", (s * 0.105, -0.030, 0.016), (0.087, 0.122, 0.016), "sole"))

# ---------------------------------------------------------------- harness
deps = bpy.context.evaluated_depsgraph_get()


def back_point(obj, x, z, lift):
    hit, loc, nrm, _ = obj.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)), depsgraph=deps)
    if not hit:
        return None, None
    return loc + nrm * lift, nrm


straps = {}
for name, z0, h, rx, ry in SEGS:
    bm = bmesh.new()
    rows = []
    for k in range(9):
        z = z0 + h * (0.08 + 0.84 * k / 8)
        p, n = back_point(bodies[name], 0.0, z, 0.004)
        if p is None:
            continue
        rows.append([bm.verts.new(p + Vector((x, 0, 0))) for x in (-0.030, 0.030)])
    for a, b in zip(rows, rows[1:]):
        bm.faces.new((a[0], a[1], b[1], b[0]))
    o = from_bm(f"Strap_{name}", bm, "strap")
    so = o.modifiers.new("Solid", "SOLIDIFY")
    so.thickness = 0.006
    so.offset = 1
    apply_mods(o)
    smooth(o)
    straps[name] = o
deps = bpy.context.evaluated_depsgraph_get()
POD_P, POD_N = back_point(bodies["Seg3"], 0.0, SEGS[3][1] + SEGS[3][2] * 0.5, 0.022)
for name in list(segs):
    segs[name] = join(name, segs[name])
deps = bpy.context.evaluated_depsgraph_get()
# belt round the pelvis segment
bm = bmesh.new()
N = 72
z0, h, rx, ry = SEGS[0][1], SEGS[0][2], SEGS[0][3], SEGS[0][4]
zc = z0 + h * 0.52
rings = []
for i in range(N):
    a = 2 * math.pi * i / N
    d = Vector((math.cos(a), math.sin(a), 0))
    hit, loc, nrm, _ = segs["Pelvis"].ray_cast(Vector((0, 0, zc)), d, depsgraph=deps)
    out = Vector((nrm.x, nrm.y, 0)).normalized()
    rings.append([bm.verts.new(loc + out * o + Vector((0, 0, hh))) for (o, hh) in
                  ((-0.002, -0.030), (0.010, -0.030), (0.010, 0.030), (-0.002, 0.030))])
for i in range(N):
    a, b = rings[i], rings[(i + 1) % N]
    for k in range(4):
        bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
belt = from_bm("Belt", bm, "strap")
bv = belt.modifiers.new("Bevel", "BEVEL")
bv.width = 0.004
bv.segments = 2
apply_mods(belt)
smooth(belt)
# one sensor pod on the back of the top segment
p, n = POD_P, POD_N
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
pod = from_bm("Pod", bm, "pod")
pod.scale = (0.070, 0.026, 0.055)
select_only(pod)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
pb = pod.modifiers.new("Bevel", "BEVEL")
pb.width = 0.010
pb.segments = 4
pod.modifiers.new("Sub", "SUBSURF").levels = 1
apply_mods(pod)
smooth(pod)
pod.location = p
led = sphere("LED", p + Vector((0.020, 0.014, 0.014)), (0.008, 0.008, 0.008), "led", seg=16, ring=8)

# ---------------------------------------------------------------- skeleton (rig)
arm_data = bpy.data.armatures.new("BukoRig")
rig = link(bpy.data.objects.new("BukoRig", arm_data))
select_only(rig)
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones


def bone(name, head_pt, tail_pt, parent=None):
    b = eb.new(name)
    b.head, b.tail, b.roll = head_pt, tail_pt, 0
    if parent:
        b.parent = eb[parent]
    return b


bone("root", (0, 0, 0), (0, 0, 0.07))
bone("pelvis", (0, 0, 0.075), (0, 0, 0.245), "root")
bone("seg1", (0, 0, 0.245), (0, 0, 0.393), "pelvis")
bone("seg2", (0, 0, 0.393), (0, 0, 0.541), "seg1")
bone("seg3", (0, 0, 0.541), (0, 0, 0.690), "seg2")
bone("head", (0, 0, 0.690), (0, 0, 1.03), "seg3")
for s, side in ((1, "L"), (-1, "R")):
    sz = SEGS[3][1] + 0.075
    bone(f"arm.{side}", (s * 0.165, 0, sz), (s * 0.250, -0.020, sz - 0.200), "seg3")
bpy.ops.object.mode_set(mode="OBJECT")


def to_bone(objs, bname):
    bpy.context.view_layer.update()
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = rig
        o.parent_type = "BONE"
        o.parent_bone = bname
        o.matrix_world = mw


to_bone([segs["Pelvis"], discs["Pelvis"], straps["Pelvis"], belt], "pelvis")
to_bone([segs["Seg1"], discs["Seg1"], straps["Seg1"]], "seg1")
to_bone([segs["Seg2"], discs["Seg2"], straps["Seg2"]], "seg2")
to_bone([segs["Seg3"], discs["Seg3"], straps["Seg3"], pod, led], "seg3")
to_bone([head, *face, *mouths], "head")
to_bone([arms["L"]], "arm.L")
to_bone([arms["R"]], "arm.R")
to_bone(feet, "root")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=False,
                          export_skins=False, export_animations=False, export_materials="EXPORT",
                          export_cameras=False, export_lights=False)
faces = sum(len(o.data.polygons) for o in scene.objects if o.type == "MESH")
print("WROTE", OUT, os.path.getsize(OUT), "bytes,", faces, "faces")
