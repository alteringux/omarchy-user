-- GTA VI — Vice City neon. Loaded after Omarchy's default looknfeel, so this
-- file owns the "intense, lots of animations" personality of the theme.
-- Switch to any other theme to get the calm Omarchy defaults back.

local neon_gradient = {
  colors = {
    "rgba(ff2d95ee)", -- Miami pink
    "rgba(c04bffee)", -- neon purple
    "rgba(00e5ffee)", -- electric teal
    "rgba(ff7a1aee)", -- sunset orange
    "rgba(ffd23fee)", -- gold
  },
  angle = 45,
}

local inactive_border_color = "rgba(5b2a6baa)"

hl.config({
  general = {
    border_size = 3,
    gaps_in = 4,
    gaps_out = 12,
    col = {
      active_border = neon_gradient,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = neon_gradient,
      border_inactive = inactive_border_color,
    },
    groupbar = {
      gradients = true,
      text_color = "rgb(ffffff)",
      col = {
        active = "rgba(ff2d9555)",
        inactive = "rgba(12021f55)",
      },
    },
  },

  decoration = {
    rounding = 10,
    active_opacity = 1.0,
    inactive_opacity = 0.92,
    dim_inactive = true,
    dim_strength = 0.28,

    blur = {
      enabled = true,
      size = 6,
      passes = 3,
      new_optimizations = true,
      xray = false,
      vibrancy = 0.35,
      vibrancy_darkness = 0.1,
      brightness = 1.0,
      noise = 0.015,
    },

    shadow = {
      enabled = true,
      range = 30,
      render_power = 3,
      color = "rgba(ff2d95bb)",
      color_inactive = "rgba(06000999)",
      scale = 1.0,
    },
  },

  animations = {
    enabled = true,
  },
})

-- Punchy, overshooting curves for a game-menu feel.
hl.curve("gtaOvershoot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.15 } } })
hl.curve("gtaSnap", { type = "bezier", points = { { 0.19, 1 }, { 0.22, 1 } } })
hl.curve("gtaBounce", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1 } } })
hl.curve("gtaLinear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })

-- Continuously spinning neon gradient border.
hl.animation({ leaf = "borderangle", enabled = true, speed = 40, bezier = "gtaLinear", style = "loop" })

hl.animation({ leaf = "global", enabled = true, speed = 7, bezier = "gtaOvershoot" })
hl.animation({ leaf = "border", enabled = true, speed = 8, bezier = "gtaSnap" })
hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "gtaBounce" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "gtaOvershoot", style = "popin 70%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "gtaSnap", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, bezier = "gtaBounce" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "gtaSnap" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 6, bezier = "gtaLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 5, bezier = "gtaLinear" })
hl.animation({ leaf = "layers", enabled = true, speed = 6, bezier = "gtaOvershoot", style = "slide" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 6, bezier = "gtaOvershoot", style = "slide" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 5, bezier = "gtaSnap", style = "slide" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 6, bezier = "gtaLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 5, bezier = "gtaLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "gtaBounce", style = "slidefade 20%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 6, bezier = "gtaBounce", style = "slidevert" })
