// Preloaded into Dyad Studio's language server (`node --require`) by
// dyad-ui-shot. The server talks LSP over stdio and needs no network for
// that. This keeps it from opening any socket of its own:
//
// - no listening. The server always starts its MCP endpoint, an HTTP server on
//   all interfaces whose tools can write files. With listen() refused, the
//   server reports that MCP failed to start and carries on without it.
// - no outgoing TCP connections and no fetch() beyond data: URLs. The server
//   fetches any icon URL that is not a dyad:// package asset with its native
//   fetch(). dyad-ui-shot already refuses such URLs before they reach the
//   server (and fetches allowed remote assets itself); this covers icons the
//   server resolves on its own, e.g. the icon of an entity.
"use strict";
const net = require("node:net");

const refuse = (what) => {
  const e = new Error(`dyad-ui-shot: ${what} is disabled in the language server`);
  e.code = "EACCES";
  return e;
};

net.Server.prototype.listen = function () {
  throw refuse("listening");
};

// Sockets over a filesystem path (IPC) stay allowed; TCP does not.
const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const o = args[0];
  const isPath = typeof o === "string" ? Number.isNaN(Number(o)) : Array.isArray(o) ? typeof o[0]?.path === "string" : typeof o?.path === "string";
  if (!isPath) throw refuse("network access");
  return connect.apply(this, args);
};

const realFetch = globalThis.fetch;
globalThis.fetch = async function fetch(input, init) {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input?.url;
  if (typeof url === "string" && /^data:/i.test(url)) return realFetch(input, init);
  throw refuse(`fetching ${url}`);
};
