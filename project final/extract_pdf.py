import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

from PyPDF2 import PdfReader

reader = PdfReader(r'c:\dev\flutter_pro\RiskGaurd1\project final\RiskGuard Project Report - Edited - final.pdf')
print(f'Total pages: {len(reader.pages)}')
for i, page in enumerate(reader.pages):
    text = page.extract_text()
    if text:
        print(f'\n===== PAGE {i+1} =====')
        print(text[:3000])
