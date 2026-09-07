-- Change the default Omarchy look'n'feel.
--
-- This file loads AFTER Omarchy's defaults AND after the current theme's
-- hyprland.lua, so anything set here wins on every theme. Comment the
-- "LIQUID ANIMATIONS" block below to hand animation control back to the theme.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#variables
hl.config({
  general = {
    -- Animate tiling adjustments instead of snapping.
    resize_on_border = true,
  },

  decoration = {
    -- Gel/glass look on every theme.
    rounding = 10,
    active_opacity = 1.0,
    -- Was 0.96. Translucent unfocused windows force an alpha blend + blur-behind
    -- every frame and disable occlusion culling, for a barely-visible effect.
    inactive_opacity = 1.0,

    blur = {
      enabled = true,
      size = 6,
      passes = 3,
      new_optimizations = true,
      ignore_opacity = true,
      xray = false,
      vibrancy = 0.25,
      vibrancy_darkness = 0.1,
      noise = 0.012,
      -- Blur the workspace left behind when a special workspace slides over it.
      special = true,
    },

    shadow = {
      enabled = true,
      range = 24,
      render_power = 3,
      color = "rgba(00000055)",
      color_inactive = "rgba(00000033)",
      scale = 1.0,
    },
  },

  misc = {
    -- The actual new behaviour: fluid drag + manual resize.
    animate_manual_resizes = true,
    animate_mouse_windowdragging = true,
  },
})

------------------------------------------------------------------------
-- LIQUID ANIMATIONS
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
------------------------------------------------------------------------

-- Silky overshoot, springy bounce, and a plain linear curve for the
-- looping gradient border. Named `liquid*` so they never collide with a
-- theme's own bezier names.
hl.curve("liquid",        { type = "bezier", points = { { 0.05, 0.9 },  { 0.1, 1.10 } } })
hl.curve("liquidDecel",   { type = "bezier", points = { { 0.16, 1 },    { 0.3, 1 } } })
hl.curve("liquidBounce",  { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1 } } })
hl.curve("liquidLinear",  { type = "bezier", points = { { 0, 0 },       { 1, 1 } } })

-- Global multiplier for every unspecified leaf.
hl.animation({ leaf = "global", enabled = true, speed = 7, bezier = "liquid" })

-- Windows: bounce on open/move, gentle overshoot in, quick out.
hl.animation({ leaf = "windows",     enabled = true, speed = 6,   bezier = "liquidBounce" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 6,   bezier = "liquid",       style = "popin 70%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 5,   bezier = "liquidDecel",  style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6,   bezier = "liquidBounce" })

-- Borders: quick colour catch-up. The spinning gradient (borderangle + style=loop)
-- is disabled: a looping animation keeps the screen dirty every frame, so VFR can
-- never drop the render rate and Hyprland burns ~1 core at idle forever.
hl.animation({ leaf = "border",      enabled = true, speed = 8,   bezier = "liquidDecel" })
hl.animation({ leaf = "borderangle", enabled = false, speed = 40,  bezier = "liquidLinear", style = "loop" })

-- Fades.
hl.animation({ leaf = "fade",       enabled = true, speed = 7, bezier = "liquidDecel" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 6, bezier = "liquidLinear" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 5, bezier = "liquidLinear" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 5, bezier = "liquidDecel" })

-- Layer surfaces: menus, launcher, notifications, OSD.
hl.animation({ leaf = "layers",        enabled = true, speed = 6, bezier = "liquid",      style = "slide" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 6, bezier = "liquid",      style = "slide" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 5, bezier = "liquidDecel", style = "slide" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 6, bezier = "liquidLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 5, bezier = "liquidLinear" })

-- Workspaces slide with the springy curve.
hl.animation({ leaf = "workspaces",       enabled = true, speed = 6, bezier = "liquidBounce", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 6, bezier = "liquidBounce", style = "slidevert" })
