#!/usr/bin/env python3
# Generate a stand-in for the "Nintendo extension" shared font (nintendo_ext.ttf): controller-button icons at the original private-use code points (A/B/X/Y, L/R/ZL/ZR/SL/SR, +/−, D-pad, stick direction arrows).
# The host has no original system fonts; button icons in game text (e.g. Mario's GameMsg/Key.msbt: U+E0E0 = A button) render as "?" when the glyph is missing. Letters come from macOS's Arial Rounded Bold, knocked out of a solid plate.
# Usage: make_ext_font.py out.ttf [letter-font.ttf]; needs fontTools (pip install fonttools)
import math, os, struct, sys
from fontTools.ttLib import TTFont
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.reverseContourPen import ReverseContourPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen

EM, ASC, DESC = 1000, 700, -300
CY, R = 300, 270          # icon centre height and circle radius: sits cleanly on text baseline

def area(c): return sum(c[i][0] * c[i - 1][1] - c[i - 1][0] * c[i][1] for i in range(len(c))) / 2
def contour(pen, pts, hole=False):
    # solid clockwise, hole counter-clockwise (TrueType convention, nonzero winding)
    if (area(pts) > 0) != hole: pts = pts[::-1]
    k = next(i for i, p in enumerate(pts) if p[2]); pts = pts[k:] + pts[:k]
    pen.moveTo(pts[0][:2]); offs = []
    for x, y, on in pts[1:]:
        if not on: offs.append((x, y)); continue
        if offs: pen.qCurveTo(*offs, (x, y)); offs = []
        else: pen.lineTo((x, y))
    if offs: pen.qCurveTo(*offs, pts[0][:2])
    pen.closePath()
def circle(cx, cy, r, n=8):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n; b = a + math.pi / n; rr = r / math.cos(math.pi / n)
        pts += [(round(cx + r * math.cos(a)), round(cy + r * math.sin(a)), 1), (round(cx + rr * math.cos(b)), round(cy + rr * math.sin(b)), 0)]
    return pts
def rrect(x0, y0, x1, y1, rad):
    rad = min(rad, (x1 - x0) / 2, (y1 - y0) / 2)
    return [(x0 + rad, y1, 1), (x1 - rad, y1, 1), (x1, y1, 0), (x1, y1 - rad, 1), (x1, y0 + rad, 1), (x1, y0, 0), (x1 - rad, y0, 1),
            (x0 + rad, y0, 1), (x0, y0, 0), (x0, y0 + rad, 1), (x0, y1 - rad, 1), (x0, y1, 0)]
def rect(x0, y0, x1, y1): return [(x0, y1, 1), (x1, y1, 1), (x1, y0, 1), (x0, y0, 1)]
def rot(pts, cx, cy, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return [(round(cx + (x - cx) * c - (y - cy) * s), round(cy + (x - cx) * s + (y - cy) * c), on) for x, y, on in pts]

class Letters:
    def __init__(self, path):
        self.f = TTFont(path); self.gs = self.f.getGlyphSet(); self.cmap = self.f.getBestCmap()
    def knock(self, pen, text, cx, cy, h, max_w=None):
        # knock text out of the plate, centred at (cx, cy) with height h
        names = [self.cmap[ord(ch)] for ch in text]; x = 0; parts = []
        for nm in names: parts.append((nm, x)); x += self.gs[nm].width
        bp = BoundsPen(self.gs)
        for nm, dx in parts: self.gs[nm].draw(TransformPen(bp, (1, 0, 0, 1, dx, 0)))
        x0, y0, x1, y1 = bp.bounds; s = h / (y1 - y0)
        if max_w and (x1 - x0) * s > max_w:
            s = max_w / (x1 - x0)
        ox, oy = cx - (x0 + x1) / 2 * s, cy - (y0 + y1) / 2 * s
        # Knocked out = opposite direction to the plate. Fonts differ in outer-contour direction (TrueType clockwise, converted fonts often counter-clockwise); flip based on the largest contour's direction
        rec = RecordingPen()
        for nm, dx in parts: self.gs[nm].draw(TransformPen(rec, (s, 0, 0, s, ox + dx * s, oy)))
        rings, cur = [], []
        for op, args in rec.value:
            if op == 'moveTo': cur = [args[0]]; rings.append(cur)
            elif op in ('lineTo', 'qCurveTo', 'curveTo'): cur.extend(a for a in args if a is not None)
        big = max(rings, key=lambda c: abs(area(c)))
        rec.replay(ReverseContourPen(pen) if area(big) < 0 else pen)

def cross(cx, cy, half, arm):   # D-pad outline (one closed ring)
    a, h = arm / 2, half
    return [(cx - a, cy + h, 1), (cx + a, cy + h, 1), (cx + a, cy + a, 1), (cx + h, cy + a, 1), (cx + h, cy - a, 1), (cx + a, cy - a, 1),
            (cx + a, cy - h, 1), (cx - a, cy - h, 1), (cx - a, cy - a, 1), (cx - h, cy - a, 1), (cx - h, cy + a, 1), (cx - a, cy + a, 1)]

def build(out, letter_font, kbd=False):
    L = Letters(letter_font); glyphs = {}; adv = {}; cmap = {}
    def glyph(name, codes, width, draw):
        pen = TTGlyphPen(None); draw(pen, width / 2); glyphs[name] = pen.glyph(); adv[name] = width
        for c in codes: cmap[c] = name
    def round_btn(t, h=330, max_w=400):
        def d(pen, cx): contour(pen, circle(cx, CY, R)); L.knock(pen, t, cx, CY, h, max_w=max_w)
        return d
    def space_bracket(pen, cx):
        contour(pen, circle(cx, CY, R))
        w, h, t = 280, 90, 44
        x0, x1 = cx - w / 2, cx + w / 2
        y0, y1 = CY - h / 2, CY + h / 2
        pts = [
            (x0, y1, 1), (x0, y0, 1), (x1, y0, 1), (x1, y1, 1),
            (x1 - t, y1, 1), (x1 - t, y0 + t, 1), (x0 + t, y0 + t, 1), (x0 + t, y1, 1)
        ]
        contour(pen, pts, hole=True)
    def plate(t, w, h=540, th=310):
        def d(pen, cx): contour(pen, rrect(cx - w / 2, CY - h / 2, cx + w / 2, CY + h / 2, min(140, w / 4, h / 4))); L.knock(pen, t, cx, CY, th, max_w=w - 100)
        return d
    def sign(minus):
        def d(pen, cx):
            contour(pen, circle(cx, CY, R)); t, l = 60, 200
            if minus: contour(pen, rect(cx - l, CY - t, cx + l, CY + t), hole=True)
            else: contour(pen, cross(cx, CY, l, 2 * t), hole=True)
        return d
    def dpad(arm_dir):   # None = all solid; otherwise only one arm filled
        def d(pen, cx):
            contour(pen, cross(cx, CY, R, 220))
            if arm_dir is None: return
            contour(pen, cross(cx, CY, R - 40, 220 - 80), hole=True)
            arm = rect(cx - 70, CY + 70, cx + 70, CY + R - 40)
            contour(pen, rot(arm, cx, CY, {'up': 0, 'left': 90, 'down': 180, 'right': 270}[arm_dir]))
        return d
    def arrow(deg):
        def d(pen, cx):
            p = [(-380, 105, 1), (60, 105, 1), (60, 310, 1), (420, 0, 1), (60, -310, 1), (60, -105, 1), (-380, -105, 1)]
            contour(pen, rot([(cx + x, CY + y, on) for x, y, on in p], cx, CY, deg))
        return d
    def stick(t):
        def d(pen, cx):
            contour(pen, circle(cx, CY, R)); contour(pen, circle(cx, CY, R - 50), hole=True); contour(pen, circle(cx, CY, 200))
            if t: L.knock(pen, t, cx, CY, 220)
        return d

    pen = TTGlyphPen(None); glyphs['.notdef'] = pen.glyph(); adv['.notdef'] = 500
    pen_sp = TTGlyphPen(None); glyphs['space'] = pen_sp.glyph(); adv['space'] = 500; cmap[0x20] = 'space'
    if kbd:
        # Standard circular buttons (width 640, radius 270)
        # Using Apple SF Symbols from SFNSRounded.ttf
        glyph('btnA', [0xE040, 0xE0A0, 0xE0E0], 640, round_btn('\u23CE', 310))   # Return / Enter ⏎
        glyph('btnB', [0xE041, 0xE0A1, 0xE0E1], 640, round_btn('\u232B', 280))   # Delete / Backspace ⌫
        glyph('btnX', [0xE042, 0xE0A2, 0xE0E2], 640, space_bracket)              # Space ␣
        glyph('btnY', [0xE043, 0xE0A3, 0xE0E3], 640, round_btn('Click', 150))    # Click
        glyph('btnL', [0xE044, 0xE0A4, 0xE0E4], 640, round_btn('L', 330))
        glyph('btnR', [0xE045, 0xE0A5, 0xE0E5], 640, round_btn('\u21E7', 310))   # Shift ⇧
        glyph('btnZL', [0xE046, 0xE0A6, 0xE0E6], 640, round_btn('Z', 330))
        glyph('btnZR', [0xE047, 0xE0A7, 0xE0E7], 640, round_btn('C', 330))
        glyph('btnSL', [0xE0A8, 0xE0E8], 720, plate('SL', 640, h=500, th=280))
        glyph('btnSR', [0xE0A9, 0xE0E9], 720, plate('SR', 640, h=500, th=280))
        glyph('btnPlus', [0xE04B, 0xE0B5, 0xE0EF], 720, plate('Tab', 640, h=500, th=260))
        glyph('btnMinus', [0xE04C, 0xE0B6, 0xE0F0], 640, round_btn('M', 330))
        # D-pad arrows: separate Up/Down/Left/Right so Navi (0xE060) and menus get true arrow icons
        glyph('dpadUp', [0xE060], 640, round_btn('\u2191', 320))                 # Up Arrow ↑ (Navi talk)
        glyph('dpadDown', [0xE061], 640, round_btn('\u2193', 320))               # Down Arrow ↓
        glyph('dpadLeft', [0xE062], 640, round_btn('\u2190', 320))               # Left Arrow ←
        glyph('dpadRight', [0xE063], 640, round_btn('\u2192', 320))              # Right Arrow →
        glyph('dpad', [0xE064, 0xE065, 0xE049, 0xE06A, 0xE048], 640, lambda pen, cx: contour(pen, cross(cx, CY, R, 220)))
        # Compact movement & mouse plates
        glyph('stickL', [0xE05E, 0xE050, 0xE052, 0xE054, 0xE056, 0xE058, 0xE05A, 0xE05C, 0xE101, 0xE0C1], 800, plate('WASD', 720, h=500, th=260))
        glyph('stickR', [0xE05F, 0xE051, 0xE053, 0xE055, 0xE057, 0xE059, 0xE05B, 0xE05D, 0xE068, 0xE102, 0xE0C2], 850, plate('Mouse', 770, h=500, th=260))
        glyph('stick', [0xE100], 850, plate('Mouse', 770, h=500, th=260))
    else:
        for i, t in enumerate(['A', 'B', 'X', 'Y']): glyph('btn' + t, [0xE040 + i, 0xE0A0 + i, 0xE0E0 + i], 640, round_btn(t))
        for i, (t, w) in enumerate([('L', 720), ('R', 720), ('ZL', 720), ('ZR', 720)]):
            glyph('btn' + t, [0xE044 + i, 0xE0A4 + i, 0xE0E4 + i], w, plate(t, w - 80, h=540, th=330))
        for i, (t, w) in enumerate([('SL', 1000), ('SR', 1000)]):
            glyph('btn' + t, [0xE0A8 + i, 0xE0E8 + i], w, plate(t, w - 100, h=540, th=330))
        glyph('btnPlus', [0xE04B, 0xE0B5, 0xE0EF], 640, sign(False)); glyph('btnMinus', [0xE04C, 0xE0B6, 0xE0F0], 640, sign(True))
        glyph('stick', [0xE100], 700, stick(None))
        glyph('stickL', [0xE05E, 0xE050, 0xE052, 0xE054, 0xE056, 0xE058, 0xE05A, 0xE05C, 0xE101, 0xE0C1], 700, stick('L'))
        glyph('stickR', [0xE05F, 0xE051, 0xE053, 0xE055, 0xE057, 0xE059, 0xE05B, 0xE05D, 0xE068, 0xE102, 0xE0C2], 700, stick('R'))
        glyph('dpad', [0xE060, 0xE061, 0xE062, 0xE063, 0xE064, 0xE065, 0xE049, 0xE06A, 0xE048], 700, dpad(None))
    # The other code points of the private-use block the real font covers get a plain ring: a game may take one of its glyphs without a null check (Super Mario 3D All-Stars' launcher
    # sets U+E06B as its font's alternate character at boot and read through the null glyph), and in text a ring is no worse than the "?" of a missing icon
    glyph('icon', [c for c in range(0xE000, 0xE200) if c not in cmap], 640, lambda pen, cx: (contour(pen, circle(cx, CY, R)), contour(pen, circle(cx, CY, R - 50), hole=True)))

    order = ['.notdef'] + sorted(n for n in glyphs if n != '.notdef')
    fb = FontBuilder(EM, isTTF=True)
    fb.setupGlyphOrder(order); fb.setupCharacterMap(cmap); fb.setupGlyf(glyphs)
    glyf = fb.font['glyf']
    for n in order: glyf[n].recalcBounds(glyf)
    fb.setupHorizontalMetrics({n: (adv[n], getattr(glyf[n], 'xMin', 0)) for n in order})
    fb.setupHorizontalHeader(ascent=ASC, descent=DESC)
    fb.setupNameTable({'familyName': 'DM Nintendo Extension Stand-in', 'styleName': 'Regular'})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0, usWinAscent=ASC, usWinDescent=-DESC)
    fb.setupPost(); fb.save(out)
    print('%s: %d glyphs, %d code points' % (out, len(order), len(cmap)))

def encode_bfotf_zs(ttf_path, out_zs_path, dict_path=None):
    with open(ttf_path, 'rb') as f:
        ttf_data = bytearray(f.read())
    while len(ttf_data) % 4 != 0:
        ttf_data.append(0)
    key = 0x028501a6
    enc = bytearray(8 + len(ttf_data))
    struct.pack_into('<I', enc, 0, 0x1a879bd9)
    w1 = struct.unpack('<I', struct.pack('>I', len(ttf_data)))[0] ^ key
    struct.pack_into('<I', enc, 4, w1)
    for i in range(0, len(ttf_data), 4):
        w = struct.unpack_from('<I', ttf_data, i)[0]
        struct.pack_into('<I', enc, 8 + i, w ^ key)
    import zstandard
    dict_data = None
    if dict_path and os.path.isfile(dict_path):
        with open(dict_path, 'rb') as f:
            dict_data = zstandard.ZstdCompressionDict(f.read())
    cctx = zstandard.ZstdCompressor(dict_data=dict_data)
    comp = cctx.compress(enc)
    os.makedirs(os.path.dirname(os.path.abspath(out_zs_path)), exist_ok=True)
    with open(out_zs_path, 'wb') as f:
        f.write(comp)
    print(f'{out_zs_path}: packed BFOTF+zstd ({len(comp)} bytes)')

if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    kbd_flag = '--kbd' in sys.argv
    bfotf_zs = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--bfotf=')), None)
    zsdic = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--dict=')), None)
    if not args: sys.exit(__doc__ or 'usage: make_ext_font.py [--kbd] [--bfotf=out.bfotf.zs] [--dict=zs.zsdic] out.ttf [letter-font.ttf]')
    default_font = '/System/Library/Fonts/SFNSRounded.ttf' if os.path.exists('/System/Library/Fonts/SFNSRounded.ttf') else '/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf'
    build(args[0], args[1] if len(args) > 1 else default_font, kbd=kbd_flag)
    if bfotf_zs:
        encode_bfotf_zs(args[0], bfotf_zs, zsdic)
