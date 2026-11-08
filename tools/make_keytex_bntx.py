#!/usr/bin/env python3
"""
Generate keyboard button prompt textures for The Legend of Zelda: Ocarina of Time (Switch 2 / NVN2).
Replaces the four face button icons in the HUD diamond cluster (KeyTexFontA_00, KeyTexFontB_00, KeyTexFontX_00, KeyTexFontY_00)
inside UI/Layout2Archive/Common.Product.100.Nin_Ounce_NVN2.bntx.zs with clean, unhighlighted keyboard symbols:
  - A: Return key SF Symbol (⏎)
  - B: Delete key SF Symbol (⌫)
  - X: Spacebar bracket (␣)
  - Y: Click

Usage:
  python3 make_keytex_bntx.py <romfs.img> <dict.zsdic> <out_bntx.zs>
"""

import os, sys, struct, subprocess, tempfile, time
import zstandard

def gob_off_s2(x, y):
    # Switch 2 (NVN2) GOB swizzle layout
    return (x % 64 // 32) * 256 + (y % 8 // 4) * 128 + (x % 32 // 16) * 64 + (y % 4 // 2) * 32 + (y % 2) * 16 + x % 16

def encode_bc4_block(pix16):
    r0 = max(pix16)
    r1 = min(pix16)
    if r0 == r1:
        return bytes([r0, r1, 0, 0, 0, 0, 0, 0])
    pal = [
        r0, r1,
        round((6 * r0 + 1 * r1) / 7),
        round((5 * r0 + 2 * r1) / 7),
        round((4 * r0 + 3 * r1) / 7),
        round((3 * r0 + 4 * r1) / 7),
        round((2 * r0 + 5 * r1) / 7),
        round((1 * r0 + 6 * r1) / 7),
    ]
    idx_bits = 0
    for i, v in enumerate(pix16):
        best_idx = min(range(8), key=lambda idx: abs(v - pal[idx]))
        idx_bits |= (best_idx << (i * 3))
    return bytes([r0, r1]) + idx_bits.to_bytes(6, 'little')

def swizzle_bc4(blocks):
    out = bytearray(2048)
    bh = 2
    gobs_x = 2
    block_bytes = 1024
    for by in range(16):
        for bx in range(16):
            x_byte = bx * 8
            y_row = by
            bl_off = (y_row // 16) * gobs_x * block_bytes + (x_byte // 64) * block_bytes + ((y_row % 16) // 8) * 512 + gob_off_s2(x_byte, y_row)
            b = blocks[by * 16 + bx]
            out[bl_off : bl_off + 8] = b
    return bytes(out)

def render_native_glyphs(out_dir):
    src = f'''
#import <Cocoa/Cocoa.h>

void save_pgm(const char *outfile, uint8_t *data, int w, int h) {{
    FILE *f = fopen(outfile, "wb");
    fprintf(f, "P5\\n%d %d\\n255\\n", w, h);
    fwrite(data, 1, w * h, f);
    fclose(f);
}}

int main() {{
    @autoreleasepool {{
        int w = 64, h = 64;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();

        // 1. A: Return (⏎)
        {{
            CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, cs, (CGBitmapInfo)kCGImageAlphaNone);
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
            NSFont *font = [NSFont systemFontOfSize:26 weight:NSFontWeightBold];
            NSString *str = @"\\u23CE";
            NSDictionary *attrs = @{{NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor whiteColor]}};
            NSSize s = [str sizeWithAttributes:attrs];
            NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
            [NSGraphicsContext setCurrentContext:gc];
            [str drawInRect:NSMakeRect((w - s.width) / 2.0, (h - s.height) / 2.0, s.width, s.height) withAttributes:attrs];
            save_pgm("{out_dir}/glyph_A.pgm", CGBitmapContextGetData(ctx), w, h);
            CGContextRelease(ctx);
        }}

        // 2. B: Delete (⌫)
        {{
            CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, cs, (CGBitmapInfo)kCGImageAlphaNone);
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
            NSFont *font = [NSFont systemFontOfSize:26 weight:NSFontWeightBold];
            NSString *str = @"\\u232B";
            NSDictionary *attrs = @{{NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor whiteColor]}};
            NSSize s = [str sizeWithAttributes:attrs];
            NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
            [NSGraphicsContext setCurrentContext:gc];
            [str drawInRect:NSMakeRect((w - s.width) / 2.0, (h - s.height) / 2.0, s.width, s.height) withAttributes:attrs];
            save_pgm("{out_dir}/glyph_B.pgm", CGBitmapContextGetData(ctx), w, h);
            CGContextRelease(ctx);
        }}

        // 3. X: Space (␣)
        {{
            CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, cs, (CGBitmapInfo)kCGImageAlphaNone);
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
            CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
            CGContextSetLineWidth(ctx, 3.8);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGContextSetLineJoin(ctx, kCGLineJoinRound);
            float cx = 32.0, cy = 32.0, sw = 32.0, sh = 13.0;
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, cx - sw/2, cy + sh/2);
            CGContextAddLineToPoint(ctx, cx - sw/2, cy - sh/2);
            CGContextAddLineToPoint(ctx, cx + sw/2, cy - sh/2);
            CGContextAddLineToPoint(ctx, cx + sw/2, cy + sh/2);
            CGContextStrokePath(ctx);
            save_pgm("{out_dir}/glyph_X.pgm", CGBitmapContextGetData(ctx), w, h);
            CGContextRelease(ctx);
        }}

        // 4. Y: Click
        {{
            CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, cs, (CGBitmapInfo)kCGImageAlphaNone);
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
            NSFont *font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
            NSString *str = @"Click";
            NSDictionary *attrs = @{{NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor whiteColor]}};
            NSSize s = [str sizeWithAttributes:attrs];
            NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
            [NSGraphicsContext setCurrentContext:gc];
            [str drawInRect:NSMakeRect((w - s.width) / 2.0, (h - s.height) / 2.0, s.width, s.height) withAttributes:attrs];
            save_pgm("{out_dir}/glyph_Y.pgm", CGBitmapContextGetData(ctx), w, h);
            CGContextRelease(ctx);
        }}

        CGColorSpaceRelease(cs);
    }}
    return 0;
}}
'''
    src_file = os.path.join(out_dir, 'render.m')
    bin_file = os.path.join(out_dir, 'render')
    with open(src_file, 'w') as f:
        f.write(src)
    subprocess.check_call(['clang', '-framework', 'Cocoa', src_file, '-o', bin_file])
    subprocess.check_call([bin_file])

def pgm_to_swizzled_bc4(pgm_path):
    with open(pgm_path, 'rb') as f:
        f.readline(); f.readline(); f.readline()
        pix = list(f.read())
    blocks = []
    for by in range(16):
        for bx in range(16):
            pix16 = []
            for py in range(4):
                for px in range(4):
                    pix16.append(pix[(by * 4 + py) * 64 + (bx * 4 + px)])
            blocks.append(encode_bc4_block(pix16))
    return swizzle_bc4(blocks)

def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <romfs.img> <zs.zsdic> <output_bntx.zs>")
        sys.exit(1)

    romfs_path = sys.argv[1]
    dict_path = sys.argv[2]
    out_path = sys.argv[3]

    with open(dict_path, 'rb') as df:
        c_dict = zstandard.ZstdCompressionDict(df.read())
    dctx = zstandard.ZstdDecompressor(dict_data=c_dict)

    print("Locating Common.Product.100.Nin_Ounce_NVN2.bntx.zs in RomFS...")
    # Find entry in RomFS index
    offset = 21033323891
    size = 64862732
    with open(romfs_path, 'rb') as f:
        f.seek(offset)
        comp = f.read(size)

    print(f"Decompressing {size} bytes with zstandard...")
    t0 = time.time()
    bntx = bytearray(dctx.decompress(comp))
    print(f"Decompressed {len(bntx)} bytes in {time.time() - t0:.2f}s")

    with tempfile.TemporaryDirectory() as tmpdir:
        print("Rendering SF Symbols & vector glyphs...")
        render_native_glyphs(tmpdir)

        textures = {
            'A': (0x4534200, os.path.join(tmpdir, 'glyph_A.pgm')),
            'B': (0x4534a00, os.path.join(tmpdir, 'glyph_B.pgm')),
            'X': (0x4535200, os.path.join(tmpdir, 'glyph_X.pgm')),
            'Y': (0x4535a00, os.path.join(tmpdir, 'glyph_Y.pgm')),
        }

        for name, (ptr, pgm_file) in textures.items():
            swizzled = pgm_to_swizzled_bc4(pgm_file)
            assert len(swizzled) == 2048
            bntx[ptr : ptr + 2048] = swizzled
            print(f"Patched KeyTexFont{name}_00 at 0x{ptr:x}")

    print("Recompressing patched BNTX with zstandard (level 3)...")
    t1 = time.time()
    cctx = zstandard.ZstdCompressor(level=3, dict_data=c_dict)
    comp_new = cctx.compress(bntx)
    print(f"Compressed to {len(comp_new)} bytes in {time.time() - t1:.2f}s")

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, 'wb') as f:
        f.write(comp_new)
    print(f"Wrote {out_path} successfully!")

if __name__ == '__main__':
    main()
