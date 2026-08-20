// editor.ts — the CodeMirror 6 Markdown editor (T3.3).
//
// A prose editor, not a code editor: line wrapping on, no line-number gutter.
// All colors/fonts come from the design tokens (var(--flint-*) in tokens.css),
// so the editor and the native chrome render one look across the WKWebView seam
// (ADR-D03/D04) and follow dark/light automatically.
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, keymap, drawSelection } from "@codemirror/view";
import {
  cursorLineDown,
  cursorLineUp,
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
  redo,
  undo,
} from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import { GFM } from "@lezer/markdown";
import { livePreview, flintMarkdownExtensions } from "./livePreview";
import { inkEmbed, inkMarkdownExtensions } from "./inkEmbed";
import { LinkCompletionController, type LinkTarget } from "./linkCompletion";
import { OutlineController } from "./outline";

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
  /** Move the cursor one line up/down (driven by the native keyboard bar). */
  moveCursor(dir: "up" | "down"): void;
  runCommand(command: string): void;
  insertAttachment(path: string): void;
  setReadOnly(readOnly: boolean): void;
}

export function createEditor(
  parent: HTMLElement,
  onChange: (text: string) => void,
  loadLinkTargets: () => Promise<LinkTarget[]>,
): FlintEditor {
  // Distinguishes a programmatic load from a user edit, so loading a note never
  // looks like a change to save.
  let applying = false;
  const completion = new LinkCompletionController(parent, loadLinkTargets);
  const outline = new OutlineController(parent);
  const editability = new Compartment();

  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: "",
      extensions: [
        history(),
        drawSelection(),
        EditorView.lineWrapping,
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
        // GFM gives task lists / strikethrough; flintMarkdownExtensions add
        // [[wikilinks]], ==highlight==, and #tags for Live Preview.
        markdown({ extensions: [GFM, ...inkMarkdownExtensions, ...flintMarkdownExtensions] }),
        syntaxHighlighting(flintHighlight),
        livePreview(),
        inkEmbed(),
        completion.extension(),
        editability.of(EditorView.editable.of(true)),
        EditorView.updateListener.of((update) => outline.update(update)),
        flintTheme,
        EditorView.updateListener.of((update) => {
          if (update.docChanged && !applying) onChange(view.state.doc.toString());
        }),
      ],
    }),
  });
  outline.attach(view);

  // Let the system keyboard provide sentence capitalization, spell checking,
  // and language-aware autocorrection inside the WKWebView content editor.
  view.contentDOM.setAttribute("autocapitalize", "sentences");
  view.contentDOM.setAttribute("autocorrect", "on");
  view.contentDOM.setAttribute("spellcheck", "true");
  view.contentDOM.setAttribute("lang", "pt-BR");

  return {
    setDoc(text: string) {
      applying = true;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
      applying = false;
    },
    getDoc: () => view.state.doc.toString(),
    focus: () => view.focus(),
    moveCursor(dir) {
      (dir === "up" ? cursorLineUp : cursorLineDown)(view);
      view.focus();
    },
    runCommand(command) {
      const { from, to } = view.state.selection.main;
      const selected = view.state.doc.sliceString(from, to);
      const surround = (open: string, close = open) => {
        view.dispatch({
          changes: { from, to, insert: `${open}${selected}${close}` },
          selection: { anchor: from + open.length + selected.length + close.length },
        });
        view.focus();
      };
      switch (command) {
        case "undo": return void undo(view);
        case "redo": return void redo(view);
        case "wikilink":
          view.dispatch({
            changes: { from, to, insert: `[[${selected}]]` },
            selection: { anchor: from + 2 + selected.length },
          });
          view.focus();
          return;
        case "embed": return surround("![[", "]]" );
        case "attach": return surround("![[", "]]" );
        case "bold": return surround("**", "**");
        case "italic": return surround("*", "*");
        case "strike": return surround("~~", "~~");
        case "code": return surround("`", "`");
        case "link": return surround("[", "](url)");
        case "quote": return surround("> ", "");
        case "list": return surround("- ", "");
        case "numberedList": return surround("1. ", "");
        case "checklist": return surround("- [ ] ", "");
        case "indent":
          view.dispatch({ changes: { from, to, insert: selected.split("\n").map((line) => `  ${line}`).join("\n") } });
          view.focus();
          return;
        case "outdent":
          view.dispatch({ changes: { from, to, insert: selected.split("\n").map((line) => line.replace(/^ {1,2}/, "")).join("\n") } });
          view.focus();
          return;
        case "heading": return surround("# ", "");
        case "tag": return surround("#", "");
        default: return;
      }
    },
    insertAttachment(path) {
      const { from, to } = view.state.selection.main;
      const text = `![[${path}]]`;
      view.dispatch({
        changes: { from, to, insert: text },
        selection: { anchor: from + text.length },
      });
      view.focus();
    },
    setReadOnly(readOnly) {
      view.dispatch({ effects: editability.reconfigure(EditorView.editable.of(!readOnly)) });
      if (readOnly) view.contentDOM.blur();
    },
  };
}
