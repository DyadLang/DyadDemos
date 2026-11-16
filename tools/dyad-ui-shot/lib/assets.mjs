// Which icon URLs the diagram view may load. Studio's language server answers
// dyad/fetch-icon for dyad:// package assets from the library files and hands
// every other URL to Node's fetch(), which reaches any host. dyad-ui-shot
// only forwards local requests to it:
//
//   urn:definition:...   the icon of an entity, resolved by the server
//   dyad://Pkg/file      an asset of a loaded Dyad package
//   data:...             inline
//
// Anything else is refused, unless it is an http(s) URL on a host listed with
// --allow-remote-assets, which dyad-ui-shot then fetches itself (size limit,
// timeout, no redirects off the list) without involving the server.

export const DEFAULT_ICON = "dyad://Dyad/Default.svg";
export const REMOTE_MAX_BYTES = 2 << 20;
export const REMOTE_TIMEOUT_MS = 10000;

export function classifyIconUrl(url) {
  if (typeof url !== "string") return "refused";
  if (url.startsWith("urn:definition:")) return "entity";
  let u;
  try {
    u = new URL(url);
  } catch {
    return "refused";
  }
  if (u.protocol === "dyad:") return "package";
  if (u.protocol === "data:") return "data";
  if (u.protocol === "http:" || u.protocol === "https:") return "remote";
  return "refused";
}

// "a.example.com, b.example.com:8443" -> ["a.example.com", "b.example.com:8443"]
export function parseHostList(s) {
  return String(s ?? "")
    .split(/[\s,]+/)
    .map((h) => h.trim().toLowerCase())
    .filter(Boolean);
}

export function hostAllowed(url, hosts) {
  const u = new URL(url);
  return (u.protocol === "http:" || u.protocol === "https:") && (hosts.includes(u.hostname) || hosts.includes(u.host));
}

// Fetch an SVG icon from an allowlisted host. Redirects are followed by hand
// so every hop is checked against the list. Returns the SVG text.
export async function fetchRemoteIcon(url, { hosts, maxBytes = REMOTE_MAX_BYTES, timeoutMs = REMOTE_TIMEOUT_MS }) {
  const signal = AbortSignal.timeout(timeoutMs);
  let current = url;
  try {
    for (let hop = 0; hop < 5; hop++) {
      if (!hostAllowed(current, hosts)) throw new Error(`${current}: host not in --allow-remote-assets`);
      const res = await fetch(current, { redirect: "manual", signal });
      if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
        current = new URL(res.headers.get("location"), current).href;
        await res.body?.cancel();
        continue;
      }
      if (!res.ok) throw new Error(`${current}: HTTP ${res.status}`);
      const type = res.headers.get("content-type") ?? "";
      if (!type.startsWith("image/svg")) {
        await res.body?.cancel();
        throw new Error(`${current}: content type ${type || "(none)"} is not image/svg+xml`);
      }
      if (Number(res.headers.get("content-length")) > maxBytes) {
        await res.body?.cancel();
        throw new Error(`${current}: larger than ${maxBytes} bytes`);
      }
      const chunks = [];
      let size = 0;
      for await (const chunk of res.body) {
        size += chunk.length;
        if (size > maxBytes) throw new Error(`${current}: larger than ${maxBytes} bytes`);
        chunks.push(chunk);
      }
      return Buffer.concat(chunks).toString("utf8");
    }
    throw new Error(`${url}: too many redirects`);
  } catch (e) {
    if (signal.aborted) throw new Error(`${url}: timed out after ${timeoutMs / 1000}s`);
    throw e;
  }
}
