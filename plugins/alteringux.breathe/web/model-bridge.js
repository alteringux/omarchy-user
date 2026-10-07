(() => {
  const names = ['PHASE','PLUGIN_GLYPH','TECHNIQUES','SCALE_MIN','SCALE_MAX','SESSION_HISTORY_MAX','MAX_CYCLE_SECONDS','allTechniques','techniqueById','isBuiltIn','phaseLabel','phaseGlyph','phaseMs','isHold','cycleSeconds','sessionSeconds','orbScale','breathRemainingMs','defaultSession','parseSession','effectiveElapsedMs','resolve','formatClock','formatDuration','validateCustom','slugify','defaultConfig','parseConfig','defaultStats','parseStats','defaultHistory','parseHistory','dateStringOf','todayDateString','dailyBuckets','streakOf','totals','sessionsWithin','techniqueBreakdown','hourHeatmap','completionRate','suggestTechnique']
  const model = {}
  for (const name of names) model[name] = window[name]
  window.BreatheModel = Object.freeze(model)
})()
