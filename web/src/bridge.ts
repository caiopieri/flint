// bridge.ts — the JS side of the typed bridge to native Swift.
//
// WKScriptMessageHandlerWithReply turns `postMessage` into a Promise: it resolves
// with Swift's reply, or rejects with its error string. Envelope: { id, method,
// payload }. Keep calls coarse and async — never per-keystroke (see AGENTS.md).

interface FlintMessageHandler {
  postMessage(message: unknown): Promise<unknown>;
}

function messageHandler(): FlintMessageHandler {
  const w = window as unknown as {
    webkit?: { messageHandlers?: { flint?: FlintMessageHandler } };
  };
  const handler = w.webkit?.messageHandlers?.flint;
  if (!handler) {
    throw new Error("Flint bridge unavailable (not running inside the app webview).");
  }
  return handler;
}

let counter = 0;

/** Call a native bridge method and await its typed reply. */
export async function call<T = unknown>(method: string, payload?: unknown): Promise<T> {
  const id = `${Date.now()}-${counter++}`;
  return (await messageHandler().postMessage({ id, method, payload })) as T;
}
