#!/usr/bin/env python3
"""Printed sheets, read back by a reader that shares no code with the app.

Run with no arguments after `MEOW_PRINT_SAMPLES=1 flutter test`, this renders
artifacts/print-sheets/golden-*.pdf with PDFium and compares each page with
test/goldens/print. Pass --update to accept the current renders; look at them
first. check_native_print.py uses job_issues on what reached the spooler.
"""
import argparse
from pathlib import Path
import re
import sys

from PIL import Image, ImageChops, ImageOps
import pypdfium2 as pdfium

root = Path(__file__).resolve().parent.parent
samples = root / 'artifacts/print-sheets'
goldens = root / 'test/goldens/print'
diffs = root / 'artifacts/print-render-diffs'

# Rendering at 72 dpi draws a point as a pixel. A pixel "differs" past a
# quarter of the grey range, and a page may differ in this share of its pixels:
# enough for antialiasing between PDFium builds, far too little for a moved
# table, a lost font or a missing column.
PIXEL_TOLERANCE = 64
PAGE_TOLERANCE = 0.002


def render(page, dpi=72):
    return page.render(scale=dpi / 72, grayscale=True).to_pil().convert('L')


def ink_box(image):
    """The box around everything darker than light grey, or None when blank."""
    return ImageOps.invert(image).point(lambda v: 255 if v > 64 else 0).getbbox()


def job_issues(path, expected, require_text=True):
    """What is wrong with the job at [path] against the manifest entry."""
    name = expected['name']
    try:
        document = pdfium.PdfDocument(str(path))
    except Exception as error:
        return [f'{name}: not a readable PDF: {error}']
    issues = []
    if len(document) != expected['pages']:
        issues.append(f'{name}: {len(document)} pages, expected {expected["pages"]}')
    text = ''
    for index in range(len(document)):
        page = document[index]
        width, height = page.get_size()
        if abs(width - expected['width']) > 2 or abs(height - expected['height']) > 2:
            issues.append(
                f'{name} page {index + 1}: {width:.0f} x {height:.0f} pt, '
                f'expected {expected["width"]:.0f} x {expected["height"]:.0f}')
        image = render(page)
        box = ink_box(image)
        if box is None:
            issues.append(f'{name} page {index + 1}: blank')
        elif box[3] < image.height * 0.9:
            # Every sheet has a footer, so its absence means a clipped page.
            issues.append(f'{name} page {index + 1}: nothing below '
                          f'{box[3] / image.height:.0%} of the page; the footer was lost')
        text += page.get_textpage().get_text_bounded()
    # Some spoolers redraw text as outlines, which still prints.
    if require_text or text.strip():
        squeezed = re.sub(r'\s+', '', text)
        for word in expected['words']:
            if word not in squeezed:
                issues.append(f'{name}: "{word}" is not on the page')
    document.close()
    return issues


def compare_page(image, golden):
    """The share of pixels that differ, or 1.0 when the page size changed."""
    if image.size != golden.size:
        return 1.0
    different = ImageChops.difference(image, golden).point(
        lambda v: 255 if v > PIXEL_TOLERANCE else 0)
    return different.histogram()[255] / (image.width * image.height)


def render_issues(sample_dir=samples, golden_dir=goldens, diff_dir=diffs, update=False):
    issues = []
    pdfs = sorted(sample_dir.glob('golden-*.pdf'))
    if not pdfs:
        return [f'No sheets in {sample_dir}; run MEOW_PRINT_SAMPLES=1 flutter test first']
    seen = set()
    for pdf in pdfs:
        stem = pdf.stem.removeprefix('golden-')
        document = pdfium.PdfDocument(str(pdf))
        for index in range(len(document)):
            name = f'{stem}-p{index + 1}.png'
            seen.add(name)
            image = render(document[index])
            target = golden_dir / name
            if update:
                golden_dir.mkdir(parents=True, exist_ok=True)
                image.save(target, optimize=True)
                continue
            if not target.exists():
                issues.append(f'{name}: no golden; look at the sheet, then run --update')
                continue
            share = compare_page(image, Image.open(target).convert('L'))
            if share > PAGE_TOLERANCE:
                diff_dir.mkdir(parents=True, exist_ok=True)
                image.save(diff_dir / name)
                issues.append(f'{name}: {share:.2%} of the page changed; '
                              f'this render is in {diff_dir.relative_to(root) if diff_dir.is_relative_to(root) else diff_dir}')
        document.close()
    if update:
        for stale in set(p.name for p in golden_dir.glob('*.png')) - seen:
            (golden_dir / stale).unlink()
    else:
        for missing in set(p.name for p in golden_dir.glob('*.png')) - seen:
            issues.append(f'{missing}: the sheet for this golden was not printed')
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update', action='store_true', help='accept the current renders')
    arguments = parser.parse_args()
    issues = render_issues(update=arguments.update)
    if issues:
        sys.exit('\n'.join(issues))
    print('PASS: printed sheets render as the goldens do')


if __name__ == '__main__':
    main()
