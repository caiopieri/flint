// Flint web runtime entry point.
//
// Phase 1: this will host the CodeMirror 6 editor (T3) and later the plugin
// runtime. For T0 it only proves the web bundle builds and ships inside the app.
const root = document.getElementById("root");
if (root) {
  root.textContent = "Flint web runtime ready.";
}

export {};
