/**
 * Push endpoint allow-list (SSRF guard). The dispatcher POSTs to whatever endpoint a client
 * registers, so only well-known Web Push services are accepted.
 * An entry is an exact host ("fcm.googleapis.com") or a subdomain wildcard ("*.push.apple.com").
 */
export const DEFAULT_PUSH_HOSTS: readonly string[] = [
  "fcm.googleapis.com", // Chrome / Edge / Android (FCM)
  "android.googleapis.com", // legacy GCM endpoints
  "updates.push.services.mozilla.com", // Firefox
  "*.push.services.mozilla.com",
  "*.push.apple.com", // Safari / iOS web push (web.push.apple.com)
  "*.notify.windows.com", // WNS (legacy Edge)
];

/** Returns null when the endpoint is acceptable, otherwise a short reason. */
export type EndpointPolicy = (url: URL) => string | null;

const IPV4 = /^\d{1,3}(\.\d{1,3}){3}$/;

/** IP literals (private, loopback, link-local, public alike) and local-only names are never push services. */
export function isForbiddenHost(hostname: string): boolean {
  const h = hostname.toLowerCase();
  if (h.includes(":") || h.startsWith("[")) return true; // IPv6 literal
  if (IPV4.test(h) || /^\d+$/.test(h) || /^0x[0-9a-f]+$/.test(h)) return true; // IPv4 literal / numeric forms
  if (h === "localhost" || h.endsWith(".localhost")) return true;
  if (h.endsWith(".local") || h.endsWith(".internal") || h.endsWith(".lan") || !h.includes(".")) return true;
  return false;
}

const hostAllowed = (h: string, hosts: readonly string[]) =>
  hosts.some((p) => (p.startsWith("*.") ? h.endsWith(p.slice(1)) && h.length > p.length - 1 : h === p));

/** extraHosts: additional entries (deployment config such as EXTRA_PUSH_HOSTS, or test hosts). */
export function createEndpointPolicy(
  hosts: readonly string[] = DEFAULT_PUSH_HOSTS,
  extraHosts: readonly string[] = [],
): EndpointPolicy {
  const all = [...hosts, ...extraHosts].map((h) => h.toLowerCase());
  return (url) => {
    if (url.protocol !== "https:") return "must be https URL";
    if (url.username || url.password) return "must not contain credentials";
    if (url.port !== "" && url.port !== "443") return "must use the default https port";
    if (isForbiddenHost(url.hostname)) return "host is not allowed";
    if (!hostAllowed(url.hostname.toLowerCase(), all)) return "host is not an allowed push service";
    return null;
  };
}

export const defaultEndpointPolicy: EndpointPolicy = createEndpointPolicy();
