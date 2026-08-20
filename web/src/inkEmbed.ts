import { syntaxTree } from "@codemirror/language";
import type { EditorState } from "@codemirror/state";
import type { Range } from "@codemirror/state";
import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import type { InlineContext, MarkdownConfig } from "@lezer/markdown";
import { call } from "./bridge";

const Embed: MarkdownConfig = {
  defineNodes: ["Embed", "EmbedMark"],
  parseInline: [
    {
      name: "Embed",
      parse(cx: InlineContext, next: number, pos: number): number {
        if (next !== 33 /* ! */ || cx.char(pos + 1) !== 91 /* [ */ || cx.char(pos + 2) !== 91) {
          return -1;
        }
        for (let i = pos + 3; i < cx.end; i++) {
          if (cx.char(i) === 10) return -1;
          if (cx.char(i) === 93 /* ] */ && cx.char(i + 1) === 93) {
            const end = i + 2;
            return cx.addElement(
              cx.elt("Embed", pos, end, [
                cx.elt("EmbedMark", pos, pos + 3),
                cx.elt("EmbedMark", i, end),
              ]),
            );
          }
        }
        return -1;
      },
    },
  ],
};

export const inkMarkdownExtensions = [Embed];

function selectionTouches(state: EditorState, from: number, to: number): boolean {
  for (const r of state.selection.ranges) {
    if (r.from <= to && r.to >= from) return true;
  }
  return false;
}

class InkEmbedWidget extends WidgetType {
  constructor(readonly target: string) {
    super();
  }

  eq(other: InkEmbedWidget): boolean {
    return other.target === this.target;
  }

  toDOM(): HTMLElement {
    const wrap = document.createElement("button");
    wrap.type = "button";
    wrap.className = "cm-flint-ink-embed";
    wrap.textContent = "Loading drawing...";

    call<{ png: string; found: boolean }>("ink.thumbnail", { target: this.target })
      .then((result) => {
        wrap.textContent = "";
        if (!result.found) {
          wrap.classList.add("cm-flint-ink-missing");
          wrap.textContent = "Drawing not found";
          return;
        }
        const img = document.createElement("img");
        img.alt = this.target;
        img.src = `data:image/png;base64,${result.png}`;
        wrap.appendChild(img);
      })
      .catch(() => {
        wrap.classList.add("cm-flint-ink-missing");
        wrap.textContent = "Drawing unavailable";
      });

    wrap.addEventListener("click", (event) => {
      event.preventDefault();
      void call("ink.open", { target: this.target });
    });
    return wrap;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

class AttachmentEmbedWidget extends WidgetType {
  constructor(readonly target: string) {
    super();
  }

  eq(other: AttachmentEmbedWidget): boolean {
    return other.target === this.target;
  }

  toDOM(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-flint-attachment-embed";
    wrap.textContent = "Carregando anexo…";

    call<{ data: string; mimeType: string }>("attachment.data", { path: this.target })
      .then((result) => {
        wrap.replaceChildren();
        if (result.mimeType.startsWith("image/")) {
          const image = document.createElement("img");
          image.alt = this.target;
          image.src = `data:${result.mimeType};base64,${result.data}`;
          wrap.appendChild(image);
        } else if (result.mimeType === "application/pdf") {
          const frame = document.createElement("iframe");
          frame.title = this.target;
          frame.src = `data:application/pdf;base64,${result.data}`;
          wrap.appendChild(frame);
        } else {
          wrap.classList.add("cm-flint-attachment-file");
          wrap.textContent = `Anexo: ${this.target}`;
        }
      })
      .catch(() => {
        wrap.classList.add("cm-flint-attachment-missing");
        wrap.textContent = "Anexo indisponível";
      });
    return wrap;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

function isInkTarget(target: string): boolean {
  return target.trim().toLowerCase().endsWith(".ink");
}

function isAttachmentTarget(target: string): boolean {
  return target.trim().toLocaleLowerCase().startsWith("attachments/");
}

function buildDecorations(view: EditorView): DecorationSet {
  const deco: Range<Decoration>[] = [];
  const { state } = view;
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter: (ref) => {
        const node = ref.node;
        if (node.name !== "Embed" || selectionTouches(state, node.from, node.to)) return;
        const target = state.doc.sliceString(node.from + 3, node.to - 2).trim();
        if (!isInkTarget(target) && !isAttachmentTarget(target)) return;
        const widget = isInkTarget(target)
          ? new InkEmbedWidget(target)
          : new AttachmentEmbedWidget(target);
        deco.push(Decoration.replace({ widget }).range(node.from, node.to));
      },
    });
  }
  return Decoration.set(deco, true);
}

const inkEmbedPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.viewportChanged || update.selectionSet) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  { decorations: (v) => v.decorations },
);

const inkEmbedTheme = EditorView.theme({
  ".cm-flint-ink-embed": {
    display: "block",
    width: "100%",
    maxWidth: "420px",
    minHeight: "120px",
    margin: "var(--flint-space-3) 0",
    padding: "var(--flint-space-2)",
    border: "1px solid var(--flint-border)",
    borderRadius: "var(--flint-radius-md)",
    background: "var(--flint-surface)",
    color: "var(--flint-text-secondary)",
    cursor: "pointer",
    textAlign: "center",
  },
  ".cm-flint-ink-embed img": {
    display: "block",
    width: "100%",
    maxHeight: "260px",
    objectFit: "contain",
  },
  ".cm-flint-ink-missing": {
    borderStyle: "dashed",
  },
  ".cm-flint-attachment-embed": {
    display: "block",
    width: "100%",
    maxWidth: "520px",
    minHeight: "44px",
    margin: "var(--flint-space-3) 0",
    padding: "var(--flint-space-2)",
    border: "1px solid var(--flint-border)",
    borderRadius: "var(--flint-radius-md)",
    background: "var(--flint-surface)",
    color: "var(--flint-text-secondary)",
    boxSizing: "border-box",
  },
  ".cm-flint-attachment-embed img": {
    display: "block",
    width: "100%",
    maxHeight: "360px",
    objectFit: "contain",
  },
  ".cm-flint-attachment-embed iframe": {
    display: "block",
    width: "100%",
    height: "360px",
    border: "0",
  },
  ".cm-flint-attachment-file, .cm-flint-attachment-missing": {
    borderStyle: "dashed",
  },
});

export function inkEmbed() {
  return [inkEmbedPlugin, inkEmbedTheme];
}
