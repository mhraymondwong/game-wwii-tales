#!/usr/bin/env python3
"""Process assets/ui/icons/*.jpg → assets/ui/processed/icons/*.png (circle crop)."""
from collections import deque
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "ui", "icons")
DST = os.path.join(ROOT, "assets", "ui", "processed", "icons")
OUT = 96
NAMES = ["infantry", "armor", "artillery", "recon", "antitank", "engineer", "halftrack", "confirm", "header-bar", "badge-allies", "badge-axis", "points", "round"]


def process(name: str, tol: float = 16.0) -> None:
	rgb = np.array(Image.open(os.path.join(SRC, f"{name}.jpg")).convert("RGB"))
	h, w, _ = rgb.shape
	mx = rgb.max(2)
	luma = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
	cand = (mx <= tol) | (luma <= tol)
	vis = np.zeros((h, w), dtype=bool)
	q = deque()
	for x in range(w):
		for y in (0, h - 1):
			if cand[y, x]:
				vis[y, x] = True
				q.append((y, x))
	for y in range(h):
		for x in (0, w - 1):
			if cand[y, x] and not vis[y, x]:
				vis[y, x] = True
				q.append((y, x))
	while q:
		y, x = q.popleft()
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			ny, nx = y + dy, x + dx
			if 0 <= ny < h and 0 <= nx < w and not vis[ny, nx] and cand[ny, nx]:
				vis[ny, nx] = True
				q.append((ny, nx))
	subject = ~vis
	seen = np.zeros((h, w), dtype=bool)
	best = []
	for y in range(h):
		for x in range(w):
			if not subject[y, x] or seen[y, x]:
				continue
			qq = deque([(y, x)])
			seen[y, x] = True
			cells = [(y, x)]
			while qq:
				cy, cx = qq.popleft()
				for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
					ny, nx = cy + dy, cx + dx
					if 0 <= ny < h and 0 <= nx < w and subject[ny, nx] and not seen[ny, nx]:
						seen[ny, nx] = True
						qq.append((ny, nx))
						cells.append((ny, nx))
			if len(cells) > len(best):
				best = cells
	keep = np.zeros((h, w), dtype=bool)
	for y, x in best:
		keep[y, x] = True
	alpha = np.zeros((h, w), np.uint8)
	alpha[keep] = 255
	out = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
	bbox = out.getbbox()
	cropped = out.crop(bbox)
	side = max(cropped.size)
	sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
	sq.paste(cropped, ((side - cropped.size[0]) // 2, (side - cropped.size[1]) // 2), cropped)
	mask = Image.new("L", (side, side), 0)
	ImageDraw.Draw(mask).ellipse([1, 1, side - 2, side - 2], fill=255)
	mask = mask.filter(ImageFilter.GaussianBlur(0.8))
	r, g, b, a = sq.split()
	circ = Image.merge("RGBA", (r, g, b, ImageChops.multiply(a, mask)))
	os.makedirs(DST, exist_ok=True)
	circ.resize((OUT, OUT), Image.Resampling.LANCZOS).save(os.path.join(DST, f"{name}.png"))
	print(name, OUT)


if __name__ == "__main__":
	for n in NAMES:
		process(n)
