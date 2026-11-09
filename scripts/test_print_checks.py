"""The print checkers must be able to fail: a checker that passes everything
would pass a broken sheet too."""
from pathlib import Path
import tempfile
import unittest

from PIL import Image
import print_checks


def write_pdf(path, pages=1, size=(612, 792), text='Player', footer=True, blank=False, shift=0):
    """The smallest PDF the checkers can read, with a line of text and a footer."""
    width, height = size
    drawing = '' if blank else ''.join(
        f'BT /F1 18 Tf 72 {height - 72 - shift - line * 24} Td ({text}) Tj ET\n' for line in range(12))
    if footer and not blank:
        drawing += f'BT /F1 9 Tf 32 30 Td (Revision 7) Tj ET\n'
    stream = drawing.encode('latin-1')
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>']
    kids = ' '.join(f'{4 + i * 2} 0 R' for i in range(pages))
    objects.append(f'<< /Type /Pages /Kids [{kids}] /Count {pages} >>'.encode())
    objects.append(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
    for i in range(pages):
        objects.append(
            f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] '
            f'/Resources << /Font << /F1 3 0 R >> >> /Contents {5 + i * 2} 0 R >>'.encode())
        objects.append(b'<< /Length %d >>\nstream\n' % len(stream) + stream + b'endstream')
    body = b'%PDF-1.4\n'
    offsets = []
    for number, content in enumerate(objects, 1):
        offsets.append(len(body))
        body += b'%d 0 obj\n' % number + content + b'\nendobj\n'
    xref = len(body)
    body += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1)
    for offset in offsets:
        body += b'%010d 00000 n \n' % offset
    body += b'trailer << /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
    path.write_bytes(body)


EXPECTED = {'name': 'sheet', 'pages': 1, 'width': 612, 'height': 792, 'words': ['Player']}


class JobTest(unittest.TestCase):
    def issues(self, expected=EXPECTED, require_text=True, **pdf):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'job.pdf'
            write_pdf(path, **pdf)
            return print_checks.job_issues(path, expected, require_text=require_text)

    def test_a_good_job_passes(self):
        self.assertEqual(self.issues(), [])

    def test_a_missing_page_fails(self):
        self.assertIn('pages', self.issues(expected={**EXPECTED, 'pages': 2})[0])

    def test_the_wrong_paper_fails(self):
        self.assertIn('595 x 842', self.issues(size=(595, 842))[0])

    def test_a_blank_page_fails(self):
        self.assertTrue(any('blank' in i for i in self.issues(blank=True)))

    def test_a_clipped_page_fails(self):
        self.assertTrue(any('footer' in i for i in self.issues(footer=False)))

    def test_a_missing_word_fails(self):
        self.assertIn('"Player"', self.issues(text='Someone')[0])

    def test_text_drawn_as_outlines_can_be_allowed_but_not_wrong_text(self):
        self.assertIn('"Player"', self.issues(text='Someone', require_text=False)[0])

    def test_a_job_matching_the_sheet_the_app_sent_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            write_pdf(Path(temp) / 'sent.pdf')
            write_pdf(Path(temp) / 'job.pdf')
            expected = {**EXPECTED, 'reference': 'sent.pdf'}
            self.assertEqual(print_checks.job_issues(Path(temp) / 'job.pdf', expected,
                                                     reference_dir=temp), [])

    def test_a_job_drawn_lower_than_the_sheet_sent_fails_without_text(self):
        with tempfile.TemporaryDirectory() as temp:
            write_pdf(Path(temp) / 'sent.pdf', text='Player Player Player Player Player')
            write_pdf(Path(temp) / 'job.pdf', text='Player Player Player Player Player', shift=40)
            expected = {**EXPECTED, 'reference': 'sent.pdf'}
            issues = print_checks.job_issues(Path(temp) / 'job.pdf', expected,
                                             require_text=False, reference_dir=temp)
            self.assertTrue(any('differs from the sheet' in i for i in issues), issues)

    def test_something_that_is_not_a_pdf_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'job.pdf'
            path.write_bytes(b'not a pdf')
            self.assertIn('not a readable PDF', print_checks.job_issues(path, EXPECTED)[0])


class RenderTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        self.samples, self.goldens, self.diffs = base / 's', base / 'g', base / 'd'
        self.samples.mkdir()
        write_pdf(self.samples / 'golden-sheet.pdf')

    def check(self, **options):
        return print_checks.render_issues(self.samples, self.goldens, self.diffs, **options)

    def test_an_unchanged_sheet_passes(self):
        self.assertEqual(self.check(update=True), [])
        self.assertEqual(self.check(), [])

    def test_changed_text_fails_and_keeps_the_render(self):
        self.check(update=True)
        write_pdf(self.samples / 'golden-sheet.pdf', text='A very different line of text here')
        issues = self.check()
        self.assertIn('of the page changed', issues[0])
        self.assertTrue((self.diffs / 'sheet-p1.png').exists())

    def test_a_new_sheet_needs_a_golden(self):
        self.assertIn('no golden', self.check()[0])

    def test_a_lost_sheet_fails(self):
        self.check(update=True)
        Image.new('L', (10, 10)).save(self.goldens / 'gone-p1.png')
        self.assertIn('not printed', self.check()[0])

    def test_no_sheets_at_all_fails(self):
        (self.samples / 'golden-sheet.pdf').unlink()
        self.assertIn('No sheets', self.check()[0])


if __name__ == '__main__':
    unittest.main()
