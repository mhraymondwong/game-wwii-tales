#!/usr/bin/env python3
"""Process assets/ui/*.jpg → assets/ui/processed/*.png (black bg → alpha)."""
from collections import deque
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "ui")
DST = os.path.join(SRC, "processed")
NAMES = [
	"logo", "btn-start", "btn-howto", "btn-quit",
	"btn-buy-infantry", "btn-buy-armor", "btn-buy-artillery",
	"btn-buy-recon", "btn-buy-antitank", "btn-buy-engineer", "btn-buy-halftrack",
	"btn-end-buy", "btn-end-turn", "btn-replay", "btn-back", "btn-return",
	"hud-panel",
]


def _flood_bg(rgb: np.ndarray, tol: float) -> np.ndarray:
	h, w, _ = rgb.shape
	mx = rgb.max(axis=2)
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
	return vis


def _components(mask: np.ndarray):
	h, w = mask.shape
	seen = np.zeros((h, w), dtype=bool)
	comps = []
	for y in range(h):
		for x in range(w):
			if not mask[y, x] or seen[y, x]:
				continue
			q = deque([(y, x)])
			seen[y, x] = True
			cells = [(y, x)]
			while q:
				cy, cx = q.popleft()
				for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
					ny, nx = cy + dy, cx + dx
					if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
						seen[ny, nx] = True
						q.append((ny, nx))
						cells.append((ny, nx))
			comps.append(cells)
	comps.sort(key=len, reverse=True)
	return comps


def process(name: str, tol: float = 18.0) -> None:
	rgb = np.array(Image.open(os.path.join(SRC, f"{name}.jpg")).convert("RGB"))
	h, w, _ = rgb.shape
	vis = _flood_bg(rgb, tol)
	subject = ~vis
	img = Image.fromarray((subject.astype(np.uint8) * 255))
	img = img.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
	subject = np.array(img) > 127
	comps = _components(subject)
	keep = np.zeros((h, w), dtype=bool)
	if name == "logo":
		# Keep plaque + disconnected subtitle letters + gold line (all sizable, centered)
		min_size = 80
		largest = comps[0]
		lx = [c[1] for c in largest]
		ly = [c[0] for c in largest]
		cx0, cx1 = min(lx), max(lx)
		cy0 = min(ly)
		mid_x = 0.5 * (cx0 + cx1)
		for cells in comps:
			if len(cells) < min_size:
				continue
			xs = [c[1] for c in cells]
			ys = [c[0] for c in cells]
			ccx = 0.5 * (min(xs) + max(xs))
			if cells is largest or (abs(ccx - mid_x) < (cx1 - cx0) * 0.35 and min(ys) >= cy0 - 20):
				for y, x in cells:
					keep[y, x] = True
	else:
		for y, x in comps[0]:
			keep[y, x] = True
	alpha = np.zeros((h, w), np.uint8)
	alpha[keep] = 255
	d1 = np.array(Image.fromarray((keep.astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(3))) > 127
	alpha[d1 & ~keep] = 160
	out = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
	bbox = out.getbbox()
	pad = 4 if name == "logo" else 2
	cropped = out.crop(
		(
			max(0, bbox[0] - pad),
			max(0, bbox[1] - pad),
			min(w, bbox[2] + pad),
			min(h, bbox[3] + pad),
		)
	)
	cw, ch = cropped.size
	if name == "logo":
		max_h, max_w = 220, 560
	elif name == "hud-panel":
		max_h, max_w = 420, 280
	else:
		max_h, max_w = 72, 280
	scale = min(max_h / ch, max_w / cw, 1.0)
	if max(cw, ch) > 400:
		scale = min(max_h / ch, max_w / cw)
	nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
	resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
	os.makedirs(DST, exist_ok=True)
	resized.save(os.path.join(DST, f"{name}.png"))
	print(name, resized.size)


if __name__ == "__main__":
	for n in NAMES:
		process(n)
