// Flint web runtime entry point.
//
// T3.1: proves the native bridge round-trips by calling `ping` and rendering the
// reply. T3.2 replaces this placeholder with the CodeMirror 6 editor and wires
// `doc.load` / `doc.save`.
import { call } from "./bridge";

async function main(): Promise<void> {
  const root = document.getElementById("root");
  if (!root) return;

  try {
    const reply = await call<{ pong: boolean; echo: unknown }>("ping", { hello: "flint" });
    root.textContent = `✓ bridge ok — ${JSON.stringify(reply)}`;
  } catch (err) {
    root.textContent = `✗ bridge error — ${String(err)}`;
  }
}

void main();

export {};
