.pragma library

// Initial focus may repair an opening race, but never overwrite user input.
function shouldRestore(open, primed, target, current, handled) {
  if (!open || !primed || !target || !target.visible || !target.enabled || handled) return false
  return !current || current === target || !current.activeFocusOnTab
}
