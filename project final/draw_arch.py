"""Draw RiskGuard System Architecture Diagram as PNG using Pillow."""
from PIL import Image, ImageDraw, ImageFont
import os

W, H = 1920, 1080
img = Image.new('RGB', (W, H), '#FFFFFF')
draw = ImageDraw.Draw(img)

# Try to load fonts
try:
    font_title = ImageFont.truetype("times.ttf", 28)
    font_head = ImageFont.truetype("timesbd.ttf", 18)
    font_body = ImageFont.truetype("times.ttf", 14)
    font_small = ImageFont.truetype("times.ttf", 12)
    font_arrow = ImageFont.truetype("timesi.ttf", 13)
    font_main = ImageFont.truetype("timesbd.ttf", 32)
except:
    try:
        font_title = ImageFont.truetype("C:/Windows/Fonts/times.ttf", 28)
        font_head = ImageFont.truetype("C:/Windows/Fonts/timesbd.ttf", 18)
        font_body = ImageFont.truetype("C:/Windows/Fonts/times.ttf", 14)
        font_small = ImageFont.truetype("C:/Windows/Fonts/times.ttf", 12)
        font_arrow = ImageFont.truetype("C:/Windows/Fonts/timesi.ttf", 13)
        font_main = ImageFont.truetype("C:/Windows/Fonts/timesbd.ttf", 32)
    except:
        font_title = ImageFont.load_default()
        font_head = font_body = font_small = font_arrow = font_main = font_title

def draw_rounded_rect(x, y, w, h, fill, outline, r=15):
    draw.rounded_rectangle([x, y, x+w, y+h], radius=r, fill=fill, outline=outline, width=2)

def draw_box_title(x, y, w, title, color):
    draw.rounded_rectangle([x, y, x+w, y+28], radius=8, fill=color, outline=color)
    tw = draw.textlength(title, font=font_head)
    draw.text((x + (w - tw)//2, y+4), title, fill='#FFFFFF', font=font_head)

def draw_items(x, y, items, font=None):
    f = font or font_body
    for i, item in enumerate(items):
        bx = x + 8
        by = y + i * 20
        draw.ellipse([bx, by+5, bx+6, by+11], fill='#555555')
        draw.text((bx+12, by), item, fill='#333333', font=f)

def draw_arrow(x1, y1, x2, y2, label='', color='#666666'):
    draw.line([(x1, y1), (x2, y2)], fill=color, width=2)
    # Arrowhead
    import math
    angle = math.atan2(y2-y1, x2-x1)
    al = 10
    draw.polygon([
        (x2, y2),
        (x2 - al*math.cos(angle-0.4), y2 - al*math.sin(angle-0.4)),
        (x2 - al*math.cos(angle+0.4), y2 - al*math.sin(angle+0.4)),
    ], fill=color)
    if label:
        mx, my = (x1+x2)//2, (y1+y2)//2
        draw.text((mx-30, my-16), label, fill=color, font=font_arrow)

# ===== TITLE =====
title = "RiskGuard - High-Level System Architecture"
tw = draw.textlength(title, font=font_main)
draw.text(((W-tw)//2, 15), title, fill='#1a1a2e', font=font_main)

# ===== 1. FLUTTER MOBILE APP (top center) =====
fx, fy, fw, fh = 60, 70, 560, 240
draw_rounded_rect(fx, fy, fw, fh, '#e8f4fd', '#2196F3')
draw_box_title(fx, fy, fw, 'Flutter Mobile Application', '#1976D2')

app_items = ['Dashboard & Navigation', 'Image Analysis Screen',
             'Voice Analysis Screen', 'Text Verification Screen',
             'Video Analysis Screen', 'Evidence Filing Screen',
             'Permission Onboarding']
draw_items(fx+10, fy+34, app_items, font_small)

# ===== 2. REAL-TIME OVERLAY (top right of Flutter) =====
ox, oy, ow, oh = 640, 70, 400, 240
draw_rounded_rect(ox, oy, ow, oh, '#e8f5e9', '#4CAF50')
draw_box_title(ox, oy, ow, 'Real-Time Protection Overlay', '#388E3C')

overlay_items = ['Android Accessibility Service',
                 'System Overlay (2300+ lines)',
                 'Monitoring Bubble / Verdict Card',
                 'Call Monitoring Chip',
                 'URL Capture & Media Capture',
                 'Whitelisted App Detection']
draw_items(ox+10, oy+34, overlay_items, font_small)

# ===== 3. LOCAL EDGE PROCESSING (left middle) =====
lx, ly, lw, lh = 60, 370, 430, 280
draw_rounded_rect(lx, ly, lw, lh, '#f1f8e9', '#8BC34A')
draw_box_title(lx, ly, lw, 'Local Edge Processing (CPU - No Cloud)', '#689F38')

local_items = ['NPR (Noise Print Residual)', 'DCT Spectral Analysis',
               'Haar Wavelet Decomposition', 'Perceptual Hashing (pHash)',
               'LFCC Cepstral Coefficients', 'CQT Phase Coherence',
               'Modulation Spectrum', 'Pitch/F0 Contour Tracking',
               'Statistical Moments', 'Local Text Statistics',
               'URL Heuristic Screening']
draw_items(lx+10, ly+34, local_items, font_small)

# ===== 4. FASTAPI BACKEND (center middle) =====
bx, by, bw, bh = 530, 370, 400, 200
draw_rounded_rect(bx, by, bw, bh, '#fff3e0', '#FF9800')
draw_box_title(bx, by, bw, 'FastAPI Backend Server', '#F57C00')

backend_items = ['Async REST API (Python 3.11+)',
                 'Multi-Modal Detection Engine',
                 'Evidence Manager',
                 'SSE Real-Time Events',
                 'URL Verification (URLhaus)',
                 'Risk Scoring Engine']
draw_items(bx+10, by+34, backend_items, font_small)

# ===== 5. CLOUD AI (right middle) =====
cx, cy, cw, ch = 970, 370, 380, 200
draw_rounded_rect(cx, cy, cw, ch, '#f3e5f5', '#9C27B0')
draw_box_title(cx, cy, cw, 'Cloud AI Services (Optional)', '#7B1FA2')

cloud_items = ['HuggingFace Inference API',
               '  - DeBERTa, RoBERTa, AI Image Detector',
               'Google Colab + ONNX Runtime',
               '  - wav2vec2 (ASVspoof2019)',
               '  - CNN Image Classifier',
               'Fallback: 100% Local CPU']
draw_items(cx+10, cy+34, cloud_items, font_small)

# ===== 6. BLOCKCHAIN & EVIDENCE (bottom left) =====
blx, bly, blw, blh = 60, 710, 430, 200
draw_rounded_rect(blx, bly, blw, blh, '#e0f2f1', '#009688')
draw_box_title(blx, bly, blw, 'Blockchain & Evidence Layer', '#00796B')

bc_items = ['SHA-256 Hash Fingerprinting',
            'IPFS Decentralized Storage (Pinata)',
            'Merkle Tree Batch Aggregation',
            'Polygon Amoy Blockchain',
            'EvidenceAnchor Smart Contract (Solidity)',
            'SQLite Off-Chain Evidence DB']
draw_items(blx+10, bly+34, bc_items, font_small)

# ===== 7. INVESTIGATION DASHBOARD (bottom right) =====
dx, dy, dw, dh = 530, 710, 400, 200
draw_rounded_rect(dx, dy, dw, dh, '#fce4ec', '#E91E63')
draw_box_title(dx, dy, dw, 'Cybercrime Investigation Dashboard', '#C2185B')

dash_items = ['Live Evidence Table (SSE)',
              'Green Pulsing LIVE Badge',
              'Toast Notifications + Sound Alerts',
              'Full Evidence Detail View',
              'One-Click Batch Anchoring',
              'PolygonScan Direct Links']
draw_items(dx+10, dy+34, dash_items, font_small)

# ===== 8. LEGEND (bottom right corner) =====
lgx, lgy = 1060, 710
draw_rounded_rect(lgx, lgy, 290, 200, '#fafafa', '#999999')
draw.text((lgx+10, lgy+8), 'Legend', fill='#333', font=font_head)
# Green - local
draw.rectangle([lgx+15, lgy+38, lgx+35, lgy+52], fill='#8BC34A', outline='#689F38')
draw.text((lgx+42, lgy+36), 'Local Processing (No Cloud)', fill='#333', font=font_small)
# Purple - cloud
draw.rectangle([lgx+15, lgy+60, lgx+35, lgy+74], fill='#9C27B0', outline='#7B1FA2')
draw.text((lgx+42, lgy+58), 'Cloud-Enhanced (Optional)', fill='#333', font=font_small)
# Orange - backend
draw.rectangle([lgx+15, lgy+82, lgx+35, lgy+96], fill='#FF9800', outline='#F57C00')
draw.text((lgx+42, lgy+80), 'Backend Server', fill='#333', font=font_small)
# Teal - blockchain
draw.rectangle([lgx+15, lgy+104, lgx+35, lgy+118], fill='#009688', outline='#00796B')
draw.text((lgx+42, lgy+102), 'Blockchain & Evidence', fill='#333', font=font_small)
# Blue - mobile
draw.rectangle([lgx+15, lgy+126, lgx+35, lgy+140], fill='#2196F3', outline='#1976D2')
draw.text((lgx+42, lgy+124), 'Mobile Application', fill='#333', font=font_small)
# Pink - dashboard
draw.rectangle([lgx+15, lgy+148, lgx+35, lgy+162], fill='#E91E63', outline='#C2185B')
draw.text((lgx+42, lgy+146), 'Investigation Dashboard', fill='#333', font=font_small)

# ===== ARROWS =====
# Flutter -> Local Edge
draw_arrow(280, fy+fh, 280, ly, 'Local Signals', '#689F38')
# Flutter -> Backend
draw_arrow(fx+fw, fy+fh//2+40, bx, by, 'HTTPS REST API', '#F57C00')
# Overlay -> Flutter (bidirectional)
draw_arrow(ox, oy+oh//2, fx+fw, fy+fh//2, 'Platform\nChannels', '#388E3C')
# Backend -> Cloud
draw_arrow(bx+bw, by+bh//2, cx, cy+ch//2, 'Cloud Inference', '#7B1FA2')
# Backend -> Blockchain
draw_arrow(bx+bw//4, by+bh, blx+blw//2, bly, 'Evidence Pipeline', '#00796B')
# Backend -> Dashboard
draw_arrow(bx+bw*3//4, by+bh, dx+dw//4, dy, 'SSE Stream', '#C2185B')
# Local -> Backend (results)
draw_arrow(lx+lw, ly+lh//2, bx, by+bh//2, 'Signal Results', '#F57C00')

# Save
out_path = os.path.join(r'c:\dev\flutter_pro\RiskGaurd1\project final', 'RiskGuard_Architecture.png')
img.save(out_path, 'PNG', quality=95)
print(f"Saved to: {out_path}")
print(f"Size: {img.size}")
