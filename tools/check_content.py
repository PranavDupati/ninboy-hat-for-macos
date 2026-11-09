#!/usr/bin/env python3
"""
check_content.py - Ninboy Hat Repository Sanitization & Safety Verification
Inspired by the content boundary verification system from GreenKid-MV (adi0900/GreenKid-MV).

Validates that the repository contains NO copyrighted Nintendo ROMs, ExeFS binaries,
console keys, or personal saves, ensuring a completely clean and legal distribution.
"""

import os
import sys
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OMIT_DIRS = {'.git', 'dist', 'build', '.build', '.venv', '__pycache__', '.pytest_cache'}
FORBIDDEN_SUFFIXES = {'.nup', '.nsp', '.nsz', '.xci', '.xcz', '.nca', '.nso', '.nro', '.kip', '.keys', '.sav', '.ipa'}
FORBIDDEN_NAMES = {'prod.keys', 'title.keys', 'console.keys'}

# Explicitly permitted custom mod assets (custom keyboard font & prompt texture dictionary)
PERMITTED_MOD_FILES = {
    'Common_kbd.Product.100.Nin_Ounce_NVN2.bntx.zs',
    'External_kbd.Nin_Ounce_NVN2.bfotf.zs',
    'nintendo_ext_kbd.ttf',
    'zs.zsdic'
}

def scan_files(root):
    for current, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in OMIT_DIRS]
        for name in files:
            yield Path(current) / name

def check_repository(root):
    errors = []
    scanned_count = 0
    
    for path in scan_files(root):
        rel = path.relative_to(root).as_posix()
        scanned_count += 1
        
        # Check forbidden names
        if path.name.lower() in FORBIDDEN_NAMES:
            errors.append((rel, 'Console keys detected'))
            continue
            
        # Check forbidden suffixes unless explicitly part of our custom mods
        if path.name in PERMITTED_MOD_FILES:
            continue
            
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            errors.append((rel, f'Commercial game container / binary ({path.suffix}) detected'))
            continue
            
        # Check executable binary magic headers
        try:
            with path.open('rb') as f:
                magic = f.read(4)
                if magic in {b'NSO0', b'NRO0', b'KIP1'}:
                    errors.append((rel, 'Raw Switch executable header detected'))
        except OSError:
            pass

    return errors, scanned_count

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT, help='Root directory to scan')
    args = parser.parse_args()
    
    print(f"==> Scanning repository at: {args.root} ...")
    errors, count = check_repository(args.root)
    
    print(f"==> Checked {count} files.")
    if errors:
        print("[FAIL] Sanitization issues detected:")
        for file, reason in errors:
            print(f"  ✗ {file}: {reason}")
        return 1
    else:
        print("  ✓ Repository is clean! No commercial game containers, keys, or binaries detected.")
        return 0

if __name__ == '__main__':
    sys.exit(main())
