import { call } from "./bridge";

interface BoardNode { id: string; type: string; x: number; y: number; width: number; height: number; file?: string; [key: string]: unknown }
interface BoardEdge { id: string; fromNode: string; toNode: string; [key: string]: unknown }
interface BoardDocument { nodes: BoardNode[]; edges: BoardEdge[]; [key: string]: unknown }
interface BoardNote { path: string; title: string }

let boardPath: string | null = null;
let boardDoc: BoardDocument = { nodes: [], edges: [] };
let notes: BoardNote[] = [];
let scale = 1;
let offsetX = 0;
let offsetY = 0;
let loadError: string | null = null;
let saveTimer: ReturnType<typeof setTimeout> | undefined;
let movedDuringDrag = false;

const mount = document.getElementById("board");
if (!mount) throw new Error("Board mount missing");
const root = mount;

function button(label: string, action: () => void): HTMLButtonElement {
  const element = document.createElement("button");
  element.type = "button";
  element.textContent = label;
  element.addEventListener("click", action);
  return element;
}

function titleFor(node: BoardNode): string {
  return typeof node.flintTitle === "string" ? node.flintTitle : node.file?.split("/").pop()?.replace(/\.md$/i, "") ?? "Board node";
}

function render(): void {
  root.replaceChildren();
  const shell = document.createElement("section");
  shell.className = "board-shell";
  const toolbar = document.createElement("nav");
  toolbar.className = "board-toolbar";
  toolbar.setAttribute("aria-label", "Ferramentas do Board");
  const add = button("＋", () => toggleNotesPanel());
  add.setAttribute("aria-label", "Adicionar nota ao Board");
  const zoomOut = button("−", () => zoomBy(.85));
  zoomOut.setAttribute("aria-label", "Diminuir zoom");
  const fit = button("100%", fitBoard);
  fit.setAttribute("aria-label", "Enquadrar Board");
  const zoomIn = button("＋", () => zoomBy(1.18));
  zoomIn.setAttribute("aria-label", "Aumentar zoom");
  toolbar.append(add, zoomOut, fit, zoomIn);
  const status = document.createElement("span");
  status.className = "board-status";
  status.textContent = `${boardDoc.nodes.length} nó${boardDoc.nodes.length === 1 ? "" : "s"}`;
  toolbar.append(status);

  const viewport = document.createElement("div");
  viewport.className = "board-viewport";
  viewport.addEventListener("pointerdown", startPan);
  const workspace = document.createElement("div");
  workspace.className = "board-workspace";
  workspace.style.transform = `translate(${offsetX}px, ${offsetY}px) scale(${scale})`;
  const edges = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  edges.classList.add("board-edges");
  for (const edge of boardDoc.edges) {
    const from = boardDoc.nodes.find((node) => node.id === edge.fromNode);
    const to = boardDoc.nodes.find((node) => node.id === edge.toNode);
    if (!from || !to) continue;
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.dataset.fromNode = edge.fromNode; line.dataset.toNode = edge.toNode;
    line.setAttribute("x1", String(from.x + from.width / 2)); line.setAttribute("y1", String(from.y + from.height / 2));
    line.setAttribute("x2", String(to.x + to.width / 2)); line.setAttribute("y2", String(to.y + to.height / 2));
    line.setAttribute("stroke", "currentColor"); line.setAttribute("stroke-opacity", ".35"); line.setAttribute("stroke-width", "2");
    edges.append(line);
  }
  workspace.append(edges);
  for (const node of boardDoc.nodes) workspace.append(card(node));
  viewport.append(workspace);
  const addBar = document.createElement("nav");
  addBar.className = "board-add-bar";
  addBar.setAttribute("aria-label", "Adicionar ao Board");
  const addNote = button("▤", () => toggleNotesPanel());
  addNote.setAttribute("aria-label", "Adicionar nota");
  const addText = button("T", () => toggleNotesPanel());
  addText.setAttribute("aria-label", "Adicionar cartão de texto");
  const addMedia = button("▧", () => toggleNotesPanel());
  addMedia.setAttribute("aria-label", "Adicionar mídia");
  addBar.append(addNote, addText, addMedia);
  shell.append(toolbar, viewport, addBar);
  if (loadError || boardDoc.nodes.length === 0) {
    const empty = document.createElement("div"); empty.className = "board-empty";
    empty.textContent = loadError ?? "Este Board está vazio. Use “Adicionar nota” para começar."; shell.append(empty);
  }
  root.append(shell);
}

function card(node: BoardNode): HTMLElement {
  const element = document.createElement("article");
  element.className = "board-card";
  element.dataset.boardNodeId = node.id;
  element.style.left = `${node.x}px`; element.style.top = `${node.y}px`;
  element.style.width = `${node.width}px`; element.style.height = `${node.height}px`;
  element.setAttribute("aria-label", node.type === "file" ? titleFor(node) : "Nó não suportado");
  if (node.type === "file") {
    const title = document.createElement("strong"); title.className = "board-card-title"; title.textContent = titleFor(node);
    const path = document.createElement("span"); path.className = "board-card-path"; path.textContent = node.file ?? "Arquivo não encontrado";
    element.append(title, path);
  } else {
    const unsupported = document.createElement("span"); unsupported.className = "board-card-unsupported"; unsupported.textContent = `Tipo “${node.type}” preservado`;
    element.append(unsupported);
  }
  element.addEventListener("pointerdown", (event) => startDrag(event, node.id));
  return element;
}

function startPan(event: PointerEvent): void {
  if (event.target !== event.currentTarget) return;
  const startX = event.clientX, startY = event.clientY, initialX = offsetX, initialY = offsetY;
  const move = (current: PointerEvent) => { offsetX = initialX + current.clientX - startX; offsetY = initialY + current.clientY - startY; updateViewport(); };
  const end = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", end); };
  window.addEventListener("pointermove", move); window.addEventListener("pointerup", end, { once: true });
}

function startDrag(event: PointerEvent, id: string): void {
  event.stopPropagation();
  const node = boardDoc.nodes.find((item) => item.id === id); if (!node) return;
  const startX = event.clientX, startY = event.clientY, initialX = node.x, initialY = node.y;
  movedDuringDrag = false;
  const move = (current: PointerEvent) => {
    const dx = (current.clientX - startX) / scale, dy = (current.clientY - startY) / scale;
    movedDuringDrag ||= Math.abs(dx) > 3 || Math.abs(dy) > 3;
    node.x = Math.round(initialX + dx); node.y = Math.round(initialY + dy);
    const element = document.querySelector<HTMLElement>(`[data-board-node-id="${CSS.escape(id)}"]`);
    if (element) { element.style.left = `${node.x}px`; element.style.top = `${node.y}px`; }
    refreshEdges();
  };
  const end = () => {
    window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", end);
    if (movedDuringDrag) scheduleSave(); else if (node.type === "file" && node.file) void call("note.open", { target: node.file });
  };
  window.addEventListener("pointermove", move); window.addEventListener("pointerup", end, { once: true });
}

function zoomBy(factor: number): void { scale = Math.min(2.5, Math.max(.35, scale * factor)); render(); }

function updateViewport(): void {
  const workspace = document.querySelector<HTMLElement>(".board-workspace");
  if (workspace) workspace.style.transform = `translate(${offsetX}px, ${offsetY}px) scale(${scale})`;
}

function refreshEdges(): void {
  for (const line of document.querySelectorAll<SVGLineElement>(".board-edges line")) {
    const from = boardDoc.nodes.find((node) => node.id === line.dataset.fromNode);
    const to = boardDoc.nodes.find((node) => node.id === line.dataset.toNode);
    if (!from || !to) continue;
    line.setAttribute("x1", String(from.x + from.width / 2)); line.setAttribute("y1", String(from.y + from.height / 2));
    line.setAttribute("x2", String(to.x + to.width / 2)); line.setAttribute("y2", String(to.y + to.height / 2));
  }
}

function fitBoard(): void {
  if (boardDoc.nodes.length === 0) { scale = 1; offsetX = 0; offsetY = 0; render(); return; }
  const minX = Math.min(...boardDoc.nodes.map((node) => node.x)), minY = Math.min(...boardDoc.nodes.map((node) => node.y));
  offsetX = 40 - minX * scale; offsetY = 100 - minY * scale; render();
}

function scheduleSave(): void {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => { saveTimer = undefined; void save(); }, 220);
}

async function save(): Promise<void> {
  if (!boardPath) return;
  try { await call("board.save", { path: boardPath, document: JSON.stringify(boardDoc) }); } catch (error) { console.error("board.save failed", error); }
}

function toggleNotesPanel(): void {
  const current = document.querySelector(".board-panel");
  if (current) { current.remove(); return; }
  const panel = document.createElement("aside"); panel.className = "board-panel"; panel.setAttribute("aria-label", "Notas do vault");
  const heading = document.createElement("div"); heading.className = "board-panel-title"; heading.textContent = "Adicionar nota"; panel.append(heading);
  for (const note of notes) {
    if (boardDoc.nodes.some((node) => node.file === note.path)) continue;
    const row = document.createElement("button"); row.type = "button"; row.className = "board-note-row";
    const title = document.createElement("span"); title.className = "board-note-title"; title.textContent = note.title;
    const path = document.createElement("span"); path.className = "board-note-path"; path.textContent = note.path; row.append(title, path);
    row.addEventListener("click", () => { void addNote(note); }); panel.append(row);
  }
  if (panel.childElementCount === 1) { const empty = document.createElement("div"); empty.className = "board-panel-title"; empty.textContent = "Todas as notas já estão no Board."; panel.append(empty); }
  document.querySelector(".board-shell")?.append(panel);
}

async function addNote(note: BoardNote): Promise<void> {
  const maxX = boardDoc.nodes.reduce((value, node) => Math.max(value, node.x + node.width + 40), 40);
  boardDoc.nodes.push({ id: crypto.randomUUID(), type: "file", file: note.path, flintTitle: note.title, x: maxX, y: 140, width: 320, height: 180 });
  document.querySelector(".board-panel")?.remove(); render(); await save();
}

async function openPath(path: string): Promise<void> {
  boardPath = path;
  loadError = null;
  try {
    const loaded = await call<{ document: string }>("board.load", { path });
    boardDoc = JSON.parse(loaded.document) as BoardDocument;
    const listed = await call<{ notes: BoardNote[] }>("board.notes"); notes = listed.notes ?? [];
    render();
  } catch (error) { boardDoc = { nodes: [], edges: [] }; loadError = "Não foi possível abrir este Board."; render(); console.error("board.load failed", error); }
}

(window as unknown as { flintBoardOpen: (path: string) => void }).flintBoardOpen = (path) => { void openPath(path); };
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") void save(); });
render();

export {};
