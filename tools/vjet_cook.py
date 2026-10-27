#!/usr/bin/env python3
"""Cook one list blob from STL or OBJ.

The payload matches VJET_v01_displaylist.spin. Python 3 and the
standard library are enough on macOS, Linux, and Windows.

The view is orthographic. Model Y points up. Screen Y points down.
Z orders the faces. Low Z is drawn first. The cooker does not weld
vertices and does not split a face.

A list blob is a 6-byte header, the payload, then reloc words.
Each reloc word is a byte offset into the payload. The sender adds
the destination Hub address. The last link stays 0.
"""

import argparse
import math
import struct
import sys
from pathlib import Path


WIDTH = 256
HEIGHT = 240
MARGIN = 16
DLIST_MAX = 2000
POSX = 0x7FFFFFFF
NEGX = -2147483648


class CookError(Exception):
    pass


def coord(value):
    if isinstance(value, str):
        try:
            value = float(value)
        except ValueError:
            raise CookError("coordinate is not a number")
    if not math.isfinite(value):
        raise CookError("coordinate is not finite")
    return value


def s32(v):
    v &= 0xFFFFFFFF
    if v >= 0x80000000:
        v -= 0x100000000
    return v


def sadd(a, b):
    return s32(s32(a) + s32(b))


def ssub(a, b):
    return s32(s32(a) - s32(b))


def sdiv(a, b):
    a = s32(a)
    b = s32(b)
    if b == 0:
        raise CookError("slope divide by zero")
    neg = (a < 0) ^ (b < 0)
    q = abs(a) // abs(b)
    return -q if neg else q


def pix(v):
    return s32(v) >> 16


def u16(v):
    return s32(v) & 0xFFFF


def slope_calc(x1, x2, y1, y2):
    return sdiv(ssub(x1, x2), pix(y1) - pix(y2) + 1)


def slope_calc2(x1, x2, y1, y2):
    return sdiv(ssub(x1, x2), s32(y1) - s32(y2) + 1)


def spin_ne(a, b):
    return -1 if s32(a) != s32(b) else 0


class List(object):
    """Display-list bytes. The arithmetic matches the Spin builder."""

    def __init__(self):
        self.buf = bytearray()
        self.relocs = []
        self.link = 0x8080
        self.topclip = 0
        self.bottomclip = HEIGHT << 16
        self.leftclip = 0
        self.rightclip = WIDTH << 16
        self.triangles = 0
        self.lines = 0
        self.faces = 0
        self.skipped = 0

    def putbyte(self, x):
        self.buf.append(x & 0xFF)

    def putword(self, x):
        self.buf += struct.pack("<H", u16(x))

    def putlong(self, x):
        self.buf += struct.pack("<i", s32(x))

    def skip(self, n):
        self.buf += b"\x00" * n

    def putlink(self):
        at = len(self.buf)
        self.putword(0)
        if self.link != 0x8080:
            struct.pack_into("<H", self.buf, self.link, at & 0xFFFF)
            self.relocs.append(self.link)
        self.link = at

    def add_long(self, off, delta):
        cur = struct.unpack_from("<i", self.buf, off)[0]
        struct.pack_into("<i", self.buf, off, s32(cur + s32(delta)))

    def line(self, x1, y1, x2, y2, colors):
        x1, y1, x2, y2 = s32(x1), s32(y1), s32(x2), s32(y2)
        if y1 > y2:
            y1, y2 = y2, y1
            x1, x2 = x2, x1
        if y2 < self.topclip or y1 >= self.bottomclip:
            self.skipped += 1
            return
        self.putlink()
        self.putbyte(0xFF)
        type_at = len(self.buf)
        self.putbyte(0)
        self.putword(pix(y1))
        self.putword(pix(y2) + 1)
        if u16(pix(y2)) == u16(pix(y1)):
            self.buf[type_at] = 2
            if x1 < x2:
                self.putword(pix(x1))
                self.putword(pix(x2))
            else:
                self.putword(pix(x2))
                self.putword(pix(x1))
            self.putword(colors)
            self.skip(2)
        else:
            self.buf[type_at] = 1
            self.skip(8)
            tmp = slope_calc(x2, x1, y2, y1)
            if x1 <= x2:
                self.putlong(x1)
                self.putlong(sadd(sadd(x1, tmp), 0x10000))
            else:
                self.putlong(sadd(sadd(x1, tmp), -0x10000))
                self.putlong(x1)
            self.putword(u16(pix(y2)) - u16(pix(y1)) + 1)
            self.putword(colors)
            self.putlong(tmp)
            self.putlong(tmp)
        self.lines += 1

    def triangle(self, x1, y1, x2, y2, x3, y3, colors):
        x1, y1 = s32(x1), s32(y1)
        x2, y2 = s32(x2), s32(y2)
        x3, y3 = s32(x3), s32(y3)
        if y1 > y2:
            y1, y2 = y2, y1
            x1, x2 = x2, x1
        if y1 > y3:
            y1, y3 = y3, y1
            x1, x3 = x3, x1
        if y2 > y3:
            y2, y3 = y3, y2
            x2, x3 = x3, x2
        if (y3 < self.topclip or y1 >= self.bottomclip
                or (u16(pix(y2)) == u16(pix(y1)) and u16(pix(y2)) == u16(pix(y3)))):
            self.skipped += 1
            return
        self.putlink()
        self.putbyte(0xFF)
        self.putbyte(1)
        self.putword(pix(y1))
        self.putword(pix(y3) + 1)
        self.skip(8)
        if u16(pix(y2)) == u16(pix(y3)):
            tmp = slope_calc(x3, x1, y3, y1)
            tmp2 = slope_calc(x2, x1, y2, y1)
            if x2 > x3:
                self.putlong(sadd(x1, min(tmp, 0)))
                self.putlong(sadd(x1, max(tmp2, 0)))
            else:
                self.putlong(sadd(x1, min(tmp2, 0)))
                self.putlong(sadd(x1, max(tmp, 0)))
            self.putword(u16(pix(y3)) - u16(pix(y1)) + 1)
            self.putword(colors)
            if x2 > x3:
                self.putlong(tmp)
                self.putlong(tmp2)
            else:
                self.putlong(tmp2)
                self.putlong(tmp)
        elif u16(pix(y1)) == u16(pix(y2)):
            tmp = slope_calc(x3, x2, y3, y2)
            tmp2 = slope_calc(x3, x1, y3, y1)
            if x1 > x2:
                self.putlong(sadd(x2, min(tmp, 0)))
                self.putlong(sadd(x1, max(tmp2, 0)))
            else:
                self.putlong(sadd(x1, min(tmp2, 0)))
                self.putlong(sadd(x2, max(tmp, 0)))
            self.putword(u16(pix(y3)) - u16(pix(y1)) + 1)
            self.putword(colors)
            if x1 > x2:
                self.putlong(tmp)
                self.putlong(tmp2)
            else:
                self.putlong(tmp2)
                self.putlong(tmp)
        else:
            tmp = slope_calc(x3, x1, y3, y1)
            tmp2 = slope_calc(x2, x1, y2, y1)
            if tmp2 > tmp:
                self.putlong(sadd(x1, min(tmp, 0)))
                self.putlong(sadd(x1, max(tmp2, 0)))
                self.putword(u16(pix(y2)) - u16(pix(y1)))
                self.putword(colors)
                self.putlong(tmp)
                self.putlong(tmp2)
            else:
                self.putlong(sadd(x1, min(tmp2, 0)))
                self.putlong(sadd(x1, max(tmp, 0)))
                self.putword(u16(pix(y2)) - u16(pix(y1)))
                self.putword(colors)
                self.putlong(tmp2)
                self.putlong(tmp)
            self.putword(u16(pix(y3)) - u16(pix(y2)) + 1)
            self.putword(colors)
            tmp3 = slope_calc(x3, x2, y3, y2)
            if tmp2 > tmp:
                self.putlong(tmp)
                self.putlong(tmp3)
            else:
                self.putlong(tmp3)
                self.putlong(tmp)
        self.triangles += 1

    def polygon(self, verts, colors):
        vcount = len(verts)
        if vcount < 3:
            self.skipped += 1
            return
        ytop = POSX
        ybottom = NEGX
        topi = 0
        topleftx = toprightx = 0
        for lefti in range(vcount):
            tmp = pix(verts[lefti][1])
            if tmp < ytop:
                ytop = tmp
                topi = lefti
                topleftx = toprightx = verts[lefti][0]
            elif tmp == ytop:
                tmp = verts[lefti][0]
                if tmp < topleftx:
                    topleftx = tmp
                if tmp > toprightx:
                    toprightx = tmp
        lefti = topi
        for _ in range(vcount):
            lefti += 1
            if lefti >= vcount:
                lefti -= vcount
            tmp = pix(verts[lefti][1])
            if tmp >= ybottom:
                ybottom = tmp
        if ytop >= pix(self.bottomclip) or ybottom < pix(self.topclip) or ytop == ybottom:
            self.skipped += 1
            return
        lefti = righti = topi
        lefti -= 1
        if lefti < 0:
            lefti += vcount
        righti += 1
        if righti >= vcount:
            righti -= vcount
        leftslope = slope_calc2(verts[lefti][0], verts[topi][0], pix(verts[lefti][1]), ytop)
        rightslope = slope_calc2(verts[righti][0], verts[topi][0], pix(verts[righti][1]), ytop)
        ccw = (s32(-1 if leftslope > rightslope else 0) << 1) + 1
        self.putlink()
        self.putbyte(0xFF)
        self.putbyte(1)
        self.putword(ytop)
        self.putword(ybottom + 1)
        self.skip(8)
        topptr = len(self.buf)
        self.putlong(topleftx)
        self.putlong(toprightx)

        def step(i, delta):
            i += delta
            if i < 0:
                i += vcount
            elif i >= vcount:
                i -= vcount
            return i

        lefti = topi
        guard = 0
        while True:
            lefti = step(lefti, -ccw)
            lefty = pix(verts[lefti][1])
            guard += 1
            if lefty != ytop or guard > vcount + 2:
                break
        righti = topi
        guard = 0
        while True:
            righti = step(righti, ccw)
            righty = pix(verts[righti][1])
            guard += 1
            if righty != ytop or guard > vcount + 2:
                break
        toplefty = toprighty = ytop
        bottom_scan = ytop
        leftslope = rightslope = NEGX
        for _ in range(vcount << 2):
            leftx = POSX
            rightx = NEGX
            if leftslope == NEGX:
                guard = 0
                while True:
                    if verts[lefti][0] < leftx:
                        leftx = verts[lefti][0]
                    lefty = pix(verts[lefti][1])
                    if lefty == ybottom:
                        break
                    tmpi = step(lefti, -ccw)
                    if pix(verts[tmpi][1]) != lefty:
                        break
                    lefti = tmpi
                    guard += 1
                    if guard > vcount + 2:
                        break
            if rightslope == NEGX:
                guard = 0
                while True:
                    if verts[righti][0] > rightx:
                        rightx = verts[righti][0]
                    righty = pix(verts[righti][1])
                    if righty == ybottom:
                        break
                    tmpi = step(righti, ccw)
                    if pix(verts[tmpi][1]) != righty:
                        break
                    righti = tmpi
                    guard += 1
                    if guard > vcount + 2:
                        break
            stepy = lefty if lefty < righty else righty
            if stepy == ybottom:
                tmp = stepy - bottom_scan + 1
            else:
                tmp = stepy - bottom_scan
            if tmp > 0:
                self.putword(tmp)
                self.putword(colors)
                if leftslope == NEGX:
                    adj = spin_ne(toplefty, ytop) & spin_ne(toplefty, ybottom)
                    leftslope = slope_calc2(leftx, topleftx, lefty + adj, toplefty)
                    topleftx = leftx
                    toplefty = lefty
                if rightslope == NEGX:
                    adj = spin_ne(toprighty, ytop) & spin_ne(toprighty, ybottom)
                    rightslope = slope_calc2(rightx, toprightx, righty + adj, toprighty)
                    toprightx = rightx
                    toprighty = righty
                self.putlong(leftslope)
                self.putlong(rightslope)
                if topptr:
                    self.add_long(topptr, min(leftslope, 0))
                    self.add_long(topptr + 4, max(rightslope, 0))
                    topptr = 0
                bottom_scan = stepy
            if stepy == ybottom:
                break
            if lefty == stepy:
                lefti = step(lefti, -ccw)
                leftslope = NEGX
            if righty == stepy:
                righti = step(righti, ccw)
                rightslope = NEGX
        self.faces += 1


def parse_colour(text):
    t = text.strip().lower()
    for prefix in ("0x", "$"):
        if t.startswith(prefix):
            t = t[len(prefix):]
    try:
        value = int(t, 16)
    except ValueError:
        raise CookError("colour %s is not hex" % text)
    if value < 0 or value > 0xFFFF:
        raise CookError("colour %s does not fit in one word" % text)
    return value


def _tri(a, b, c):
    return ("tri", (a, b, c), (a[2] + b[2] + c[2]) / 3.0)


def _line(a, b):
    return ("line", (a, b), (a[2] + b[2]) / 2.0)


def _face(pts):
    z = sum(p[2] for p in pts) / float(len(pts))
    return ("face", tuple(pts), z)


def parse_ascii_stl(data):
    text = data.decode("latin1")
    got = []
    tris = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[0].lower() == "vertex":
            got.append((coord(parts[1]), coord(parts[2]), coord(parts[3])))
            if len(got) == 3:
                tris.append(_tri(got[0], got[1], got[2]))
                got = []
    if got:
        raise CookError("STL facet has %d vertices" % len(got))
    if not tris:
        raise CookError("STL file has no facet")
    return tris


def parse_binary_stl(data):
    if len(data) < 84:
        raise CookError("binary STL is shorter than the header")
    try:
        count = struct.unpack_from("<I", data, 80)[0]
    except struct.error:
        raise CookError("binary STL count does not match the file")
    need = 84 + count * 50
    if count < 1 or len(data) < need:
        raise CookError("binary STL count does not match the file")
    tris = []
    off = 84
    try:
        for _ in range(count):
            xs = struct.unpack_from("<9f", data, off + 12)
            a = (coord(xs[0]), coord(xs[1]), coord(xs[2]))
            b = (coord(xs[3]), coord(xs[4]), coord(xs[5]))
            c = (coord(xs[6]), coord(xs[7]), coord(xs[8]))
            tris.append(_tri(a, b, c))
            off += 50
    except struct.error:
        raise CookError("binary STL count does not match the file")
    return tris


def _exact_binary_stl(data):
    if len(data) < 84:
        return False
    count = struct.unpack_from("<I", data, 80)[0]
    if count < 1:
        return False
    return len(data) == 84 + count * 50


def parse_stl(data):
    # A binary file may start with the bytes "solid". An exact record
    # length is binary. ASCII is the fallback when the length does not match.
    if _exact_binary_stl(data):
        return parse_binary_stl(data)
    head = data.lstrip()[:5].lower()
    if head == b"solid" and b"facet" in data.lower():
        return parse_ascii_stl(data)
    return parse_binary_stl(data)


def _obj_index(token, nverts):
    raw = token.split("/")[0]
    if raw == "":
        raise CookError("OBJ index is empty")
    try:
        i = int(raw, 10)
    except ValueError:
        raise CookError("OBJ index is not a number")
    if i < 0:
        i = nverts + i
    else:
        i -= 1
    if i < 0 or i >= nverts:
        raise CookError("OBJ index is outside the vertex list")
    return i


def _cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _quad_ok(pts):
    signs = []
    n = len(pts)
    for i in range(n):
        z = _cross(pts[i], pts[(i + 1) % n], pts[(i + 2) % n])
        if z == 0:
            raise CookError("OBJ face is degenerate")
        signs.append(z > 0)
    if any(signs) and not all(signs):
        raise CookError("OBJ face is concave")


def parse_obj(data):
    verts = []
    prims = []
    for line in data.decode("latin1").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if not parts:
            continue
        kind = parts[0]
        if kind == "v" and len(parts) >= 3:
            z = coord(parts[3]) if len(parts) >= 4 else 0.0
            verts.append((coord(parts[1]), coord(parts[2]), z))
        elif kind == "l":
            if len(parts) < 3:
                raise CookError("OBJ line needs two vertices")
            idx = [_obj_index(tok, len(verts)) for tok in parts[1:]]
            for a, b in zip(idx, idx[1:]):
                prims.append(_line(verts[a], verts[b]))
        elif kind == "f":
            if len(parts) not in (4, 5):
                raise CookError("OBJ face has %d vertices" % (len(parts) - 1))
            idx = [_obj_index(tok, len(verts)) for tok in parts[1:]]
            pts = [verts[i] for i in idx]
            if len(pts) == 4:
                _quad_ok(pts)
                prims.append(_face(pts))
            else:
                prims.append(_tri(pts[0], pts[1], pts[2]))
        elif kind in ("vn", "vt", "vp", "o", "g", "s", "usemtl", "mtllib", "usemap"):
            continue
    if not prims:
        raise CookError("OBJ file has no line or face")
    return prims


def fit_points(prims):
    xs = [p[0] for _k, pts, _z in prims for p in pts]
    ys = [p[1] for _k, pts, _z in prims for p in pts]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    width = maxx - minx
    height = maxy - miny
    span_x = WIDTH - 2 * MARGIN
    span_y = HEIGHT - 2 * MARGIN
    if width == 0 and height == 0:
        raise CookError("the model has no extent")
    if width == 0:
        scale = span_y / height
    elif height == 0:
        scale = span_x / width
    else:
        scale = min(span_x / width, span_y / height)
    used_w = width * scale
    used_h = height * scale
    ox = MARGIN + (span_x - used_w) / 2.0
    oy = MARGIN + (span_y - used_h) / 2.0

    def one(p):
        px = ox + (p[0] - minx) * scale
        py = oy + (maxy - p[1]) * scale
        try:
            sx = int(round(px))
            sy = int(round(py))
        except (ValueError, OverflowError):
            raise CookError("screen coordinate does not fit")
        if sx < -32768 or sx > 32767 or sy < -32768 or sy > 32767:
            raise CookError("screen coordinate does not fit")
        return sx << 16, sy << 16

    return one


def build(prims, colour):
    order = sorted(prims, key=lambda item: item[2])
    mapper = fit_points(order)
    gl = List()
    for kind, pts, _z in order:
        scr = [mapper(p) for p in pts]
        if kind == "line":
            gl.line(scr[0][0], scr[0][1], scr[1][0], scr[1][1], colour)
        elif kind == "tri":
            gl.triangle(scr[0][0], scr[0][1], scr[1][0], scr[1][1],
                        scr[2][0], scr[2][1], colour)
        else:
            gl.polygon(scr, colour)
    if gl.triangles + gl.lines + gl.faces == 0:
        raise CookError("the fit produced no shape")
    if len(gl.buf) > DLIST_MAX:
        raise CookError("the list is %d bytes. The limit is %d" % (len(gl.buf), DLIST_MAX))
    check_chain(gl.buf, gl.relocs)
    return gl


def pack_blob(gl):
    payload = bytes(gl.buf)
    header = struct.pack("<HHH", len(payload), len(gl.relocs), 0)
    rel = b"".join(struct.pack("<H", off) for off in gl.relocs)
    return header + payload + rel


def write_asm(path, blob, source_name):
    payload_len, reloc_n, font = struct.unpack_from("<HHH", blob, 0)
    lines = [
        "; list blob from %s" % source_name,
        "; payload %d, relocs %d, font %d" % (payload_len, reloc_n, font),
        "SECTION rodata_user",
        "PUBLIC _vjet_blob",
        "_vjet_blob:",
        "    DEFW %d" % payload_len,
        "    DEFW %d" % reloc_n,
        "    DEFW %d" % font,
    ]
    body = blob[6:]
    row = []
    for i, b in enumerate(body):
        row.append("$%02X" % b)
        if len(row) == 12 or i == len(body) - 1:
            lines.append("    DEFB " + ",".join(row))
            row = []
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_inc(path, blob_name):
    text = "\n".join([
        "; binary include of %s" % blob_name,
        "SECTION rodata_user",
        "PUBLIC _vjet_blob",
        "_vjet_blob:",
        '    binary "%s"' % blob_name,
        "",
    ])
    path.write_text(text, encoding="ascii")


def report(name, gl, blob, font_note):
    print("%s: triangles %d, lines %d, faces %d, skipped %d, payload %d, relocs %d, blob %d" % (
        name, gl.triangles, gl.lines, gl.faces, gl.skipped,
        len(gl.buf), len(gl.relocs), len(blob)))
    if font_note is not None:
        print("font %d is unused. The blob stores 0." % font_note)


def cook_path(path, colour):
    data = path.read_bytes()
    suffix = path.suffix.lower()
    if suffix == ".stl":
        prims = parse_stl(data)
    elif suffix == ".obj":
        prims = parse_obj(data)
    else:
        raise CookError("file %s is not STL or OBJ" % path.name)
    gl = build(prims, colour)
    return gl, pack_blob(gl)


def examples_dir():
    return Path(__file__).resolve().parent / "vjet"


def check_chain(buf, relocs):
    found = walk_shapes(buf)
    slots = []
    positions = []
    for pos, _typ in found:
        positions.append(pos)
        link = struct.unpack_from("<H", buf, pos)[0]
        if link != 0:
            slots.append(pos)
    if slots != list(relocs):
        raise CookError("reloc list does not match the links")
    show_accepts(buf)
    for i, pos in enumerate(positions):
        link = struct.unpack_from("<H", buf, pos)[0]
        if i + 1 < len(positions):
            if link != positions[i + 1]:
                raise CookError("list link skipped a shape")
        elif link != 0:
            raise CookError("list link skipped a shape")


def _traps_cover(payload, pos, span, cover):
    q = 24
    got = 0
    while got < cover:
        if q + 12 > span:
            return False
        height = struct.unpack_from("<H", payload, pos + q)[0]
        if height == 0:
            return False
        got += height
        q += 12
    return True


def show_accepts(payload):
    """Same rules as listChainOk. Offsets here, Hub addresses on the Propeller."""

    pos = 0
    n = 0
    lim = len(payload)
    while True:
        if pos + 7 >= lim:
            raise CookError("list header does not fit")
        if payload[pos + 2] != 0xFF:
            raise CookError("list sync is not FF")
        kind = payload[pos + 3]
        if kind < 1 or kind > 3:
            raise CookError("list type is not 1, 2, or 3")
        y0, y1 = struct.unpack_from("<HH", payload, pos + 4)
        if y0 > 240 or y1 > 240 or y1 < y0:
            raise CookError("list scanlines are outside 0..240")
        nxt = struct.unpack_from("<H", payload, pos)[0]
        if nxt == 0:
            span = lim - pos
        elif (nxt & 1) or nxt <= pos or (nxt + 7) >= lim:
            raise CookError("list link left the payload")
        else:
            span = nxt - pos
        if kind == 1:
            if span < 36 or not _traps_cover(payload, pos, span, y1 - y0):
                raise CookError("list trap does not cover its scanlines")
        elif kind == 2:
            if span < 16:
                raise CookError("list box is short")
        elif span < 20:
            raise CookError("list text is short")
        if nxt == 0:
            return
        pos = nxt
        n += 1
        if n == 250:
            raise CookError("list has too many shapes")


def walk_shapes(payload):
    pos = 0
    found = []
    seen = set()
    while True:
        if pos in seen or pos + 4 > len(payload):
            raise CookError("list link left the payload")
        seen.add(pos)
        link = struct.unpack_from("<H", payload, pos)[0]
        found.append((pos, payload[pos + 3]))
        if link == 0:
            break
        pos = link
    return found


def run_check():
    colour = parse_colour("FFFF")
    root = examples_dir()
    tri_stl, blob_stl = cook_path(root / "triangle.stl", colour)
    tri_obj, blob_obj = cook_path(root / "triangle.obj", colour)
    if blob_stl != blob_obj:
        raise CookError("STL and OBJ triangles differ")
    if tri_stl.triangles != 1 or tri_stl.relocs or len(tri_stl.buf) != 36:
        raise CookError("triangle payload is not one 36-byte shape")
    if tri_stl.buf[2] != 0xFF or tri_stl.buf[3] != 1:
        raise CookError("triangle header is not a trap")
    start, end = struct.unpack_from("<HH", tri_stl.buf, 4)
    if start != 16 or end != 225:
        raise CookError("triangle scanlines are %d..%d" % (start, end))

    ascii_tris = parse_ascii_stl((root / "triangle.stl").read_bytes())
    binary = bytearray(80) + struct.pack("<I", 1)
    for prim in ascii_tris:
        binary += struct.pack("<3f", 0.0, 0.0, 1.0)
        for p in prim[1]:
            binary += struct.pack("<3f", p[0], p[1], p[2])
        binary += struct.pack("<H", 0)
    if parse_binary_stl(bytes(binary)) != ascii_tris:
        raise CookError("binary STL does not match the ASCII facet")
    gl_bin = build(parse_binary_stl(bytes(binary)), colour)
    if bytes(gl_bin.buf) != bytes(tri_stl.buf):
        raise CookError("binary STL list does not match the ASCII list")

    _sq, sq_blob = cook_path(root / "square.obj", colour)
    sq = sq_blob[6:6 + struct.unpack_from("<H", sq_blob, 0)[0]]
    shapes = walk_shapes(sq)
    if [typ for _p, typ in shapes] != [2, 1, 2, 1]:
        raise CookError("square line types are %s" % [typ for _p, typ in shapes])
    if struct.unpack_from("<H", sq_blob, 2)[0] != 3:
        raise CookError("square reloc count is wrong")

    quad, quad_blob = cook_path(root / "quad.stl", colour)
    if quad.triangles != 2 or quad.relocs != [0]:
        raise CookError("quad did not store two triangles")
    link = struct.unpack_from("<H", quad.buf, 0)[0]
    if link == 0 or walk_shapes(quad.buf)[1][0] != link:
        raise CookError("quad link does not name the second shape")

    face, _fb = cook_path(root / "quad.obj", colour)
    if face.faces != 1 or face.triangles != 0 or len(face.buf) != 36:
        raise CookError("convex quad was not one face")
    start, end = struct.unpack_from("<HH", face.buf, 4)
    if start != 16 or end != 225:
        raise CookError("quad face scanlines are %d..%d" % (start, end))

    bad = b"v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0.2 0.2 0\nf 1 2 3 4\n"
    try:
        parse_obj(bad)
    except CookError:
        pass
    else:
        raise CookError("concave quad was accepted")

    try:
        parse_obj(b"v nan 0 0\nv 1 0 0\nl 1 2\n")
    except CookError:
        pass
    else:
        raise CookError("a non-finite coordinate was accepted")

    try:
        parse_obj(b"v 0 0 0\nv 1 0 0\nl 1 x\n")
    except CookError:
        pass
    else:
        raise CookError("a bad OBJ index was accepted")

    try:
        build(parse_obj(b"v -1e308 0 0\nv 1e308 0 0\nl 1 2\n"), colour)
    except CookError:
        pass
    else:
        raise CookError("an out of range coordinate was accepted")

    cycle = bytearray(16)
    struct.pack_into("<H", cycle, 0, 8)
    struct.pack_into("<H", cycle, 8, 8)
    try:
        walk_shapes(cycle)
    except CookError:
        pass
    else:
        raise CookError("a cyclic link was accepted")

    straight = bytearray(16)
    struct.pack_into("<H", straight, 0, 8)
    try:
        check_chain(straight, [])
    except CookError:
        pass
    else:
        raise CookError("a missing reloc was accepted")

    one = List()
    one.line(0, 0, 10 << 16, 1 << 16, colour)
    if one.lines != 1 or len(one.buf) != 36:
        raise CookError("a one pixel line was not one trap")
    check_chain(one.buf, one.relocs)

    solid = bytearray(b"solid") + bytearray(75) + binary[80:]
    if parse_stl(bytes(solid)) != ascii_tris:
        raise CookError("a binary STL with a solid header was read as ASCII")

    print("check ok")
    report("triangle.stl", tri_stl, blob_stl, None)
    report("square.obj", _sq, sq_blob, None)
    report("quad.stl", quad, quad_blob, None)
    report("quad.obj", face, _fb, None)


def main(argv):
    parser = argparse.ArgumentParser(description="Cook a VECTORJET list blob from STL or OBJ.")
    parser.add_argument("--stl", type=Path, help="ASCII or binary STL")
    parser.add_argument("--obj", type=Path, help="OBJ lines or faces")
    parser.add_argument("--colour", "--color", dest="colour", help="one colour word, hex")
    parser.add_argument("--font", type=int, default=None, help="accepted and unused until the list has text")
    parser.add_argument("--out", type=Path, help="write the .vjb list blob")
    parser.add_argument("--asm", type=Path, help="write DEFB and DEFW for the blob")
    parser.add_argument("--inc", type=Path, help="write a binary include of --out")
    parser.add_argument("--check", action="store_true", help="cook the sample files and check the bytes")
    args = parser.parse_args(argv)

    if args.check:
        try:
            run_check()
        except CookError as exc:
            print("vjet_cook: %s" % exc, file=sys.stderr)
            return 1
        return 0

    if (args.stl is None) == (args.obj is None):
        print("vjet_cook: pass one of --stl or --obj", file=sys.stderr)
        return 1
    if args.colour is None:
        print("vjet_cook: pass --colour", file=sys.stderr)
        return 1
    if args.out is None and args.asm is None:
        print("vjet_cook: pass --out or --asm", file=sys.stderr)
        return 1
    if args.inc is not None and args.out is None:
        print("vjet_cook: --inc needs --out", file=sys.stderr)
        return 1

    src = args.stl if args.stl is not None else args.obj
    try:
        colour = parse_colour(args.colour)
        gl, blob = cook_path(src, colour)
    except CookError as exc:
        print("vjet_cook: %s" % exc, file=sys.stderr)
        return 1
    except OSError as exc:
        print("vjet_cook: %s" % exc, file=sys.stderr)
        return 1

    try:
        if args.out is not None:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_bytes(blob)
        if args.asm is not None:
            args.asm.parent.mkdir(parents=True, exist_ok=True)
            write_asm(args.asm, blob, src.name)
        if args.inc is not None:
            args.inc.parent.mkdir(parents=True, exist_ok=True)
            write_inc(args.inc, args.out.name)
    except OSError as exc:
        print("vjet_cook: %s" % exc, file=sys.stderr)
        return 1
    report(src.name, gl, blob, args.font)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
