#!/usr/bin/env python3
"""Rebuild WWII Tales unit PNGs from assets/*.jpg.

Uses edge-connected flood-fill for charcoal backgrounds, with a protected
subject core so dark uniform/track pixels are not erased. Crops tightly and
writes natural-aspect PNGs into processed/.
"""
from __future__ import annotations

from collections import deque
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets")
DST = os.path.join(ROOT, "processed")
MAX_SIDE = 192


def rebuild(name: str, tol: float) -> None:
	rgb = np.array(Image.open(os.path.join(SRC, f"unit-{name}.jpg")).convert("RGB"))
	h, w, _ = rgb.shape
	edge = np.concatenate(
		[
			rgb[:8].reshape(-1, 3),
			rgb[-8:].reshape(-1, 3),
			rgb[:, :8].reshape(-1, 3),
			rgb[:, -8:].reshape(-1, 3),
		],
		axis=0,
	)
	bg = np.median(edge, axis=0).astype(np.float32)
	dist = np.linalg.norm(rgb.astype(np.float32) - bg, axis=2)
	chroma = rgb.max(2).astype(np.float32) - rgb.min(2).astype(np.float32)

	core = (dist > (tol + 8.0)) | ((chroma > 12) & (dist > 10))
	protect_img = Image.fromarray((core.astype(np.uint8) * 255))
	protect_img = protect_img.filter(ImageFilter.MaxFilter(7))
	protect_img = protect_img.filter(ImageFilter.MaxFilter(7))
	protected = np.array(protect_img) > 127

	cand = (dist <= tol) & (~protected)
	vis = np.zeros((h, w), dtype=bool)
	q: deque = deque()
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

	subject = (~vis) | core
	keep_zone = (
		np.array(
			Image.fromarray((core.astype(np.uint8) * 255))
			.filter(ImageFilter.MaxFilter(11))
			.filter(ImageFilter.MaxFilter(11))
		)
		> 127
	)
	subject = subject & (keep_zone | (dist > tol * 0.85) | (chroma > 10))

	img = Image.fromarray((subject.astype(np.uint8) * 255))
	img = img.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
	subject = np.array(img) > 127

	seen = np.zeros((h, w), dtype=bool)
	best: list = []
	for y in range(h):
		for x in range(w):
			if not subject[y, x] or seen[y, x]:
				continue
			qq: deque = deque([(y, x)])
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
	sub2 = np.zeros((h, w), dtype=bool)
	for y, x in best:
		sub2[y, x] = True
	subject = sub2

	alpha = np.zeros((h, w), np.float32)
	alpha[subject] = 255.0
	d1 = np.array(Image.fromarray((subject.astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(3))) > 127
	rim = d1 & ~subject
	alpha[rim & (dist <= tol + 6)] = 120.0

	out = Image.fromarray(np.dstack([rgb, alpha.astype(np.uint8)]), "RGBA")
	bbox = out.getbbox()
	pad = 3
	cropped = out.crop(
		(
			max(0, bbox[0] - pad),
			max(0, bbox[1] - pad),
			min(w, bbox[2] + pad),
			min(h, bbox[3] + pad),
		)
	)
	cw, ch = cropped.size
	scale = MAX_SIDE / max(cw, ch)
	nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
	resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
	os.makedirs(DST, exist_ok=True)
	path = os.path.join(DST, f"unit-{name}.png")
	resized.save(path)
	print(f"{name}: {cropped.size} -> {resized.size} -> {path}")


if __name__ == "__main__":
	for n, t in [
		("infantry", 28.0), ("armor", 30.0), ("artillery", 28.0),
		("recon", 28.0), ("antitank", 28.0), ("engineer", 28.0), ("halftrack", 30.0),
	]:
		rebuild(n, t)
