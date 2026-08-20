import type { Extension } from "@codemirror/state";
import { EditorView, type ViewUpdate } from "@codemirror/view";
import { call } from "./bridge";

export interface LinkTarget {
  label: string;
  path: string;
  target: string;
  kind: "md" | "ink";
}

type LinkTargetLoader = () => Promise<LinkTarget[]>;

/** Local `[[` completion. The catalog is loaded once over the coarse bridge. */
export class LinkCompletionController {
  private readonly menu: HTMLDivElement;
  private view: EditorView | null = null;
  private targets: LinkTarget[] = [];
  private visibleTargets: LinkTarget[] = [];
  private createTarget: string | null = null;
  private queryStart = 0;
  private queryEnd = 0;
  private selectedIndex = 0;
  private lastQuery = "";
  private catalogRequested = false;
  private insertingClosingDelimiters = false;

  constructor(
    private readonly parent: HTMLElement,
    private readonly loadTargets: LinkTargetLoader,
  ) {
    parent.classList.add("flint-editor-host");
    this.menu = document.createElement("div");
    this.menu.className = "flint-link-menu";
    this.menu.setAttribute("role", "listbox");
    this.menu.hidden = true;
    parent.appendChild(this.menu);
  }

  extension(): Extension {
    return [
      EditorView.updateListener.of((update) => this.update(update)),
      EditorView.domEventHandlers({
        keydown: (event) => this.handleKeydown(event),
      }),
    ];
  }

  setTargets(targets: LinkTarget[]): void {
    this.targets = targets;
    if (this.view) this.refresh(this.view);
  }

  destroy(): void {
    this.menu.remove();
  }

  private update(update: ViewUpdate): void {
    this.view = update.view;
    if (update.docChanged && !this.insertingClosingDelimiters && this.ensureClosingDelimiters(update.view)) {
      return;
    }
    if (update.docChanged || update.selectionSet || update.viewportChanged) {
      this.refresh(update.view);
    }
  }

  /** Typing the second `[` creates the pair and leaves the caret inside it. */
  private ensureClosingDelimiters(view: EditorView): boolean {
    const head = view.state.selection.main.head;
    const line = view.state.doc.lineAt(head);
    const offset = head - line.from;
    if (!line.text.slice(0, offset).endsWith("[[")) return false;
    if (line.text.slice(offset, offset + 2) === "]]") {
      return false;
    }

    this.insertingClosingDelimiters = true;
    view.dispatch({
      changes: { from: head, insert: "]]" },
      selection: { anchor: head },
    });
    this.insertingClosingDelimiters = false;
    return true;
  }

  private refresh(view: EditorView): void {
    const head = view.state.selection.main.head;
    const line = view.state.doc.lineAt(head);
    const beforeCursor = line.text.slice(0, head - line.from);
    const opener = beforeCursor.lastIndexOf("[[");

    if (opener < 0 || beforeCursor.slice(opener + 2).includes("]")) {
      this.hide();
      return;
    }

    this.queryStart = line.from + opener + 2;
    this.queryEnd = head;
    const query = beforeCursor.slice(opener + 2);
    if (/^\s/.test(query)) {
      this.hide();
      return;
    }
    if (query !== this.lastQuery) {
      this.selectedIndex = 0;
      this.lastQuery = query;
    }
    this.ensureCatalog();
    const needle = query.toLocaleLowerCase();
    this.visibleTargets = this.targets
      .filter((target) =>
        `${target.label} ${target.target}`.toLocaleLowerCase().includes(needle),
      )
      .slice(0, 8);
    this.createTarget = query && !this.hasExactTarget(query) ? query : null;
    const optionCount = this.visibleTargets.length + (this.createTarget ? 1 : 0);
    this.selectedIndex = Math.min(this.selectedIndex, Math.max(optionCount - 1, 0));

    this.render();
    this.position(view, head);
  }

  private ensureCatalog(): void {
    if (this.catalogRequested) return;
    this.catalogRequested = true;
    void this.loadTargets()
      .then((targets) => {
        this.targets = targets;
        if (this.view && !this.menu.hidden) this.refresh(this.view);
      })
      .catch((error) => {
        console.error("doc.links failed", error);
        this.targets = [];
        if (this.view && !this.menu.hidden) this.refresh(this.view);
      });
  }

  private render(): void {
    this.menu.replaceChildren();
    this.menu.hidden = false;

    if (this.visibleTargets.length === 0 && !this.createTarget) {
      const empty = document.createElement("div");
      empty.className = "flint-link-menu-empty";
      empty.textContent = "Nenhum documento encontrado";
      this.menu.appendChild(empty);
      return;
    }

    for (const [index, target] of this.visibleTargets.entries()) {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "flint-link-menu-row";
      row.setAttribute("role", "option");
      row.setAttribute("aria-selected", String(index === this.selectedIndex));
      if (index === this.selectedIndex) row.classList.add("is-selected");

      const label = document.createElement("span");
      label.className = "flint-link-menu-label";
      label.textContent = target.label;
      const path = document.createElement("span");
      path.className = "flint-link-menu-path";
      path.textContent = target.kind === "ink" ? "caderno" : target.path;
      row.append(label, path);

      row.addEventListener("mousedown", (event) => event.preventDefault());
      row.addEventListener("click", () => this.accept(index));
      this.menu.appendChild(row);
    }

    if (this.createTarget) {
      const index = this.visibleTargets.length;
      const row = document.createElement("button");
      row.type = "button";
      row.className = "flint-link-menu-row is-create";
      row.setAttribute("role", "option");
      row.setAttribute("aria-selected", String(index === this.selectedIndex));
      if (index === this.selectedIndex) row.classList.add("is-selected");

      const label = document.createElement("span");
      label.className = "flint-link-menu-label";
      label.textContent = `Criar: ${this.createTarget}`;
      const path = document.createElement("span");
      path.className = "flint-link-menu-path";
      path.textContent = this.createTarget.toLocaleLowerCase().endsWith(".ink")
        ? "caderno"
        : "nota";
      row.append(label, path);

      row.addEventListener("mousedown", (event) => event.preventDefault());
      row.addEventListener("click", () => this.accept(index));
      this.menu.appendChild(row);
    }
  }

  private position(view: EditorView, head: number): void {
    const coords = view.coordsAtPos(head);
    if (!coords) {
      this.hide();
      return;
    }
    const parentRect = this.parent.getBoundingClientRect();
    const menuHeight = this.menu.offsetHeight;
    const left = Math.max(8, Math.min(
      coords.left - parentRect.left,
      this.parent.clientWidth - this.menu.offsetWidth - 8,
    ));
    let top = coords.top - parentRect.top - menuHeight - 8;
    if (top < 8) top = coords.bottom - parentRect.top + 8;
    this.menu.style.left = `${left}px`;
    this.menu.style.top = `${top}px`;
  }

  private handleKeydown(event: KeyboardEvent): boolean {
    if (this.menu.hidden) return false;
    if (event.key === "ArrowRight") {
      event.preventDefault();
      this.finishTypedTarget();
      return true;
    }
    const optionCount = this.visibleTargets.length + (this.createTarget ? 1 : 0);
    if (optionCount === 0) return false;
    if (event.key === "ArrowDown") {
      event.preventDefault();
      this.selectedIndex = (this.selectedIndex + 1) % optionCount;
      this.render();
      if (this.view) this.position(this.view, this.queryEnd);
      return true;
    }
    if (event.key === "ArrowUp") {
      event.preventDefault();
      this.selectedIndex = (this.selectedIndex - 1 + optionCount) % optionCount;
      this.render();
      if (this.view) this.position(this.view, this.queryEnd);
      return true;
    }
    if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault();
      this.accept(this.selectedIndex);
      return true;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      this.hide();
      return true;
    }
    return false;
  }

  private finishTypedTarget(): void {
    if (!this.view) return;
    const trailing = this.view.state.doc.sliceString(this.queryEnd, this.queryEnd + 2);
    const closeLength = trailing === "]]" ? 2 : 0;
    if (closeLength === 0) {
      this.view.dispatch({
        changes: { from: this.queryEnd, insert: "]]" },
        selection: { anchor: this.queryEnd + 2 },
      });
    } else {
      this.view.dispatch({ selection: { anchor: this.queryEnd + 2 } });
    }
    this.view.focus();
    this.hide();
  }

  private accept(index: number): void {
    const createIndex = this.visibleTargets.length;
    if (this.createTarget && index === createIndex) {
      const target = this.createTarget;
      this.insertTarget(target);
      void call<{ opened: boolean }>("note.open", { target }).catch((error) => {
        console.error("wikilink create failed", error);
      });
      return;
    }
    const target = this.visibleTargets[index];
    if (!target) return;
    this.insertTarget(target.target);
  }

  private insertTarget(target: string): void {
    if (!this.view) return;
    const trailing = this.view.state.doc.sliceString(this.queryEnd, this.queryEnd + 2);
    const closeLength = trailing === "]]" ? 2 : 0;
    this.view.dispatch({
      changes: {
        from: this.queryStart,
        to: this.queryEnd + closeLength,
        insert: `${target}]]`,
      },
      selection: { anchor: this.queryStart + target.length + 2 },
    });
    this.view.focus();
    this.hide();
  }

  private hasExactTarget(query: string): boolean {
    const normalized = query.toLocaleLowerCase();
    const extension = normalized.endsWith(".md")
      ? "md"
      : normalized.endsWith(".ink")
        ? "ink"
        : "";
    const base = extension ? normalized.slice(0, -(extension.length + 1)) : normalized;
    return this.targets.some((target) => {
      if (extension && target.kind !== extension) return false;
      return target.target.toLocaleLowerCase() === base || target.label.toLocaleLowerCase() === base;
    });
  }

  private hide(): void {
    this.visibleTargets = [];
    this.createTarget = null;
    this.lastQuery = "";
    this.menu.hidden = true;
  }
}
