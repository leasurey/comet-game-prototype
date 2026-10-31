"""COMET 角色生成器 — Blender 5.x 后台脚本

用途：程序化构建带骨架与动画的人形角色，导出 GLB 供 Godot 使用。

设计要点（与「圆柱拼装」的本质区别）：
- 躯干/四肢用「环放样」(loft) 生成，截面是椭圆，有真实人体收放（肩宽/腰细/胯宽）。
- 每个顶点在**构建时**就带上骨骼权重（不是导出后自动权重），关节处显式混合，
  因此形变可控、无「骨头热扩散失败」问题。
- 骨架 20 根骨骼，真实蒙皮；动画以 Action 形式存在，glTF 导出为独立 AnimationPlayer 片段。

用法：
    blender.exe --background --factory-startup --python tools/blender/build_character.py -- \
        --out assets/models/characters --only kevin
"""

import bpy
import bmesh
import math
import os
import sys
import json

PI = math.pi
SIN = math.sin
COS = math.cos

# --------------------------------------------------------------------------
# 角色配置：外观差异（肤色/发色/服色/身材）
# height 为净身高（米），build 为体宽系数（1.0 = 标准）
# --------------------------------------------------------------------------
CHARACTERS = {
    "kevin": dict(
        name="Kevin", height=1.79, build=1.00, shoulder=1.00,
        skin=(0.855, 0.700, 0.590), hair=(0.285, 0.200, 0.125),
        shirt=(0.235, 0.320, 0.480), pants=(0.215, 0.225, 0.265),
        shoes=(0.115, 0.100, 0.095), hair_style="short", sleeve="rolled",
    ),
    "mike": dict(
        name="Mike", height=1.76, build=1.10, shoulder=1.06,
        skin=(0.800, 0.650, 0.550), hair=(0.140, 0.115, 0.095),
        shirt=(0.520, 0.470, 0.420), pants=(0.290, 0.270, 0.240),
        shoes=(0.135, 0.120, 0.105), hair_style="short", sleeve="short",
    ),
    "lee": dict(
        name="Lee", height=1.66, build=0.97, shoulder=0.94,
        skin=(0.880, 0.740, 0.640), hair=(0.520, 0.420, 0.290),
        shirt=(0.430, 0.340, 0.250), pants=(0.265, 0.265, 0.300),
        shoes=(0.150, 0.130, 0.115), hair_style="long", sleeve="long",
    ),
    "beth": dict(
        name="Beth", height=1.68, build=0.98, shoulder=0.95,
        skin=(0.825, 0.685, 0.585), hair=(0.630, 0.480, 0.290),
        shirt=(0.615, 0.330, 0.375), pants=(0.330, 0.285, 0.330),
        shoes=(0.145, 0.125, 0.110), hair_style="long", sleeve="long",
    ),
    "hugh": dict(
        name="Hugh", height=1.81, build=1.02, shoulder=1.02,
        skin=(0.810, 0.680, 0.580), hair=(0.190, 0.170, 0.145),
        shirt=(0.330, 0.420, 0.380), pants=(0.235, 0.235, 0.280),
        shoes=(0.110, 0.100, 0.095), hair_style="short", sleeve="long",
    ),
    "amir": dict(
        name="Amir", height=1.74, build=0.98, shoulder=0.98,
        skin=(0.715, 0.570, 0.445), hair=(0.115, 0.095, 0.075),
        shirt=(0.470, 0.520, 0.610), pants=(0.285, 0.285, 0.265),
        shoes=(0.125, 0.115, 0.105), hair_style="short", sleeve="rolled",
    ),
    "laurie": dict(
        name="Laurie", height=1.70, build=0.95, shoulder=0.93,
        skin=(0.865, 0.725, 0.630), hair=(0.720, 0.570, 0.380),
        shirt=(0.430, 0.520, 0.610), pants=(0.375, 0.330, 0.285),
        shoes=(0.160, 0.135, 0.120), hair_style="long", sleeve="long",
    ),
}

NOMINAL_HEIGHT = 1.75

# --------------------------------------------------------------------------
# 骨架定义（名义尺寸，未缩放）
# name, head, tail, parent, deform
# --------------------------------------------------------------------------
BONES_CENTER = [
    ("root",     (0, 0, 0.000), (0, 0, 0.120), None,    False),
    ("hips",     (0, 0, 0.950), (0, 0, 1.060), "root",  True),
    ("spine",    (0, 0, 1.060), (0, 0, 1.260), "hips",  True),
    ("chest",    (0, 0, 1.260), (0, 0, 1.440), "spine", True),
    ("neck",     (0, 0, 1.440), (0, 0, 1.552), "chest", True),
    ("head",     (0, 0, 1.552), (0, 0, 1.760), "neck",  True),
]

BONES_SIDE = [
    ("shoulder",  (0.030, 0.000, 1.418), (0.176, 0.000, 1.412), "chest",     True),
    ("upper_arm", (0.176, 0.000, 1.412), (0.214, 0.000, 1.140), "shoulder",  True),
    ("forearm",   (0.214, 0.000, 1.140), (0.224, 0.020, 0.902), "upper_arm", True),
    ("hand",      (0.224, 0.020, 0.902), (0.228, 0.030, 0.780), "forearm",   True),
    ("thigh",     (0.088, 0.000, 0.920), (0.092, 0.000, 0.500), "hips",      True),
    ("shin",      (0.092, 0.000, 0.500), (0.092, 0.005, 0.090), "thigh",     True),
    ("foot",      (0.092, 0.005, 0.090), (0.092, 0.160, 0.030), "shin",      True),
]


def bone_table():
    """展开左右侧骨骼，返回完整列表。"""
    out = list(BONES_CENTER)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        for name, h, t, parent, deform in BONES_SIDE:
            bname = "%s.%s" % (name, side)
            pname = parent
            if parent in ("shoulder", "upper_arm", "forearm", "hand", "thigh", "shin", "foot"):
                pname = "%s.%s" % (parent, side)
            out.append((
                bname,
                (h[0] * sx, h[1], h[2]),
                (t[0] * sx, t[1], t[2]),
                pname,
                deform,
            ))
    return out


# --------------------------------------------------------------------------
# 网格构建器：同时累积顶点、面、材质索引、逐顶点骨骼权重
# --------------------------------------------------------------------------
class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.face_mats = []
        self.weights = []      # 每顶点 {bone: weight}

    def v(self, co, w):
        self.verts.append((float(co[0]), float(co[1]), float(co[2])))
        self.weights.append(dict(w))
        return len(self.verts) - 1

    def f(self, idx, mat):
        self.faces.append(tuple(idx))
        self.face_mats.append(mat)

    # ---- 环 ----
    def ring(self, center, rx, ry, segs, w, y_off=0.0):
        base = len(self.verts)
        cx, cy, cz = center
        for i in range(segs):
            a = 2.0 * PI * i / segs
            x = cx + rx * COS(a)
            y = cy + ry * SIN(a) + y_off
            self.v((x, y, cz), w)
        return base

    def bridge(self, a, b, segs, mat):
        for i in range(segs):
            j = (i + 1) % segs
            self.f((a + i, a + j, b + j, b + i), mat)

    def cap(self, base, segs, center_co, w, mat):
        c = self.v(center_co, w)
        for i in range(segs):
            j = (i + 1) % segs
            self.f((base + i, base + j, c), mat)

    def ring_xz(self, center, rx, rz, segs, w):
        base = len(self.verts)
        cx, cy, cz = center
        for i in range(segs):
            a = 2.0 * PI * i / segs
            x = cx + rx * COS(a)
            z = cz + rz * SIN(a)
            self.v((x, cy, z), w)
        return base

    def tube_y(self, sections, segs, mat, cap_start=True, cap_end=True):
        """沿 +Y 放样（用于鞋）：section = (y, cx, cz, rx, rz, weights)"""
        bases = []
        for y, cx, cz, rx, rz, w in sections:
            bases.append(self.ring_xz((cx, y, cz), rx, rz, segs, w))
        for i in range(len(bases) - 1):
            self.bridge(bases[i], bases[i + 1], segs, mat)
        if cap_start:
            y, cx, cz, rx, rz, w = sections[0]
            self.cap(bases[0], segs, (cx, y, cz), w, mat)
        if cap_end:
            y, cx, cz, rx, rz, w = sections[-1]
            self.cap(bases[-1], segs, (cx, y, cz), w, mat)
        return bases

    def tube(self, sections, segs, mat, cap_start=True, cap_end=True):
        """sections: [(center, rx, ry, weights), ...] 自上而下或自下而上连续。"""
        bases = []
        for center, rx, ry, w in sections:
            bases.append(self.ring(center, rx, ry, segs, w))
        for i in range(len(bases) - 1):
            self.bridge(bases[i], bases[i + 1], segs, mat)
        if cap_start:
            c0, r0, ry0, w0 = sections[0]
            self.cap(bases[0], segs, c0, w0, mat)
        if cap_end:
            c1, r1, ry1, w1 = sections[-1]
            self.cap(bases[-1], segs, c1, w1, mat)
        return bases

    def ellipsoid(self, center, radii, segs, rings, w, mat, skip_face=None):
        """UV 球。skip_face(x,y,z)->bool 可挖掉局部（用于头发露脸）。"""
        cx, cy, cz = center
        rx, ry, rz = radii
        grid = []
        for r in range(1, rings):
            lat = -PI / 2.0 + PI * r / rings
            row = []
            for s in range(segs):
                lon = 2.0 * PI * s / segs
                x = cx + rx * COS(lat) * COS(lon)
                y = cy + ry * COS(lat) * SIN(lon)
                z = cz + rz * SIN(lat)
                row.append(self.v((x, y, z), w))
            grid.append(row)
        top = self.v((cx, cy, cz + rz), w)
        bot = self.v((cx, cy, cz - rz), w)

        def keep(pts):
            if skip_face is None:
                return True
            mx = sum(p[0] for p in pts) / len(pts)
            my = sum(p[1] for p in pts) / len(pts)
            mz = sum(p[2] for p in pts) / len(pts)
            return not skip_face(mx, my, mz)

        for s in range(segs):
            s2 = (s + 1) % segs
            pts = [self.verts[top], self.verts[grid[0][s]], self.verts[grid[0][s2]]]
            if keep(pts):
                self.f((top, grid[0][s], grid[0][s2]), mat)
            pts = [self.verts[bot], self.verts[grid[-1][s2]], self.verts[grid[-1][s]]]
            if keep(pts):
                self.f((bot, grid[-1][s2], grid[-1][s]), mat)
        for r in range(len(grid) - 1):
            for s in range(segs):
                s2 = (s + 1) % segs
                quad = (grid[r][s], grid[r][s2], grid[r + 1][s2], grid[r + 1][s])
                pts = [self.verts[i] for i in quad]
                if keep(pts):
                    self.f(quad, mat)

    def box(self, center, size, w, mat):
        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        idx = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    idx.append(self.v((cx + sx * hx, cy + sy * hy, cz + sz * hz), w))
        # 顶点序：000,001,010,011,100,101,110,111 (x,y,z 各取 -/+)
        b = idx
        quads = [
            (b[0], b[1], b[3], b[2]),  # -X
            (b[4], b[6], b[7], b[5]),  # +X
            (b[0], b[4], b[5], b[1]),  # -Y
            (b[2], b[3], b[7], b[6]),  # +Y
            (b[0], b[2], b[6], b[4]),  # -Z
            (b[1], b[5], b[7], b[3]),  # +Z
        ]
        for q in quads:
            self.f(q, mat)


# --------------------------------------------------------------------------
# 材质
# --------------------------------------------------------------------------
def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def make_material(name, rgb, roughness=0.7, specular=0.3):
    lin = [srgb_to_linear(max(0.0, min(1.0, v))) for v in rgb[:3]]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
    return mat


MAT_ORDER = ["skin", "hair", "shirt", "pants", "shoes", "eye", "mouth"]


def build_materials(cfg):
    def darken(c, k):
        return (c[0] * k, c[1] * k, c[2] * k)

    mats = {
        "skin": make_material("skin", cfg["skin"], 0.62),
        "hair": make_material("hair", cfg["hair"], 0.55),
        "shirt": make_material("shirt", cfg["shirt"], 0.85),
        "pants": make_material("pants", cfg["pants"], 0.85),
        "shoes": make_material("shoes", cfg["shoes"], 0.45),
        "eye": make_material("eye", (0.10, 0.09, 0.09), 0.25),
        "mouth": make_material("mouth", darken(cfg["skin"], 0.55), 0.55),
    }
    return [mats[k] for k in MAT_ORDER], {k: i for i, k in enumerate(MAT_ORDER)}


# --------------------------------------------------------------------------
# 人体网格
# --------------------------------------------------------------------------
def build_body(cfg):
    """构建人体网格（v2）。

    结构改进：
    - 躯干拆成「骨盆(裤) + 上衣(衬衫,下摆外扩)」，消除「连衣裙」外观
    - 肩部加三角肌球体，消除手臂与躯干的接缝
    - 袖子按 sleeve 配置分长短
    - 脚用沿 Y 轴放样，得到真实鞋型（不再是小方块）
    """
    bd = cfg["build"]
    sh = cfg["shoulder"]
    sleeve = cfg.get("sleeve", "long")
    mb = MeshBuilder()
    _, MI = build_materials(cfg)
    SKIN = MI["skin"]
    HAIR = MI["hair"]
    SHIRT = MI["shirt"]
    PANTS = MI["pants"]
    SHOES = MI["shoes"]
    EYE = MI["eye"]
    MOUTH = MI["mouth"]

    # ---------------- 骨盆（裤子） ----------------
    pelvis = [
        ((0, 0, 0.898), 0.112 * bd, 0.090 * bd, {"hips": 1.0}),
        ((0, 0, 0.940), 0.140 * bd, 0.100 * bd, {"hips": 1.0}),
        ((0, 0, 0.985), 0.142 * bd, 0.101 * bd, {"hips": 1.0}),
        ((0, 0, 1.024), 0.146 * bd, 0.102 * bd, {"hips": 0.7, "spine": 0.3}),
    ]
    mb.tube(pelvis, 16, PANTS, cap_start=True, cap_end=True)

    # ---------------- 上衣（衬衫） ----------------
    torso = [
        ((0, 0, 0.890), 0.172 * bd, 0.117 * bd, {"hips": 0.85, "spine": 0.15}),
        ((0, 0, 1.000), 0.160 * bd, 0.110 * bd, {"hips": 0.5, "spine": 0.5}),
        ((0, 0, 1.072), 0.150 * bd, 0.103 * bd, {"spine": 1.0}),
        ((0, 0, 1.165), 0.165 * bd, 0.110 * bd, {"spine": 0.55, "chest": 0.45}),
        ((0, 0, 1.255), 0.182 * sh * bd, 0.118 * bd, {"chest": 1.0}),
        ((0, 0, 1.345), 0.195 * sh * bd, 0.119 * bd, {"chest": 1.0}),
        ((0, 0, 1.416), 0.198 * sh * bd, 0.112 * bd, {"chest": 0.85, "neck": 0.15}),
        ((0, 0, 1.452), 0.138 * bd, 0.095 * bd, {"chest": 0.5, "neck": 0.5}),
    ]
    mb.tube(torso, 16, SHIRT, cap_start=True, cap_end=True)

    # 衣领（一圈略高的衬衫环）
    mb.tube([
        ((0, 0.004, 1.446), 0.082 * bd, 0.078 * bd, {"neck": 0.6, "chest": 0.4}),
        ((0, 0.004, 1.478), 0.074 * bd, 0.072 * bd, {"neck": 0.9, "chest": 0.1}),
    ], 14, SHIRT, cap_start=False, cap_end=False)

    # ---------------- 颈 ----------------
    neck = [
        ((0, 0.004, 1.440), 0.058 * bd, 0.055 * bd, {"neck": 1.0}),
        ((0, 0.006, 1.505), 0.052 * bd, 0.050 * bd, {"neck": 0.75, "head": 0.25}),
        ((0, 0.006, 1.548), 0.050 * bd, 0.048 * bd, {"head": 1.0}),
    ]
    mb.tube(neck, 12, SKIN, cap_start=False, cap_end=False)

    # ---------------- 头 ----------------
    head_c = (0, 0.006, 1.646)
    hw = {"head": 1.0}
    mb.ellipsoid(head_c, (0.094 * bd, 0.106 * bd, 0.120 * bd), 18, 12, hw, SKIN)
    mb.ellipsoid((0, 0.026, 1.584), (0.076 * bd, 0.089 * bd, 0.052 * bd), 14, 9, hw, SKIN)
    for sx in (-1, 1):
        mb.ellipsoid((sx * 0.036, 0.099 * bd, 1.664), (0.012, 0.011, 0.011), 10, 7, hw, EYE)
        mb.box((sx * 0.038, 0.101 * bd, 1.684), (0.031, 0.010, 0.007), hw, HAIR)
        mb.ellipsoid((sx * 0.096 * bd, 0.002, 1.638), (0.013, 0.022, 0.032), 10, 7, hw, SKIN)
    mb.box((0, 0.106 * bd, 1.630), (0.030, 0.036, 0.046), hw, SKIN)
    mb.box((0, 0.105 * bd, 1.600), (0.034, 0.014, 0.009), hw, MOUTH)

    # ---------------- 头发 ----------------
    if cfg["hair_style"] == "long":
        mb.ellipsoid((0, -0.004, 1.658), (0.104 * bd, 0.117 * bd, 0.130 * bd), 18, 12, hw, HAIR,
                     skip_face=lambda x, y, z: (y > 0.022 and z < 1.700) or z < 1.556)
        mb.tube([
            ((0, -0.056, 1.638), 0.100 * bd, 0.056 * bd, hw),
            ((0, -0.062, 1.556), 0.102 * bd, 0.053 * bd, hw),
            ((0, -0.060, 1.474), 0.094 * bd, 0.047 * bd, hw),
            ((0, -0.052, 1.428), 0.082 * bd, 0.041 * bd, hw),
        ], 14, HAIR, cap_start=False, cap_end=True)
    else:
        mb.ellipsoid((0, -0.004, 1.658), (0.103 * bd, 0.115 * bd, 0.126 * bd), 18, 12, hw, HAIR,
                     skip_face=lambda x, y, z: (y > 0.020 and z < 1.698) or z < 1.596)

    # ---------------- 双臂 ----------------
    # 袖子终点的截面索引：short=肩膀下一点，rolled=前臂中段，long=手腕
    sleeve_idx = {"short": 3, "rolled": 4, "long": 7}[sleeve]

    for sx, side in ((1.0, "L"), (-1.0, "R")):
        ua = "upper_arm.%s" % side
        fa = "forearm.%s" % side
        hd = "hand.%s" % side
        sb = "shoulder.%s" % side
        x0 = 0.158 * sx * sh

        # 三角肌：填满肩关节，消除接缝
        mb.ellipsoid((x0 * 0.99, 0, 1.358), (0.070 * bd, 0.068 * bd, 0.076 * bd), 14, 10,
                     {sb: 0.5, "chest": 0.5}, SHIRT)

        sections = [
            ((x0 * 1.12, 0, 1.398), 0.060 * bd, 0.060 * bd, {sb: 0.5, "chest": 0.5}),
            ((x0 * 1.20, 0, 1.340), 0.055 * bd, 0.054 * bd, {sb: 0.4, ua: 0.6}),
            ((x0 * 1.28, 0, 1.270), 0.052 * bd, 0.051 * bd, {ua: 1.0}),
            ((x0 * 1.38, 0, 1.160), 0.047 * bd, 0.046 * bd, {ua: 0.7, fa: 0.3}),
            ((x0 * 1.45, 0.004, 1.110), 0.045 * bd, 0.044 * bd, {fa: 1.0}),
            ((x0 * 1.52, 0.012, 1.000), 0.040 * bd, 0.039 * bd, {fa: 1.0}),
            ((x0 * 1.56, 0.016, 0.930), 0.036 * bd, 0.035 * bd, {fa: 0.8, hd: 0.2}),
            ((x0 * 1.58, 0.020, 0.898), 0.033 * bd, 0.032 * bd, {fa: 0.4, hd: 0.6}),
        ]
        mb.tube(sections[:sleeve_idx], 12, SHIRT, cap_start=True, cap_end=False)
        mb.tube(sections[sleeve_idx - 1:], 12, SKIN, cap_start=False, cap_end=True)

        # 手掌
        hx = x0 * 1.60
        mb.tube([
            ((hx, 0.022, 0.896), 0.030 * bd, 0.041 * bd, {hd: 1.0}),
            ((hx, 0.026, 0.850), 0.029 * bd, 0.045 * bd, {hd: 1.0}),
            ((hx, 0.028, 0.806), 0.025 * bd, 0.039 * bd, {hd: 1.0}),
            ((hx, 0.030, 0.782), 0.017 * bd, 0.027 * bd, {hd: 1.0}),
        ], 10, SKIN, cap_start=False, cap_end=True)
        mb.box((hx - 0.032 * sx, 0.042, 0.868), (0.024, 0.050, 0.032), {hd: 1.0}, SKIN)

    # ---------------- 双腿 ----------------
    for sx, side in ((1.0, "L"), (-1.0, "R")):
        th = "thigh.%s" % side
        sn = "shin.%s" % side
        ft = "foot.%s" % side
        x0 = 0.086 * sx
        mb.tube([
            ((x0 * 0.97, 0, 0.948), 0.098 * bd, 0.094 * bd, {"hips": 0.45, th: 0.55}),
            ((x0, 0, 0.880), 0.094 * bd, 0.090 * bd, {th: 1.0}),
            ((x0 * 1.02, 0, 0.700), 0.077 * bd, 0.074 * bd, {th: 1.0}),
            ((x0 * 1.04, 0, 0.545), 0.063 * bd, 0.061 * bd, {th: 0.65, sn: 0.35}),
            ((x0 * 1.04, 0, 0.480), 0.059 * bd, 0.057 * bd, {sn: 1.0}),
            ((x0 * 1.04, 0.002, 0.320), 0.052 * bd, 0.051 * bd, {sn: 1.0}),
            ((x0 * 1.04, 0.004, 0.135), 0.042 * bd, 0.041 * bd, {sn: 0.7, ft: 0.3}),
            ((x0 * 1.04, 0.005, 0.092), 0.038 * bd, 0.038 * bd, {ft: 1.0}),
        ], 14, PANTS, cap_start=True, cap_end=False)

        # 鞋：沿 Y 轴放样（真实鞋型）
        fx = x0 * 1.04
        mb.tube_y([
            (-0.078, fx, 0.044, 0.040 * bd, 0.043, {ft: 1.0}),
            (-0.040, fx, 0.042, 0.049 * bd, 0.041, {ft: 1.0}),
            (0.010, fx, 0.040, 0.053 * bd, 0.039, {ft: 1.0}),
            (0.070, fx, 0.036, 0.052 * bd, 0.035, {ft: 1.0}),
            (0.135, fx, 0.032, 0.047 * bd, 0.031, {ft: 1.0}),
            (0.185, fx, 0.028, 0.036 * bd, 0.026, {ft: 1.0}),
        ], 12, SHOES, cap_start=True, cap_end=True)

    return mb, MI


# --------------------------------------------------------------------------
# 对象创建
# --------------------------------------------------------------------------
def create_mesh_object(name, mb, materials, mat_index):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(mb.verts, [], mb.faces)
    mesh.update()

    for m in materials:
        mesh.materials.append(m)
    for i, poly in enumerate(mesh.polygons):
        poly.material_index = mb.face_mats[i]

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    # 法线重算（保证外向）
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    # 平滑
    for poly in mesh.polygons:
        poly.use_smooth = True

    # 细分 1 级（增加曲面观感）
    sub = obj.modifiers.new("Subdiv", 'SUBSURF')
    sub.levels = 1
    sub.render_levels = 1

    return obj


def create_armature(name, scale):
    arm_data = bpy.data.armatures.new(name + "Data")
    arm_obj = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='EDIT')

    table = bone_table()
    created = {}
    for bname, head, tail, parent, deform in table:
        eb = arm_data.edit_bones.new(bname)
        eb.head = (head[0] * scale, head[1] * scale, head[2] * scale)
        eb.tail = (tail[0] * scale, tail[1] * scale, tail[2] * scale)
        eb.roll = 0.0
        eb.use_deform = deform
        created[bname] = eb
    for bname, head, tail, parent, deform in table:
        if parent and parent in created:
            created[bname].parent = created[parent]
            created[bname].use_connect = False

    bpy.ops.object.mode_set(mode='OBJECT')
    return arm_obj


def assign_weights(obj, arm_obj, mb):
    groups = {}
    for wmap in mb.weights:
        for bone in wmap:
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
    # remove_doubles 可能造成顶点数变化：只在数量一致时逐个赋值
    if len(mb.weights) != len(obj.data.vertices):
        print("[WARN] 顶点数变化 %d -> %d，改用最近邻权重回填"
              % (len(mb.weights), len(obj.data.vertices)))
        # blob 细分后顶点倍增，顶点组会插值——此处直接跳过逐点赋值，
        # 由下方“几何最近骨”兜底逻辑处理
        assign_weights_by_distance(obj, arm_obj)
        return
    for i, wmap in enumerate(mb.weights):
        total = sum(wmap.values()) or 1.0
        for bone, wt in wmap.items():
            if wt <= 0.0:
                continue
            groups[bone].add([i], wt / total, 'REPLACE')


def assign_weights_by_distance(obj, arm_obj):
    """兜底：按到骨骼线段的距离反比赋权（仅用于顶点数变化的情况）。"""
    bones = [b for b in arm_obj.data.bones if b.use_deform]
    for b in bones:
        if b.name not in obj.vertex_groups:
            obj.vertex_groups.new(name=b.name)
    for v in obj.data.vertices:
        co = v.co
        scored = []
        for b in bones:
            h = b.head_local
            t = b.tail_local
            ab = t - h
            denom = ab.length_squared or 1e-6
            u = max(0.0, min(1.0, (co - h).dot(ab) / denom))
            closest = h + ab * u
            d = (co - closest).length
            scored.append((d, b.name))
        scored.sort()
        top = scored[:2]
        ws = [(1.0 / (d + 0.02) ** 4, n) for d, n in top]
        total = sum(w for w, _ in ws)
        for w, n in ws:
            obj.vertex_groups[n].add([v.index], w / total, 'REPLACE')


# --------------------------------------------------------------------------
# 动画
# --------------------------------------------------------------------------
def rad(d):
    return math.radians(d)


def set_pose(arm, frame, poses):
    """poses: {bone_name: (rx,ry,rz)} 或 {bone_name: ("loc", x,y,z)}"""
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    for bname, val in poses.items():
        pb = arm.pose.bones.get(bname)
        if pb is None:
            continue
        if isinstance(val, dict):
            if "rot" in val:
                rx, ry, rz = val["rot"]
                from mathutils import Euler
                pb.rotation_quaternion = Euler((rad(rx), rad(ry), rad(rz)), 'XYZ').to_quaternion()
            if "loc" in val:
                pb.location = val["loc"]
        else:
            rx, ry, rz = val
            from mathutils import Euler
            pb.rotation_quaternion = Euler((rad(rx), rad(ry), rad(rz)), 'XYZ').to_quaternion()


def key_all(arm, frame):
    for pb in arm.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def clear_pose(arm):
    from mathutils import Quaternion
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = (0, 0, 0)


def new_action(arm, name):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = None
    clear_pose(arm)
    bpy.context.view_layer.update()


def finalize_action(arm, name):
    act = arm.animation_data.action
    if act is None:
        print("[WARN] 动作 %s 未生成" % name)
        return None
    act.name = name
    act.use_fake_user = True
    for fc in _action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
    arm.animation_data.action = None
    return act


def _action_fcurves(act):
    """兼容 Blender 4.x(.fcurves) 与 5.x(slotted action layer/strip/channelbag)。"""
    fcs = getattr(act, "fcurves", None)
    if fcs is not None:
        try:
            return list(fcs)
        except TypeError:
            pass
    out = []
    for layer in getattr(act, "layers", []):
        for strip in getattr(layer, "strips", []):
            bags = getattr(strip, "channelbags", None)
            if bags is None:
                continue
            try:
                for cb in bags:
                    out.extend(list(cb.fcurves))
            except Exception:
                pass
    return out


def anim_idle(arm):
    """待机：呼吸 + 微重心变化，60 帧循环。"""
    new_action(arm, "idle")
    frames = [
        (1,  {"chest": (0, 0, 0), "spine": (0, 0, 0), "head": (0, 0, 0),
              "hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)},
              "upper_arm.L": (0, 0, -2), "upper_arm.R": (0, 0, 2)}),
        (30, {"chest": (-1.6, 0, 0), "spine": (-0.8, 0, 0), "head": (1.0, 1.5, 0),
              "hips": {"rot": (0, 0, 0), "loc": (0, -0.006, 0)},
              "upper_arm.L": (1.5, 0, -3), "upper_arm.R": (1.5, 0, 3),
              "forearm.L": (-2, 0, 0), "forearm.R": (-2, 0, 0)}),
        (60, {"chest": (0, 0, 0), "spine": (0, 0, 0), "head": (0, 0, 0),
              "hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)},
              "upper_arm.L": (0, 0, -2), "upper_arm.R": (0, 0, 2)}),
    ]
    for f, poses in frames:
        bpy.context.scene.frame_set(f)
        clear_pose(arm)
        set_pose(arm, f, poses)
        key_all(arm, f)
    return finalize_action(arm, "idle")


def anim_walk(arm):
    """行走：32 帧一个完整步态循环。"""
    new_action(arm, "walk")
    A = 26.0   # 大腿摆幅
    B = -34.0  # 小腿弯曲
    frames = [
        # 左脚前
        (1,  {"thigh.L": (A, 0, 0), "shin.L": (-6, 0, 0), "foot.L": (6, 0, 0),
              "thigh.R": (-A * 0.85, 0, 0), "shin.R": (B * 0.55, 0, 0), "foot.R": (18, 0, 0),
              "upper_arm.L": (-A * 0.7, 0, -3), "upper_arm.R": (A * 0.7, 0, 3),
              "forearm.L": (-16, 0, 0), "forearm.R": (-12, 0, 0),
              "chest": (2, 0, -3), "spine": (0, 0, 2),
              "hips": {"rot": (0, 0, 5), "loc": (0, -0.018, 0)}}),
        # 过渡（下压）
        (9,  {"thigh.L": (8, 0, 0), "shin.L": (-12, 0, 0), "foot.L": (4, 0, 0),
              "thigh.R": (-6, 0, 0), "shin.R": (-34, 0, 0), "foot.R": (10, 0, 0),
              "upper_arm.L": (-6, 0, -3), "upper_arm.R": (6, 0, 3),
              "forearm.L": (-14, 0, 0), "forearm.R": (-14, 0, 0),
              "chest": (1, 0, -1), "spine": (0, 0, 1),
              "hips": {"rot": (0, 0, 2), "loc": (0, -0.030, 0)}}),
        # 右脚前
        (17, {"thigh.R": (A, 0, 0), "shin.R": (-6, 0, 0), "foot.R": (6, 0, 0),
              "thigh.L": (-A * 0.85, 0, 0), "shin.L": (B * 0.55, 0, 0), "foot.L": (18, 0, 0),
              "upper_arm.R": (-A * 0.7, 0, 3), "upper_arm.L": (A * 0.7, 0, -3),
              "forearm.R": (-16, 0, 0), "forearm.L": (-12, 0, 0),
              "chest": (2, 0, 3), "spine": (0, 0, -2),
              "hips": {"rot": (0, 0, -5), "loc": (0, -0.018, 0)}}),
        (25, {"thigh.R": (8, 0, 0), "shin.R": (-12, 0, 0), "foot.R": (4, 0, 0),
              "thigh.L": (-6, 0, 0), "shin.L": (-34, 0, 0), "foot.L": (10, 0, 0),
              "upper_arm.R": (-6, 0, 3), "upper_arm.L": (6, 0, -3),
              "forearm.R": (-14, 0, 0), "forearm.L": (-14, 0, 0),
              "chest": (1, 0, 1), "spine": (0, 0, -1),
              "hips": {"rot": (0, 0, -2), "loc": (0, -0.030, 0)}}),
        (33, {"thigh.L": (A, 0, 0), "shin.L": (-6, 0, 0), "foot.L": (6, 0, 0),
              "thigh.R": (-A * 0.85, 0, 0), "shin.R": (B * 0.55, 0, 0), "foot.R": (18, 0, 0),
              "upper_arm.L": (-A * 0.7, 0, -3), "upper_arm.R": (A * 0.7, 0, 3),
              "forearm.L": (-16, 0, 0), "forearm.R": (-12, 0, 0),
              "chest": (2, 0, -3), "spine": (0, 0, 2),
              "hips": {"rot": (0, 0, 5), "loc": (0, -0.018, 0)}}),
    ]
    for f, poses in frames:
        bpy.context.scene.frame_set(f)
        clear_pose(arm)
        set_pose(arm, f, poses)
        key_all(arm, f)
    return finalize_action(arm, "walk")


def anim_turn(arm):
    """转身：重心转移 + 上身先转（配合代码旋转，避免整体打转）。"""
    new_action(arm, "turn")
    frames = [
        (1,  {"hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)}, "chest": (0, 0, 0),
              "head": (0, 0, 0), "thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0)}),
        (8,  {"hips": {"rot": (0, 0, -6), "loc": (0, -0.020, 0)}, "chest": (0, 0, -14),
              "head": (0, 0, -20), "thigh.L": (0, 0, -4), "thigh.R": (4, 0, -6),
              "shin.R": (-12, 0, 0)}),
        (18, {"hips": {"rot": (0, 0, 8), "loc": (0, -0.010, 0)}, "chest": (0, 0, 16),
              "head": (0, 0, 22), "thigh.L": (6, 0, 5), "thigh.R": (-2, 0, 8),
              "shin.L": (-10, 0, 0)}),
        (26, {"hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)}, "chest": (0, 0, 0),
              "head": (0, 0, 0), "thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0)}),
    ]
    for f, poses in frames:
        bpy.context.scene.frame_set(f)
        clear_pose(arm)
        set_pose(arm, f, poses)
        key_all(arm, f)
    return finalize_action(arm, "turn")


def anim_talk(arm):
    """交谈：手臂小幅手势 + 头部点头/侧倾，90 帧循环。"""
    new_action(arm, "talk")
    base = {
        "upper_arm.L": (0, 0, -4), "upper_arm.R": (0, 0, 4),
        "forearm.L": (-14, 0, 0), "forearm.R": (-14, 0, 0),
    }
    frames = [
        (1,  dict(base, head=(0, 0, 0), chest=(0, 0, 0))),
        (20, {"upper_arm.L": (-12, 0, -8), "upper_arm.R": (-4, 0, 4),
              "forearm.L": (-42, 0, 0), "forearm.R": (-18, 0, 0),
              "hand.L": (-10, 0, 0), "head": (3, -4, 0), "chest": (-1, 0, -2)}),
        (45, {"upper_arm.L": (-3, 0, -5), "upper_arm.R": (-14, 0, 9),
              "forearm.L": (-16, 0, 0), "forearm.R": (-46, 0, 0),
              "hand.R": (-8, 0, 0), "head": (-2, 5, 0), "chest": (1, 0, 2)}),
        (68, {"upper_arm.L": (-8, 0, -7), "upper_arm.R": (-8, 0, 7),
              "forearm.L": (-30, 0, 0), "forearm.R": (-30, 0, 0),
              "head": (4, 0, 0), "chest": (-1, 0, 0)}),
        (90, dict(base, head=(0, 0, 0), chest=(0, 0, 0))),
    ]
    for f, poses in frames:
        bpy.context.scene.frame_set(f)
        clear_pose(arm)
        set_pose(arm, f, poses)
        key_all(arm, f)
    return finalize_action(arm, "talk")


def anim_sit(arm, reverse=False):
    """坐下 / 起身（30 帧过渡）。"""
    name = "stand_up" if reverse else "sit"
    new_action(arm, name)
    stand = {
        "hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)},
        "thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0),
        "shin.L": (0, 0, 0), "shin.R": (0, 0, 0),
        "foot.L": (0, 0, 0), "foot.R": (0, 0, 0),
        "spine": (0, 0, 0), "chest": (0, 0, 0), "head": (0, 0, 0),
        "upper_arm.L": (0, 0, -3), "upper_arm.R": (0, 0, 3),
        "forearm.L": (0, 0, 0), "forearm.R": (0, 0, 0),
    }
    # 髋部下降 0.42m（骨骼局部 Y 轴沿骨向上，故 -Y 为下降），大腿抬 82°，小腿回收
    sit = {
        "hips": {"rot": (-6, 0, 0), "loc": (0, -0.420, 0.020)},
        "thigh.L": (82, 0, 4), "thigh.R": (82, 0, -4),
        "shin.L": (-80, 0, 0), "shin.R": (-80, 0, 0),
        "foot.L": (6, 0, 0), "foot.R": (6, 0, 0),
        "spine": (4, 0, 0), "chest": (2, 0, 0), "head": (-4, 0, 0),
        "upper_arm.L": (-18, 0, -6), "upper_arm.R": (-18, 0, 6),
        "forearm.L": (-30, 0, 0), "forearm.R": (-30, 0, 0),
    }
    seq = [(1, sit), (31, stand)] if reverse else [(1, stand), (31, sit)]
    for f, poses in seq:
        bpy.context.scene.frame_set(f)
        clear_pose(arm)
        set_pose(arm, f, poses)
        key_all(arm, f)
    return finalize_action(arm, name)


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------
def probe(arm):
    """数值自检：验证骨骼旋转轴方向是否符合预期。"""
    import mathutils
    bpy.context.scene.frame_set(1)
    clear_pose(arm)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()

    def world_tail(bname):
        pb = arm.pose.bones.get(bname)
        if pb is None:
            return None
        return arm.matrix_world @ pb.tail

    print("[PROBE] rest foot.L tail:", world_tail("foot.L"))
    set_pose(arm, 1, {"thigh.L": (40, 0, 0)})
    bpy.context.view_layer.update()
    print("[PROBE] thigh.L +40deg -> foot.L tail:", world_tail("foot.L"))
    clear_pose(arm)
    set_pose(arm, 1, {"shin.L": (-40, 0, 0)})
    bpy.context.view_layer.update()
    print("[PROBE] shin.L -40deg -> foot.L tail:", world_tail("foot.L"))
    clear_pose(arm)
    set_pose(arm, 1, {"upper_arm.L": (-40, 0, 0)})
    bpy.context.view_layer.update()
    print("[PROBE] upper_arm.L -40deg -> hand.L tail:", world_tail("hand.L"))
    clear_pose(arm)
    bpy.context.view_layer.update()


def export_glb(path):
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    kwargs = dict(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_skins=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_morph=False,
        export_def_bones=False,
        export_optimize_animation_size=False,
        export_bake_animation=False,
    )
    kwargs = {k: v for k, v in kwargs.items() if k in props or k == "filepath"}
    bpy.ops.export_scene.gltf(**kwargs)


def setup_preview_scene():
    """搭一套简易三点布光 + 相机，用于渲染外观检查图。"""
    scene = bpy.context.scene

    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.045, 0.050, 0.062, 1.0)
        bg.inputs[1].default_value = 1.0

    target = bpy.data.objects.new("CamTarget", None)
    target.location = (0, 0, 0.92)
    scene.collection.objects.link(target)

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 62
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.95, 3.05, 1.46)
    con = cam.constraints.new('TRACK_TO')
    con.target = target
    con.track_axis = 'TRACK_NEGATIVE_Z'
    con.up_axis = 'UP_Y'
    scene.camera = cam

    def add_area(name, loc, energy, size, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, 'AREA')
        ld.energy = energy
        ld.size = size
        ld.color = color
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        c = lo.constraints.new('TRACK_TO')
        c.target = target
        c.track_axis = 'TRACK_NEGATIVE_Z'
        c.up_axis = 'UP_Y'
        return lo

    add_area("Key", (1.5, 2.0, 2.4), 260.0, 1.5, (1.0, 0.95, 0.88))
    add_area("Fill", (-2.2, 1.6, 1.4), 90.0, 2.2, (0.82, 0.88, 1.0))
    add_area("Rim", (-0.8, -2.0, 2.1), 200.0, 1.4, (0.86, 0.91, 1.0))

    # 地面（接收阴影，便于看脚部是否贴地）
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "PreviewFloor"
    fm = make_material("preview_floor", (0.10, 0.10, 0.11), 0.9)
    floor.data.materials.append(fm)

    scene.render.resolution_x = 720
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH'):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    scene.render.film_transparent = False
    return cam


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path))


def render_preview(path, frame=1):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.frame_set(frame)
    bpy.context.scene.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)


def build_character(cid, cfg, out_dir, do_probe=False,
                    blend_dir=None, render_dir=None,
                    render_frames=((None, 1, "rest"), ("walk", 9, "walk"), ("talk", 20, "talk"))):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30

    scale = cfg["height"] / NOMINAL_HEIGHT

    mb, mat_index = build_body(cfg)
    # 材质已在此前创建（build_body 内部调用 build_materials），重新取用
    materials = [bpy.data.materials[k] for k in MAT_ORDER]

    # 先按名义尺寸建模，再统一缩放到目标身高
    for i, co in enumerate(mb.verts):
        mb.verts[i] = (co[0] * scale, co[1] * scale, co[2] * scale)

    obj = create_mesh_object("Body", mb, materials, mat_index)

    arm = create_armature("Rig", scale)

    # 权重：先于细分应用（顶点数仍一致）
    assign_weights(obj, arm, mb)

    # 父级到骨架（保持变换）
    obj.parent = arm
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    # 骨架修改器要排在细分之前
    while obj.modifiers.find("Armature") > 0:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_move_up(modifier="Armature")

    # 动画
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    anim_idle(arm)
    anim_walk(arm)
    anim_turn(arm)
    anim_talk(arm)
    anim_sit(arm, reverse=False)
    anim_sit(arm, reverse=True)
    bpy.ops.object.mode_set(mode='OBJECT')

    if do_probe:
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode='POSE')
        probe(arm)
        bpy.ops.object.mode_set(mode='OBJECT')

    scene.frame_set(1)

    # 选中骨架+网格导出
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm

    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "%s.glb" % cid)
    export_glb(out_path)

    acts = [a.name for a in bpy.data.actions]
    stats = {
        "id": cid,
        "file": out_path,
        "verts": len(obj.data.vertices),
        "polys": len(obj.data.polygons),
        "bones": len([b for b in arm.data.bones if b.use_deform]),
        "actions": acts,
        "height_m": round(cfg["height"], 3),
    }

    # 保存可编辑源工程（任务书要求保留 Blender 源文件）
    if blend_dir:
        save_blend(os.path.join(blend_dir, "%s.blend" % cid))
        stats["blend"] = os.path.join(blend_dir, "%s.blend" % cid)

    # 渲染外观检查图
    if render_dir:
        setup_preview_scene()
        frames = render_frames or [(None, 1, "rest")]
        for act_name, fr, tag in frames:
            if act_name:
                act = bpy.data.actions.get(act_name)
                if act is not None:
                    arm.animation_data.action = act
            else:
                arm.animation_data.action = None
            render_preview(os.path.join(render_dir, "%s_%s.png" % (cid, tag)), fr)
        arm.animation_data.action = None
        stats["renders"] = [os.path.join(render_dir, "%s_%s.png" % (cid, tag))
                            for _, _, tag in frames]

    return stats


def main():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    out_dir = "assets/models/characters"
    blend_dir = None
    render_dir = None
    only = None
    do_probe = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out" and i + 1 < len(argv):
            out_dir = argv[i + 1]
            i += 2
        elif a == "--blend-dir" and i + 1 < len(argv):
            blend_dir = argv[i + 1]
            i += 2
        elif a == "--render-dir" and i + 1 < len(argv):
            render_dir = argv[i + 1]
            i += 2
        elif a == "--only" and i + 1 < len(argv):
            only = argv[i + 1]
            i += 2
        elif a == "--probe":
            do_probe = True
            i += 1
        else:
            i += 1

    targets = [only] if only else list(CHARACTERS.keys())
    results = []
    for cid in targets:
        if cid not in CHARACTERS:
            print("[ERR] 未知角色 %s" % cid)
            continue
        print("[BUILD] %s ..." % cid)
        st = build_character(cid, CHARACTERS[cid], out_dir, do_probe,
                             blend_dir=blend_dir, render_dir=render_dir)
        results.append(st)
        print("[OK] %s verts=%d polys=%d bones=%d actions=%s"
              % (cid, st["verts"], st["polys"], st["bones"], ",".join(st["actions"])))

    print("[SUMMARY] " + json.dumps(results, ensure_ascii=False))


if __name__ == "__main__":
    main()
