// livePreview.ts — Obsidian-style "Live Preview" for the CodeMirror editor (T8).
//
// Renders Markdown inline while keeping the file plain text: the markup
// characters (**, *, `, #, >, -, [ ]) are CONCEALED, and the content is styled
// (bold, italic, heading sizes, bullets, checkboxes…). The trick that keeps it
// editable: whenever the selection/cursor touches a formatted region, that
// region's raw markers are REVEALED so you can edit them. Move away → concealed
// again.
//
// How it works (CodeMirror 6): a ViewPlugin walks the Lezer Markdown syntax tree
// over the visible ranges and produces two kinds of decorations —
//   • Decoration.mark   — styles the *content* (e.g. bold weight) ;
//   • Decoration.replace — hides the *marker* glyphs (or swaps them for a widget
//                          like a bullet • or a checkbox).
// Concealment is skipped for any node the selection currently touches. The set
// is rebuilt on doc change, viewport change, and selection change.
//
// Scope (locked, T8): bold, italic, inline code, headings, bullets, ordered
// lists, links, blockquotes, task checkboxes. Out: tables, images, embeds
// (`![[…]]` is the Ink/T7 seam), callouts, math.
import { syntaxTree } from "@codemirror/language";
import type { EditorState } from "@codemirror/state";
import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import type { Range } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";

// A zero-config replace decoration that simply hides the range it covers.
const hide = Decoration.replace({});

/** True if any selection range touches (overlaps or sits at the edge of) [from, to]. */
function selectionTouches(state: EditorState, from: number, to: number): boolean {
  for (const r of state.selection.ranges) {
    if (r.from <= to && r.to >= from) return true;
  }
  return false;
}

// Renders the list bullet glyph in place of the raw `-`/`*`/`+` marker.
class BulletWidget extends WidgetType {
  eq(): boolean {
    return true;
  }
  toDOM(): HTMLElement {
    const dot = document.createElement("span");
    dot.className = "cm-flint-bullet";
    dot.textContent = "•";
    return dot;
  }
}

// An interactive checkbox for `- [ ]` / `- [x]`. Clicking toggles the source
// character at `markPos` (the slot between the brackets) — files stay the truth.
class CheckboxWidget extends WidgetType {
  constructor(
    readonly checked: boolean,
    readonly markPos: number,
  ) {
    super();
  }
  eq(other: CheckboxWidget): boolean {
    return other.checked === this.checked && other.markPos === this.markPos;
  }
  toDOM(view: EditorView): HTMLElement {
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = this.checked;
    box.className = "cm-flint-task";
    box.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const cur = view.state.doc.sliceString(this.markPos, this.markPos + 1);
      const next = /[xX]/.test(cur) ? " " : "x";
      view.dispatch({ changes: { from: this.markPos, to: this.markPos + 1, insert: next } });
    });
    return box;
  }
  ignoreEvent(): boolean {
    return true;
  }
}

/** Direct children of `node` whose name ends in "Mark" (EmphasisMark, CodeMark…). */
function markChildren(node: SyntaxNode): SyntaxNode[] {
  const marks: SyntaxNode[] = [];
  for (let c = node.firstChild; c; c = c.nextSibling) {
    if (c.name.endsWith("Mark")) marks.push(c);
  }
  return marks;
}

/** First direct child named `name`, or null. */
function childNamed(node: SyntaxNode, name: string): SyntaxNode | null {
  for (let c = node.firstChild; c; c = c.nextSibling) {
    if (c.name === name) return c;
  }
  return null;
}

const HEADING_RE = /^ATXHeading(\d)$/;

function buildDecorations(view: EditorView): DecorationSet {
  const { state } = view;
  const deco: Range<Decoration>[] = [];
  const add = (from: number, to: number, d: Decoration) => deco.push(d.range(from, to));

  // A paired-delimiter inline node (strong/emphasis/code): style the content,
  // hide the leading & trailing markers unless the cursor is inside.
  const inlineDelimited = (node: SyntaxNode, contentClass: string) => {
    const marks = markChildren(node);
    if (marks.length < 2) return;
    const contentFrom = marks[0].to;
    const contentTo = marks[marks.length - 1].from;
    if (contentTo > contentFrom) add(contentFrom, contentTo, Decoration.mark({ class: contentClass }));
    if (selectionTouches(state, node.from, node.to)) return; // reveal markers
    for (const m of marks) add(m.from, m.to, hide);
  };

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter: (ref) => {
        const node = ref.node;
        const name = node.name;

        if (name === "StrongEmphasis") {
          inlineDelimited(node, "cm-flint-strong");
        } else if (name === "Emphasis") {
          inlineDelimited(node, "cm-flint-em");
        } else if (name === "InlineCode") {
          inlineDelimited(node, "cm-flint-code");
        } else if (name === "Strikethrough") {
          inlineDelimited(node, "cm-flint-strike");
        } else if (HEADING_RE.test(name)) {
          const level = Number(HEADING_RE.exec(name)![1]);
          const line = state.doc.lineAt(node.from);
          add(line.from, line.from, Decoration.line({ class: `cm-flint-h cm-flint-h${level}` }));
          if (selectionTouches(state, line.from, line.to)) return;
          const mark = childNamed(node, "HeaderMark");
          if (mark) add(node.from, Math.min(mark.to + 1, line.to), hide); // "# " (incl. space)
        } else if (name === "QuoteMark") {
          const line = state.doc.lineAt(node.from);
          add(line.from, line.from, Decoration.line({ class: "cm-flint-quote" }));
          if (selectionTouches(state, line.from, line.to)) return;
          add(node.from, Math.min(node.to + 1, line.to), hide); // "> " (incl. space)
        } else if (name === "Link") {
          // LinkMark children are "[", "]", "(", ")" — the text sits between the
          // first two (robust even when the link text is itself formatted).
          const marks = markChildren(node);
          if (marks.length < 2) return;
          const textFrom = marks[0].to;
          const textTo = marks[1].from;
          if (textTo > textFrom) add(textFrom, textTo, Decoration.mark({ class: "cm-flint-link" }));
          if (selectionTouches(state, node.from, node.to)) return;
          add(node.from, textFrom, hide); // "["
          add(textTo, node.to, hide); // "](url)"
        } else if (name === "ListItem") {
          const reveal = selectionTouches(state, state.doc.lineAt(node.from).from, state.doc.lineAt(node.from).to);
          const listMark = childNamed(node, "ListMark");
          const task = childNamed(node, "Task");
          if (task) {
            const marker = childNamed(task, "TaskMarker"); // "[ ]" / "[x]"
            if (listMark && marker && !reveal) {
              const checked = /[xX]/.test(state.doc.sliceString(marker.from, marker.to));
              add(
                listMark.from,
                marker.to,
                Decoration.replace({ widget: new CheckboxWidget(checked, marker.from + 1) }),
              );
            }
          } else if (listMark && !reveal) {
            const glyph = state.doc.sliceString(listMark.from, listMark.to);
            if (/^[-*+]$/.test(glyph)) {
              add(listMark.from, listMark.to, Decoration.replace({ widget: new BulletWidget() }));
            }
          }
        }
      },
    });
  }

  return Decoration.set(deco, true);
}

const livePreviewPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }
    update(u: ViewUpdate) {
      if (u.docChanged || u.viewportChanged || u.selectionSet) {
        this.decorations = buildDecorations(u.view);
      }
    }
  },
  { decorations: (v) => v.decorations },
);

// Styling for the rendered content. Colors/sizes come from the design tokens so
// the editor matches native chrome and follows dark/light (ADR-D03/D04).
const livePreviewTheme = EditorView.theme({
  ".cm-flint-strong": { fontWeight: "700", color: "var(--flint-syntax-strong)" },
  ".cm-flint-em": { fontStyle: "italic", color: "var(--flint-syntax-emphasis)" },
  ".cm-flint-strike": { textDecoration: "line-through", color: "var(--flint-text-muted)" },
  ".cm-flint-code": {
    fontFamily: "var(--flint-font-mono)",
    fontSize: "0.9em",
    color: "var(--flint-syntax-code)",
    backgroundColor: "var(--flint-surface, rgba(255,255,255,0.06))",
    borderRadius: "4px",
    padding: "0.05em 0.3em",
  },
  ".cm-flint-link": {
    color: "var(--flint-syntax-link)",
    textDecoration: "underline",
    cursor: "pointer",
  },
  ".cm-flint-h": { fontWeight: "700", color: "var(--flint-syntax-heading)", lineHeight: "1.25" },
  ".cm-flint-h1": { fontSize: "var(--flint-reading-h1-size)" },
  ".cm-flint-h2": { fontSize: "var(--flint-reading-h2-size)" },
  ".cm-flint-h3": { fontSize: "var(--flint-reading-h3-size)" },
  ".cm-flint-h4, .cm-flint-h5, .cm-flint-h6": { fontSize: "1em" },
  ".cm-flint-quote": {
    borderLeft: "3px solid var(--flint-syntax-blockquote)",
    paddingLeft: "var(--flint-space-3)",
    color: "var(--flint-syntax-blockquote)",
    fontStyle: "italic",
  },
  ".cm-flint-bullet": { color: "var(--flint-syntax-markup)" },
  ".cm-flint-task": { verticalAlign: "middle", marginRight: "0.4em", cursor: "pointer" },
});

/** The Live Preview extension: conceal-and-render Markdown with cursor reveal. */
export function livePreview() {
  return [livePreviewPlugin, livePreviewTheme];
}
