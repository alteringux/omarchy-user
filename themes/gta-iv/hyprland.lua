-- GTA IV — Liberty City industrial grit. Loaded after Omarchy's default
-- looknfeel, so this file owns the "tense, hard-edged" personality of the theme.
-- Switch to any other theme to get the calm Omarchy defaults back.

local gunk_gradient = {
  colors = {
    "rgba(6b8f4aee)", -- olive drab
    "rgba(8b7d3bee)", -- drab moss
    "rgba(7a6e3cee)", -- gunmetal green
    "rgba(5c6b3bee)", -- steel olive
  },
  angle = 135,
}

local inactive_border_color = "rgba(4a5a3aaa)"

hl.config({
  general = {
    border_size = 2,
    gaps_in = 5,
    gaps_out = 14,
    col = {
      active_border = gunk_gradient,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = gunk_gradient,
      border_inactive = inactive_border_color,
    },
    groupbar = {
      gradients = false,
      text_color = "rgb(c4cbb6)",
      col = {
        active = "rgba(6b8f4a55)",
        inactive = "rgba(0f120d55)",
      },
    },
  },

  decoration = {
    rounding = 6,
    active_opacity = 1.0,
    inactive_opacity = 0.88,
    dim_inactive = true,
    dim_strength = 0.35,

    blur = {
      enabled = true,
      size = 4,
      passes = 2,
      new_optimizations = true,
      xray = false,
      vibrancy = 0.15,
      vibrancy_darkness = 0.2,
      brightness = 0.95,
      noise = 0.025,
    },

    shadow = {
      enabled = true,
      range = 20,
      render_power = 2,
      color = "rgba(0a0c08cc)",
      color_inactive = "rgba(05060488)",
      scale = 1.0,
    },
  },

  animations = {
    enabled = true,
  },
})

-- Stiffer, industrial curves — no bounce, no overshoot.
hl.curve("gtaLinear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("gtaSnap", { type = "bezier", points = { { 0.19, 1 }, { 0.22, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 5, bezier = "gtaLinear" })
hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "gtaSnap" })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "gtaLinear" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "gtaLinear", style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "gtaSnap", style = "popin 85%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "gtaLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "gtaSnap" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 5, bezier = "gtaLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 4, bezier = "gtaLinear" })
hl.animation({ leaf = "layers", enabled = true, speed = 5, bezier = "gtaLinear", style = "slide" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 5, bezier = "gtaLinear", style = "slide" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 4, bezier = "gtaSnap", style = "slide" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 5, bezier = "gtaLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 4, bezier = "gtaLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "gtaSnap", style = "slidefade 15%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "gtaLinear", style = "slidevert" })
