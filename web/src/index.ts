// Flint web runtime entry point (T3.2 + T3.3).
//
// Hosts the CodeMirror editor and bridges it to the native vault:
//   - boot: ask Swift which note is open (doc.current) and load it (doc.load);
//   - edits: debounce, then doc.save;
//   - flush the pending save before switching notes and when the view is hidden,
//     so the debounce window can never swallow the last keystrokes.
// Native pushes note switches via window.flintOpen(path).
import { call } from "./bridge";
import { createEditor, type FlintEditor } from "./editor";

const SAVE_DEBOUNCE_MS = 400;

let editor: FlintEditor | null = null;
let currentPath: string | null = null;
let pendingText: string | null = null;
let saveTimer: ReturnType<typeof setTimeout> | undefined;

async function flushSave(): Promise<void> {
  if (saveTimer !== undefined) {
    clearTimeout(saveTimer);
    saveTimer = undefined;
  }
  if (currentPath === null || pendingText === null) return;
  const path = currentPath;
  const text = pendingText;
  pendingText = null;
  try {
    await call("doc.save", { path, text });
  } catch (err) {
    console.error("doc.save failed", err);
  }
}

function scheduleSave(text: string): void {
  pendingText = text;
  if (saveTimer !== undefined) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => void flushSave(), SAVE_DEBOUNCE_MS);
}

async function openPath(path: string | null): Promise<void> {
  await flushSave(); // never lose the previous note's pending edits
  currentPath = path;
  if (!editor) return;
  if (path === null) {
    editor.setDoc("");
    return;
  }
  try {
    const res = await call<{ text: string }>("doc.load", { path });
    editor.setDoc(res.text ?? "");
  } catch (err) {
    editor.setDoc(`Couldn't load note:\n${String(err)}`);
  }
}

// Native → JS: open a note (or null to clear). Defined before boot so an early
// push from updateUIView is safe.
(window as unknown as { flintOpen: (path: string | null) => void }).flintOpen = (path) => {
  void openPath(path);
};

// Native → JS: the keyboard bar's up/down arrows move the cursor by line.
(window as unknown as { flintMoveCursor: (dir: "up" | "down") => void }).flintMoveCursor = (dir) => {
  editor?.moveCursor(dir);
};

async function main(): Promise<void> {
  const mount = document.getElementById("editor");
  if (!mount) return;

  editor = createEditor(mount, scheduleSave);

  // Pull the initially-selected note (avoids a readiness race on first mount).
  try {
    const current = await call<{ path: string | null }>("doc.current");
    await openPath(current.path ?? null);
  } catch (err) {
    console.error("doc.current failed", err);
  }

  // Flush when the webview is hidden (app backgrounded, note deselected).
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") void flushSave();
  });
}

void main();

export {};
