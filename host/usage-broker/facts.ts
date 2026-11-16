import { readFileSync } from "node:fs";
import { join } from "node:path";

type HostFacts = { usageBrokerPort: number; gatewayPort: number };

const file = join(import.meta.dirname, "../facts");

export function readHostFacts(): HostFacts {
  const values = new Map<string, string>();
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const at = line.indexOf("=");
    if (at > 0) values.set(line.slice(0, at), line.slice(at + 1));
  }
  const need = (key: string): string => {
    const value = values.get(key);
    if (value === undefined || value === "") throw new Error(`${file} has no ${key}`);
    return value;
  };
  const port = (key: string): number => {
    const value = Number(need(key));
    if (!Number.isInteger(value) || value < 1 || value > 65535) throw new Error(`${file} has ${key} ${need(key)}, which is not a port`);
    return value;
  };
  return { usageBrokerPort: port("usage_broker_port"), gatewayPort: port("gateway_port") };
}
