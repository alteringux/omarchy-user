.pragma library

var _contrastCache = Object.create(null)

function _channel(value) { return Math.max(0, Math.min(1, value)) }

function _rgb(color) {
  return [_channel(color.r), _channel(color.g), _channel(color.b), _channel(color.a)]
}

function _snap(value) { return Math.round(_channel(value) * 5) / 5 }

function _byte(value) { return Math.round(_channel(value) * 255).toString(16).padStart(2, "0") }

function _hex(r, g, b, a) {
  return "#" + _byte(a) + _byte(r) + _byte(g) + _byte(b)
}

function webSafeColor(color) {
  return _hex(_snap(color.r), _snap(color.g), _snap(color.b), color.a)
}

function alphaColor(color, alpha) {
  return _hex(_snap(color.r), _snap(color.g), _snap(color.b), alpha)
}

function _composite(color, surface) {
  var alpha = _channel(color[3])
  return [color[0] * alpha + surface[0] * (1 - alpha),
          color[1] * alpha + surface[1] * (1 - alpha),
          color[2] * alpha + surface[2] * (1 - alpha), 1]
}

function _linear(channel) {
  return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function _luminance(color) {
  return 0.2126 * _linear(color[0]) + 0.7152 * _linear(color[1]) + 0.0722 * _linear(color[2])
}

function contrastRatio(foreground, surface, background) {
  var white = [1, 1, 1, 1]
  var base = background === undefined ? white : _composite(_rgb(background), white)
  var visibleSurface = _composite(_rgb(surface), base)
  var visibleForeground = _composite(_rgb(foreground), visibleSurface)
  var first = _luminance(visibleForeground)
  var second = _luminance(visibleSurface)
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
}

function contrastColorFor(preferred, surface, minimum, background) {
  var threshold = minimum === undefined ? 4.5 : Number(minimum)
  if (!isFinite(threshold) || threshold < 1) threshold = 4.5

  var target = _rgb(preferred).slice(0, 3).map(_snap)
  var whiteBackdrop = [1, 1, 1, 1]
  var base = background === undefined ? whiteBackdrop : _composite(_rgb(background), whiteBackdrop)
  var compositeSurface = _composite(_rgb(surface), base)
  var key = [target[0], target[1], target[2], compositeSurface[0], compositeSurface[1],
             compositeSurface[2], threshold].join(":")
  if (_contrastCache[key]) return _contrastCache[key]

  var best = null
  var bestDistance = Number.POSITIVE_INFINITY
  var surfaceLuminance = _luminance(compositeSurface)
  for (var ri = 0; ri < 6; ri++) {
    var r = ri / 5
    for (var gi = 0; gi < 6; gi++) {
      var g = gi / 5
      for (var bi = 0; bi < 6; bi++) {
        var b = bi / 5
        var candidate = [r, g, b, 1]
        var candidateLuminance = _luminance(candidate)
        var contrast = (Math.max(candidateLuminance, surfaceLuminance) + 0.05)
          / (Math.min(candidateLuminance, surfaceLuminance) + 0.05)
        if (contrast < threshold) continue
        var distance = Math.pow(r - target[0], 2) + Math.pow(g - target[1], 2)
          + Math.pow(b - target[2], 2)
        if (distance < bestDistance) {
          best = candidate
          bestDistance = distance
        }
      }
    }
  }

  if (!best) {
    var black = [0, 0, 0, 1]
    var white = [1, 1, 1, 1]
    best = (Math.max(_luminance(black), surfaceLuminance) + 0.05)
      / (Math.min(_luminance(black), surfaceLuminance) + 0.05)
      >= (Math.max(_luminance(white), surfaceLuminance) + 0.05)
      / (Math.min(_luminance(white), surfaceLuminance) + 0.05) ? black : white
  }

  var result = _hex(best[0], best[1], best[2], 1)
  _contrastCache[key] = result
  return result
}
