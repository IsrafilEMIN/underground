import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { readHostFacts } from "./facts.ts";

const HOST = "127.0.0.1";
const GENERATION = 1;
const ETAG = `"${GENERATION}"`;
const MAX_WAIT_MS = 60_000;

const facts = readHostFacts();
const addressesFile = join(facts.root, "code/addresses");
const gatewayTokenFile = join(homedir(), ".omp/auth-gateway.token");

type Reply = { status: number; etag?: string; body?: string };

function json(status: number, value: unknown): Reply {
  return { status, body: JSON.stringify(value) };
}

async function gatewayUsage(): Promise<Reply> {
  const gateway = /^gateway=(\d{1,3}(?:\.\d{1,3}){3}:\d{1,5})$/m.exec(await readFile(addressesFile, "utf8"))?.[1];
  if (gateway === undefined) return json(502, { error: "addresses file: no gateway=<ip>:<port> line" });
  const token = (await readFile(gatewayTokenFile, "utf8")).trim();

  if (!/^[\x21-\x7e]+$/.test(token)) return json(502, { error: "gateway token file does not hold one printable token" });
  const reply = await fetch(`http://${gateway}/v1/usage`, { headers: { Authorization: `Bearer ${token}` } });
  return { status: reply.status, body: await reply.text() };
}

async function respond(method: string, rawUrl: string, ifNoneMatch: string | undefined): Promise<Reply> {
  const url = new URL(rawUrl, "http://usage-broker");
  if (method === "GET" && url.pathname === "/v1/healthz") return json(200, { ok: true });
  if (method === "GET" && url.pathname === "/v1/snapshot") {
    if (ifNoneMatch === ETAG) {
      const wait = Math.min(Math.max(Number(url.searchParams.get("wait")) || 0, 0), MAX_WAIT_MS);
      const { promise, resolve } = Promise.withResolvers<void>();
      setTimeout(resolve, wait);
      await promise;
      return { status: 304, etag: ETAG };
    }
    const at = Date.now();
    return {
      ...json(200, {
        generation: GENERATION,
        generatedAt: at,
        serverNowMs: at,
        refresher: { enabled: false, intervalMs: 60_000, skewMs: 0, nextSweepInMs: 60_000 },
        credentials: [],
      }),
      etag: ETAG,
    };
  }
  if (method === "GET" && url.pathname === "/v1/usage") {
    try {
      return await gatewayUsage();
    } catch (error) {
      return json(502, { error: `gateway usage failed: ${error instanceof Error ? error.message : String(error)}` });
    }
  }
  if (method === "POST" && url.pathname === "/v1/usage/observed") return { status: 204 };
  return json(404, { error: "the usage broker serves usage only" });
}

createServer(async (req, res) => {
  req.resume();
  const header = req.headers["if-none-match"];
  const reply = await respond(req.method ?? "GET", req.url ?? "/", Array.isArray(header) ? header[0] : header);
  res.statusCode = reply.status;
  if (reply.etag !== undefined) res.setHeader("etag", reply.etag);
  if (reply.body !== undefined) res.setHeader("content-type", "application/json");
  res.end(reply.body);
}).listen(facts.usageBrokerPort, HOST, () => {
  process.stdout.write(`usage-broker: listening on ${HOST}:${facts.usageBrokerPort}\n`);
});
