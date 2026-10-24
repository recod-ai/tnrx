#!/usr/bin/env python3
"""Gera os ícones da extensão a partir do logo do recod.ai: o hipercubo (tesseract)
projetado no plano, com as quatro direções ajustadas aos vértices do logo.

  media/tnrx.svg  barra de atividades: monocromático (o VS Code só usa a forma, a cor vem do tema)
  media/icon.png  página da extensão: colorido, 256x256, fundo branco arredondado (precisa do ImageMagick)

Uso (na pasta vscode/):  python3 tools/recod-icon.py
"""

import itertools
import subprocess
import tempfile
from pathlib import Path

MEDIA = Path(__file__).resolve().parent.parent / "media"
# Projeção de cada eixo do 4-cubo, em px do logo de 400px; o logo não é simétrico, nem isto.
DIRS = [(20, -56), (90, -55.5), (80, 55.5), (30, 56)]
VERTS = list(itertools.product((-1, 1), repeat=4))
POS = {v: (sum(s * d[0] for s, d in zip(v, DIRS)), sum(s * d[1] for s, d in zip(v, DIRS))) for v in VERTS}
EDGES = [(a, b) for a, b in itertools.combinations(VERTS, 2) if sum(x != y for x, y in zip(a, b)) == 1]
# Os dois vértices do meio; três arestas de cada (todas menos a do quarto eixo) são coloridas no logo.
ORANGE, RED = (1, -1, 1, -1), (-1, 1, -1, 1)
COLORS = {None: "#231f20", "orange": "#f2885f", "red": "#e0193a"}


def color(edge):
    if next(k for k in range(4) if edge[0][k] != edge[1][k]) == 3:
        return None
    return "orange" if ORANGE in edge else "red" if RED in edge else None


def svg(size, pad, stroke_width, colored):
    radius = max(max(abs(x), abs(y)) for x, y in POS.values())
    scale = (size / 2 - pad) / radius
    point = lambda v: f"{size / 2 + POS[v][0] * scale:.2f} {size / 2 + POS[v][1] * scale:.2f}"
    groups = {}
    for edge in EDGES:
        groups.setdefault(color(edge) if colored else None, []).append(f"M{point(edge[0])}L{point(edge[1])}")
    # as arestas pretas primeiro, as coloridas por cima
    paths = "".join(
        f'<path stroke="{COLORS[k] if colored else "currentColor"}" d="{" ".join(d)}"/>'
        for k, d in sorted(groups.items(), key=lambda kv: kv[0] is not None)
    )
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}" '
            f'fill="none" stroke-width="{stroke_width}" stroke-linecap="round" stroke-linejoin="round">{paths}</svg>\n')


def main():
    (MEDIA / "tnrx.svg").write_text(svg(24, 1.2, 0.8, colored=False))
    with tempfile.TemporaryDirectory() as tmp:
        fg, bg = Path(tmp) / "fg.svg", Path(tmp) / "bg.png"
        fg.write_text(svg(256, 18, 5, colored=True))
        subprocess.run(["magick", "-size", "256x256", "xc:none", "-fill", "white",
                        "-draw", "roundrectangle 0,0 255,255 40,40", str(bg)], check=True)
        subprocess.run(["magick", str(bg), "-colorspace", "sRGB", "-type", "TrueColorAlpha",
                        "(", "-background", "none", "-density", "96", str(fg), ")",
                        "-gravity", "center", "-composite", f"PNG32:{MEDIA / 'icon.png'}"], check=True)
    print("media/tnrx.svg e media/icon.png gerados")


if __name__ == "__main__":
    main()
