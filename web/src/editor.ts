// editor.ts — the CodeMirror 6 Markdown editor (T3.3).
//
// A prose editor, not a code editor: line wrapping on, no line-number gutter.
// All colors/fonts come from the design tokens (var(--flint-*) in tokens.css),
// so the editor and the native chrome render one look across the WKWebView seam
// (ADR-D03/D04) and follow dark/light automatically.
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, drawSelection } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

const flintTheme = EditorView.theme({
  "&": {
    height: "100%",
    color: "var(--flint-text-primary)",
    backgroundColor: "var(--flint-bg)",
    fontSize: "var(--flint-reading-base-size)",
  },
  ".cm-scroller": {
    fontFamily: "var(--flint-font-serif)",
    lineHeight: "var(--flint-reading-base-lh)",
    overflow: "auto",
  },
  ".cm-content": {
    // Editorial measure, centered like a document — not edge-to-edge.
    maxWidth: "var(--flint-reading-measure)",
    margin: "0 auto",
    padding: "var(--flint-space-6) var(--flint-space-5) var(--flint-space-10)",
    caretColor: "var(--flint-cursor)",
  },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--flint-cursor)" },
  "&.cm-focused": { outline: "none" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection": {
    backgroundColor: "var(--flint-selection)",
  },
  ".cm-activeLine": { backgroundColor: "transparent" },
});

const flintHighlight = HighlightStyle.define([
  { tag: t.heading, color: "var(--flint-syntax-heading)", fontWeight: "600" },
  { tag: t.strong, color: "var(--flint-syntax-strong)", fontWeight: "700" },
  { tag: t.emphasis, color: "var(--flint-syntax-emphasis)", fontStyle: "italic" },
  { tag: t.link, color: "var(--flint-syntax-link)" },
  { tag: t.url, color: "var(--flint-syntax-link)" },
  { tag: t.monospace, color: "var(--flint-syntax-code)" },
  { tag: t.quote, color: "var(--flint-syntax-blockquote)", fontStyle: "italic" },
  // The literal Markdown punctuation (#, *, -, >, backticks, link brackets).
  { tag: [t.processingInstruction, t.meta, t.punctuation], color: "var(--flint-syntax-markup)" },
  { tag: t.list, color: "var(--flint-syntax-markup)" },
]);

export interface FlintEditor {
  /** Replace the whole document (a load) without firing the change callback. */
  setDoc(text: string): void;
  getDoc(): string;
  focus(): void;
}

export function createEditor(parent: HTMLElement, onChange: (text: string) => void): FlintEditor {
  // Distinguishes a programmatic load from a user edit, so loading a note never
  // looks like a change to save.
  let applying = false;

  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: "",
      extensions: [
        history(),
        drawSelection(),
        EditorView.lineWrapping,
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
        markdown(),
        syntaxHighlighting(flintHighlight),
        flintTheme,
        EditorView.updateListener.of((update) => {
          if (update.docChanged && !applying) onChange(view.state.doc.toString());
        }),
      ],
    }),
  });

  return {
    setDoc(text: string) {
      applying = true;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
      applying = false;
    },
    getDoc: () => view.state.doc.toString(),
    focus: () => view.focus(),
  };
}
