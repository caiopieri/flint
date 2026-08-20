import { syntaxTree } from "@codemirror/language";
import type { EditorView, ViewUpdate } from "@codemirror/view";
import { EditorView as View } from "@codemirror/view";

interface OutlineHeading {
  level: number;
  title: string;
  from: number;
}

/**
 * Local table of contents for the current editor buffer.
 *
 * It deliberately stays inside CodeMirror: headings include unsaved edits and
 * opening the outline never crosses the JS/Swift bridge.
 */
export class OutlineController {
  private readonly root: HTMLDivElement;
  private readonly button: HTMLButtonElement;
  private readonly panel: HTMLDivElement;
  private view: EditorView | null = null;
  private headings: OutlineHeading[] = [];
  private isOpen = false;

  constructor(parent: HTMLElement) {
    this.root = document.createElement("div");
    this.root.className = "flint-outline-root";

    this.button = document.createElement("button");
    this.button.type = "button";
    this.button.className = "flint-outline-button";
    this.button.setAttribute("aria-label", "Abrir outline da nota");
    this.button.textContent = "☷";
    this.button.addEventListener("click", () => this.toggle());

    this.panel = document.createElement("div");
    this.panel.className = "flint-outline-panel";
    this.panel.hidden = true;

    this.root.append(this.button, this.panel);
    parent.appendChild(this.root);
    this.setVisible(false);
  }

  attach(view: EditorView): void {
    this.view = view;
    this.refresh(view);
  }

  update(update: ViewUpdate): void {
    this.view = update.view;
    if (!update.docChanged) return;
    this.refresh(update.view);
  }

  private refresh(view: EditorView): void {
    this.headings = collectHeadings(view);
    this.setVisible(this.headings.length > 0);
    if (this.isOpen) this.renderPanel();
  }

  private setVisible(visible: boolean): void {
    this.root.hidden = !visible;
    if (!visible) this.close();
  }

  private toggle(): void {
    if (!this.headings.length) return;
    this.isOpen = !this.isOpen;
    this.panel.hidden = !this.isOpen;
    if (this.isOpen) this.renderPanel();
  }

  private close(): void {
    this.isOpen = false;
    this.panel.hidden = true;
  }

  private renderPanel(): void {
    this.panel.replaceChildren();
    for (const heading of this.headings) {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "flint-outline-row";
      row.style.paddingInlineStart = `calc(var(--flint-space-3) + ${(heading.level - 1) * 12}px)`;
      row.textContent = heading.title;
      row.title = heading.title;
      row.addEventListener("click", () => this.goTo(heading));
      this.panel.appendChild(row);
    }
  }

  private goTo(heading: OutlineHeading): void {
    const view = this.view;
    if (!view) return;
    const line = view.state.doc.lineAt(heading.from);
    const contentOffset = line.text.search(/\s/);
    const anchor = heading.from + (contentOffset >= 0 ? contentOffset + 1 : heading.level);
    view.dispatch({
      selection: { anchor: Math.min(anchor, line.to) },
      effects: View.scrollIntoView(heading.from, { y: "start" }),
    });
    view.focus();
    this.close();
  }
}

function collectHeadings(view: EditorView): OutlineHeading[] {
  const headings: OutlineHeading[] = [];
  syntaxTree(view.state).iterate({
    enter: (ref) => {
      const match = /^ATXHeading([1-6])$/.exec(ref.name);
      if (!match) return;
      const line = view.state.doc.lineAt(ref.from);
      const title = line.text
        .replace(/^#{1,6}\s+/, "")
        .replace(/\s+#+\s*$/, "")
        .trim();
      if (title) headings.push({ level: Number(match[1]), title, from: line.from });
    },
  });
  return headings;
}
