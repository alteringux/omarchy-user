-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
  input = {
    -- Increase sensitivity for mouse/trackpad (range -1.0 to 1.0, default: 0).
    sensitivity = 0.5,

    -- Slow down + smooth out wheel/mouse scrolling everywhere (default: 1.0).
    scroll_factor = 0.5,

    touchpad = {
      -- Smaller = finer, less jumpy two-finger scroll everywhere
      -- (Omarchy default is 0.4). Nudge up toward 0.4 if pages feel too slow.
      scroll_factor = 0.2,
    },
  },
})

-- App-specific touchpad scroll speeds. These override Omarchy's defaults
-- (which make terminals scroll faster at 1.5) so terminals match the
-- calmer global feel too.
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 0.6 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })
