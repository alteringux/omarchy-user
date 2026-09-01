#!/usr/bin/env python3
"""Generate Siren Ink tattoo-flash wallpapers as SVG, then rasterize with rsvg-convert.

Style: luminous "ink on dark skin" -- bold blush linework with crimson / rose /
gold / aged-teal fills, American-traditional motifs, soft vignette. Not photoreal;
hand-authored flash art in the theme palette.
"""
import subprocess
import textwrap
from pathlib import Path

W, H = 2560, 1440
HERE = Path(__file__).parent

# Siren Ink palette
BG0 = "#1c1216"
BG1 = "#0b0708"
LINE = "#f1dedf"      # blush linework (the "needle" line)
LINE_D = "#c9a9ac"    # dimmer line for interior detail
INK = "#c8203f"       # oxblood crimson
ROSE = "#e072a5"      # lipstick rose
GOLD = "#d9a441"      # gilded flash
TEAL = "#4f9d8a"      # aged blue-green
SHADOW = "#5a2230"    # deep wine shading

DEFS = f"""
  <defs>
    <radialGradient id="skin" cx="50%" cy="42%" r="75%">
      <stop offset="0%" stop-color="{BG0}"/>
      <stop offset="100%" stop-color="{BG1}"/>
    </radialGradient>
    <radialGradient id="vig" cx="50%" cy="50%" r="70%">
      <stop offset="55%" stop-color="#000000" stop-opacity="0"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.78"/>
    </radialGradient>
    <filter id="glow" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="6" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="softglow" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="18"/>
    </filter>
  </defs>
"""

def frame(inner, glow_color=INK):
    return textwrap.dedent(f"""\
    <svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
    {DEFS}
      <rect width="{W}" height="{H}" fill="url(#skin)"/>
      <ellipse cx="{W/2}" cy="{H*0.46}" rx="620" ry="620" fill="{glow_color}" opacity="0.16" filter="url(#softglow)"/>
      <g stroke-linecap="round" stroke-linejoin="round">
    {inner}
      </g>
      <rect width="{W}" height="{H}" fill="url(#vig)"/>
    </svg>
    """)


def rose():
    """Classic traditional rose, centered."""
    cx, cy = W/2, H*0.46
    g = f'<g transform="translate({cx},{cy}) scale(1.9)" filter="url(#glow)">'
    # outer petals (crimson) built from overlapping arcs
    g += f'''
      <path d="M0,-70 C 55,-92 108,-52 96,6 C 140,20 132,86 76,96
               C 70,140 -6,150 -34,104 C -92,120 -140,60 -110,8
               C -150,-40 -104,-100 -46,-80 C -34,-118 40,-116 0,-70 Z"
            fill="{INK}" stroke="{LINE}" stroke-width="5"/>
    '''
    # mid petals (rose)
    g += f'''
      <path d="M0,-40 C 34,-54 66,-28 58,6 C 84,16 78,54 44,60
               C 40,86 -4,92 -22,62 C -56,72 -84,36 -66,4
               C -90,-22 -62,-60 -28,-46 C -20,-72 24,-70 0,-40 Z"
            fill="{ROSE}" stroke="{LINE}" stroke-width="4"/>
    '''
    # bud spiral centre
    g += f'''
      <path d="M-4,26 C -30,22 -34,-14 -8,-22 C 16,-30 34,-6 26,14
               C 20,30 -2,34 -8,18 C -12,6 4,0 10,10"
            fill="{SHADOW}" stroke="{LINE}" stroke-width="4"/>
      <path d="M-2,10 C -14,8 -16,-8 -2,-12 C 10,-15 18,-2 12,8"
            fill="none" stroke="{LINE}" stroke-width="3.5"/>
    '''
    # sepals / stem
    g += f'''
      <path d="M-96,96 C -120,150 -120,210 -150,250" fill="none" stroke="{LINE}" stroke-width="6"/>
      <path d="M0,150 C -10,210 -10,250 -30,300" fill="none" stroke="{LINE}" stroke-width="6"/>
      <path d="M0,150 C -8,200 6,240 40,262 C 8,244 -2,206 0,150 Z" fill="{TEAL}" stroke="{LINE}" stroke-width="4.5"/>
      <path d="M-150,250 C -120,240 -96,258 -86,292 C -120,288 -150,300 -150,250 Z" fill="{TEAL}" stroke="{LINE}" stroke-width="4.5"/>
      <path d="M-30,300 C 6,286 44,300 58,338 C 18,332 -18,346 -30,300 Z" fill="{TEAL}" stroke="{LINE}" stroke-width="4.5"/>
    '''
    # drips
    g += f'<circle cx="120" cy="150" r="6" fill="{INK}"/><circle cx="140" cy="180" r="4" fill="{INK}"/>'
    g += "</g>"
    return frame(g, INK)


def dagger_serpent():
    """Dagger with a serpent coiled around the blade."""
    cx, cy = W/2, H*0.5
    g = f'<g transform="translate({cx},{cy}) scale(1.15)" filter="url(#glow)">'
    # blade
    g += f'''
      <path d="M0,-300 L 26,-210 L 20,150 L 0,190 L -20,150 L -26,-210 Z"
            fill="{LINE_D}" stroke="{LINE}" stroke-width="5"/>
      <path d="M0,-292 L 0,180" stroke="{LINE}" stroke-width="3" opacity="0.6"/>
    '''
    # guard
    g += f'''
      <path d="M-120,-210 C -60,-236 60,-236 120,-210 C 60,-190 -60,-190 -120,-210 Z"
            fill="{GOLD}" stroke="{LINE}" stroke-width="5"/>
    '''
    # grip + pommel
    g += f'''
      <rect x="-20" y="-206" width="40" height="150" rx="10" fill="{SHADOW}" stroke="{LINE}" stroke-width="5"/>
      <path d="M-20,-186 h40 M-20,-156 h40 M-20,-126 h40 M-20,-96 h40" stroke="{LINE}" stroke-width="3" opacity="0.7"/>
      <circle cx="0" cy="-40" r="26" fill="{GOLD}" stroke="{LINE}" stroke-width="5"/>
      <circle cx="0" cy="-40" r="10" fill="{INK}"/>
    '''
    # serpent coiled around blade
    g += f'''
      <path d="M-70,-150 C -140,-110 -120,-40 -30,-30 C 70,-18 120,-70 60,-120
               C 10,-160 -20,-120 -40,-90 C -60,-58 -20,-30 20,-44
               C 60,-58 60,120 -10,150 C -80,180 -120,120 -70,70"
            fill="none" stroke="{TEAL}" stroke-width="30"/>
      <path d="M-70,-150 C -140,-110 -120,-40 -30,-30 C 70,-18 120,-70 60,-120
               C 10,-160 -20,-120 -40,-90 C -60,-58 -20,-30 20,-44
               C 60,-58 60,120 -10,150 C -80,180 -120,120 -70,70"
            fill="none" stroke="{LINE}" stroke-width="5"/>
      <path d="M-70,70 C -84,58 -84,40 -74,26" fill="none" stroke="{TEAL}" stroke-width="24"/>
      <path d="M-70,70 C -84,58 -84,40 -74,26" fill="none" stroke="{LINE}" stroke-width="5"/>
      <!-- head -->
      <path d="M-74,26 C -96,20 -104,-8 -84,-20 C -64,-30 -44,-14 -50,8 C -54,24 -66,30 -74,26 Z"
            fill="{TEAL}" stroke="{LINE}" stroke-width="5"/>
      <circle cx="-78" cy="-6" r="4.5" fill="{INK}"/>
      <path d="M-84,-20 C -92,-30 -100,-30 -108,-24 M-84,-16 C -94,-20 -104,-16 -110,-8"
            fill="none" stroke="{INK}" stroke-width="4"/>
    '''
    # blood drops
    g += f'<path d="M0,190 C 8,220 8,236 0,250 C -8,236 -8,220 0,190 Z" fill="{INK}" stroke="{LINE}" stroke-width="3"/>'
    g += f'<circle cx="34" cy="238" r="7" fill="{INK}"/><circle cx="-30" cy="262" r="5" fill="{INK}"/>'
    g += "</g>"
    return frame(g, TEAL)


def heart_banner():
    """Flaming heart with a scroll banner -- the seductive centerpiece."""
    cx, cy = W/2, H*0.44
    g = f'<g transform="translate({cx},{cy}) scale(1.6)" filter="url(#glow)">'
    # flames behind
    g += f'''
      <path d="M0,-140 C 40,-190 30,-230 60,-260 C 54,-210 90,-200 84,-150
               C 120,-180 118,-140 96,-110 C 60,-70 -60,-70 -96,-110
               C -118,-140 -120,-180 -84,-150 C -90,-200 -54,-210 -60,-260
               C -30,-230 -40,-190 0,-140 Z"
            fill="{GOLD}" stroke="{LINE}" stroke-width="4" opacity="0.9"/>
    '''
    # heart
    g += f'''
      <path d="M0,-90 C 0,-140 -70,-160 -110,-120 C -150,-80 -140,-20 0,110
               C 140,-20 150,-80 110,-120 C 70,-160 0,-140 0,-90 Z"
            fill="{INK}" stroke="{LINE}" stroke-width="6"/>
      <path d="M-64,-96 C -92,-96 -104,-64 -96,-40" fill="none" stroke="{ROSE}" stroke-width="8"/>
    '''
    # banner scroll across
    g += f'''
      <path d="M-210,20 C -180,-2 -120,-2 -90,20 C -60,42 60,42 90,20
               C 120,-2 180,-2 210,20 C 180,42 120,42 90,20
               C 60,-2 -60,-2 -90,20 C -120,42 -180,42 -210,20 Z"
            fill="{SHADOW}" stroke="{LINE}" stroke-width="5"/>
      <path d="M-210,20 L -244,4 L -232,44 Z" fill="{SHADOW}" stroke="{LINE}" stroke-width="5"/>
      <path d="M210,20 L 244,4 L 232,44 Z" fill="{SHADOW}" stroke="{LINE}" stroke-width="5"/>
      <text x="0" y="30" text-anchor="middle" font-family="Noto Serif, Georgia, serif"
            font-size="34" font-style="italic" fill="{LINE}">seductive</text>
    '''
    g += "</g>"
    return frame(g, INK)


def flash_sheet():
    """Repeated small motifs, flash-sheet grid."""
    g = ""
    motifs = []
    # a swallow
    motifs.append(f'''<g><path d="M-46,0 C -20,-26 20,-26 46,-4 C 20,-14 24,10 46,18
        C 10,22 -6,6 -12,-6 C -20,10 -40,16 -60,10 C -44,4 -44,-2 -46,0 Z"
        fill="{TEAL}" stroke="{LINE}" stroke-width="4"/>
        <path d="M-12,-6 L -8,26 L 6,10" fill="{INK}" stroke="{LINE}" stroke-width="4"/></g>''')
    # lips
    motifs.append(f'''<g><path d="M-44,0 C -30,-16 -12,-14 0,-6 C 12,-14 30,-16 44,0
        C 30,20 12,26 0,26 C -12,26 -30,20 -44,0 Z" fill="{ROSE}" stroke="{LINE}" stroke-width="4"/>
        <path d="M-44,0 C -20,8 20,8 44,0" fill="none" stroke="{LINE}" stroke-width="3.5"/></g>''')
    # anchor
    motifs.append(f'''<g><circle cx="0" cy="-34" r="10" fill="none" stroke="{LINE}" stroke-width="5"/>
        <path d="M0,-24 L 0,34 M-26,4 h52 M-38,20 C -30,44 30,44 38,20"
        fill="none" stroke="{LINE}" stroke-width="5"/><path d="M-38,20 l -8,-4 M38,20 l 8,-4" stroke="{GOLD}" stroke-width="5"/></g>''')
    # star / sparkle
    motifs.append(f'''<g><path d="M0,-40 L 10,-10 L 40,0 L 10,10 L 0,40 L -10,10 L -40,0 L -10,-10 Z"
        fill="{GOLD}" stroke="{LINE}" stroke-width="4"/></g>''')
    # dagger tiny
    motifs.append(f'''<g><path d="M0,-40 L 6,-14 L 4,30 L 0,40 L -4,30 L -6,-14 Z" fill="{LINE_D}" stroke="{LINE}" stroke-width="4"/>
        <path d="M-20,-14 h40" stroke="{GOLD}" stroke-width="6"/></g>''')
    # heart tiny
    motifs.append(f'''<g><path d="M0,-8 C 0,-24 -20,-28 -30,-16 C -40,-4 -30,12 0,34
        C 30,12 40,-4 30,-16 C 20,-28 0,-24 0,-8 Z" fill="{INK}" stroke="{LINE}" stroke-width="4"/></g>''')

    cols, rows = 6, 4
    dx, dy = W / cols, H / rows
    idx = 0
    for r in range(rows):
        for c in range(cols):
            m = motifs[idx % len(motifs)]
            idx += 1
            x = dx * (c + 0.5)
            y = dy * (r + 0.5)
            rot = (idx * 37) % 40 - 20
            g += f'<g transform="translate({x:.0f},{y:.0f}) rotate({rot}) scale(1.35)" filter="url(#glow)">{m}</g>\n'
    return frame(g, ROSE)


BUILDS = {
    "1-rose": rose,
    "2-dagger-serpent": dagger_serpent,
    "3-flaming-heart": heart_banner,
    "4-flash-sheet": flash_sheet,
}

for name, fn in BUILDS.items():
    svg = HERE / f"{name}.svg"
    png = HERE / f"{name}.jpg"
    svg.write_text(fn())
    subprocess.run(
        ["rsvg-convert", "-w", str(W), "-h", str(H), "-f", "png", "-o", str(png.with_suffix(".png")), str(svg)],
        check=True,
    )
    subprocess.run(
        ["magick", str(png.with_suffix(".png")), "-quality", "92", str(png)],
        check=True,
    )
    png.with_suffix(".png").unlink()
    svg.unlink()
    print("wrote", png.name)
