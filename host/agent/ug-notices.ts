type Context = { ui: { notify(message: string, type: "info" | "warning" | "error"): void } };
type Pi = { on(event: "session_start", handler: (event: unknown, ctx: Context) => Promise<void>): void };

export default function (pi: Pi) {
  pi.on("session_start", async (_event, ctx) => {
    for (const line of (process.env.UG_NOTICES ?? "").split("\n")) {
      if (line.trim() === "") continue;
      ctx.ui.notify(line, "warning");
    }
  });
}
