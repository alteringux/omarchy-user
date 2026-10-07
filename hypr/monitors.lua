-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1.25

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Fallback for any monitor not matched below.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Left: Dell S2721DS, portrait. transform 3 = 90 deg clockwise (panel top edge
-- ends up on the right). Logical size after rotate + scale: 1152 x 2048.
hl.monitor({ output = "DP-3", mode = "preferred", position = "0x0", scale = 1.25, transform = 3 })

-- Center: built-in Apple panel. Logical size after scale: 2048 x 1280.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "1152x0", scale = 1.25 })

-- Right ("top right"): Dell S2721DGF, top-aligned with the laptop.
-- NOTE: this link maxes out at 1280x1024 - anything higher (1440p, even 1080p)
-- fails to modeset and falls back. That is a cable/adapter bandwidth limit on
-- this output, not a config problem. Swap the cable / TB3 adapter to go higher.
hl.monitor({ output = "DP-4", mode = "1280x1024@75", position = "3200x0", scale = 1 })
