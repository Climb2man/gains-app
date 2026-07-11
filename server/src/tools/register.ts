import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { store } from "../store.js";
import type { HealthSlice } from "../slice.js";

function text(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data) }] };
}

function inRange(date: string, from?: string, to?: string): boolean {
  if (from && date < from) return false;
  if (to && date > to) return false;
  return true;
}

function round(n: number, dp = 1): number {
  const f = 10 ** dp;
  return Math.round(n * f) / f;
}

const rangeArgs = {
  from: z.string().optional().describe("Start date (inclusive), YYYY-MM-DD. Omit for no lower bound."),
  to: z.string().optional().describe("End date (inclusive), YYYY-MM-DD. Omit for no upper bound."),
} as const;

function latestDate(slice: HealthSlice): string | null {
  const all = [
    ...slice.nutrition.days.map((d) => d.date),
    ...slice.workouts.days.map((d) => d.date),
    ...slice.whoop.days.map((d) => d.date),
  ];
  if (all.length === 0) return null;
  return all.reduce((a, b) => (a > b ? a : b));
}

export function registerTools(server: McpServer): void {
  server.registerTool(
    "gains_status",
    {
      description:
        "Health of this server's data: whether a slice has been synced from the phone, when it was built (as_of), and how many days of each domain are loaded. Call this first if other tools say there's no data.",
    },
    async () => text(store.status()),
  );

  server.registerTool(
    "gains_profile",
    {
      description:
        "The user's own profile basics (name, sex, age, height, current weight) and their self-set daily goals (calories, macros, steps).",
    },
    async () => {
      const slice = store.get();
      return text(slice.profile ?? { note: "No profile in the synced slice." });
    },
  );

  server.registerTool(
    "gains_today",
    {
      description:
        "Composite snapshot for the most recent synced day: calories + macros eaten vs goals, Whoop recovery/sleep/strain/steps/calories-burned if connected, and any workouts.",
    },
    async () => {
      const slice = store.get();
      const date = latestDate(slice);
      if (!date) return text({ note: "No dated data in the synced slice yet." });
      const nutrition = slice.nutrition.days.find((d) => d.date === date) ?? null;
      const whoop = slice.whoop.days.find((d) => d.date === date) ?? null;
      const workouts = slice.workouts.days.find((d) => d.date === date)?.sessions ?? [];
      return text({
        date,
        nutrition,
        whoop,
        workouts,
        goals: slice.profile?.goals ?? null,
        weight_lb: slice.profile?.weight_lb ?? null,
        as_of: slice.as_of,
      });
    },
  );

  server.registerTool(
    "gains_nutrition",
    {
      description:
        "Daily food totals (calories, protein, carbs, fat, sugar, fiber, sodium, water) across a range, with the user's goals and a per-day average. Use for 'how many calories / how much protein' questions.",
      inputSchema: rangeArgs,
    },
    async ({ from, to }) => {
      const slice = store.get();
      const days = slice.nutrition.days
        .filter((d) => inRange(d.date, from, to))
        .sort((a, b) => a.date.localeCompare(b.date))
        .map((d) => ({
          date: d.date,
          calories: d.calories,
          protein_g: d.protein_g,
          carb_g: d.carb_g,
          fat_g: d.fat_g,
          sugar_g: d.sugar_g,
          fiber_g: d.fiber_g,
          sodium_mg: d.sodium_mg,
          water_ml: d.water_ml,
        }));
      const n = days.length;
      const avg = n === 0 ? null : {
        calories: round(days.reduce((s, d) => s + d.calories, 0) / n),
        protein_g: round(days.reduce((s, d) => s + d.protein_g, 0) / n),
        carb_g: round(days.reduce((s, d) => s + d.carb_g, 0) / n),
        fat_g: round(days.reduce((s, d) => s + d.fat_g, 0) / n),
      };
      return text({ days, average_per_day: avg, day_count: n, goals: slice.profile?.goals ?? null });
    },
  );

  server.registerTool(
    "gains_food_journal",
    {
      description:
        "The food-journal lines for a date or range: what the user typed, the resolved items with macros, and each item's assumptions note. Use for 'what exactly did I eat'. Some older days may carry totals only (no journal).",
      inputSchema: rangeArgs,
    },
    async ({ from, to }) => {
      const slice = store.get();
      const days = slice.nutrition.days
        .filter((d) => inRange(d.date, from, to) && d.journal && d.journal.length > 0)
        .sort((a, b) => a.date.localeCompare(b.date))
        .map((d) => ({ date: d.date, lines: d.journal ?? [] }));
      return text({ days });
    },
  );

  server.registerTool(
    "gains_workouts",
    {
      description:
        "The user's logged workout sessions across a range (title, raw text, parsed exercises). Empty if nothing was logged.",
      inputSchema: rangeArgs,
    },
    async ({ from, to }) => {
      const slice = store.get();
      const days = slice.workouts.days
        .filter((d) => inRange(d.date, from, to))
        .sort((a, b) => a.date.localeCompare(b.date));
      return text({ days });
    },
  );

  server.registerTool(
    "gains_whoop",
    {
      description:
        "Whoop daily metrics over a range: recovery %, HRV, resting heart rate, sleep hours + performance, day strain, calories burned, and steps. Empty if Whoop isn't linked.",
      inputSchema: rangeArgs,
    },
    async ({ from, to }) => {
      const slice = store.get();
      const days = slice.whoop.days
        .filter((d) => inRange(d.date, from, to))
        .sort((a, b) => a.date.localeCompare(b.date));
      return text({ days });
    },
  );

  server.registerTool(
    "gains_weight",
    {
      description:
        "The user's body-weight history (lb) over a range, plus body-fat % when logged and the net change across the range. Sorted oldest→newest. Use for weight-trend questions.",
      inputSchema: rangeArgs,
    },
    async ({ from, to }) => {
      const slice = store.get();
      const points = slice.weight.points
        .filter((p) => inRange(p.date, from, to))
        .sort((a, b) => a.date.localeCompare(b.date));
      const first = points[0];
      const last = points[points.length - 1];
      const change_lb = first && last && points.length >= 2 ? round(last.lb - first.lb) : null;
      return text({ points, change_lb });
    },
  );

  server.registerTool(
    "gains_streaks",
    {
      description:
        "The user's goal streaks: current run, longest run, and the last 7 days' hit rate against their self-set goals.",
    },
    async () => {
      const slice = store.get();
      return text(slice.streaks ?? { note: "No streak data in the synced slice." });
    },
  );

  server.registerTool(
    "gains_trend",
    {
      description:
        "A single metric as a date→value series, for plotting or correlating across domains. Pick one metric; optionally bound by date.",
      inputSchema: {
        metric: z
          .enum(["calories", "protein_g", "carb_g", "fat_g", "weight_lb", "recovery_pct", "hrv_ms", "resting_hr_bpm", "sleep_hours", "day_strain", "calories_burned", "steps"])
          .describe("Which metric to return as a time series."),
        ...rangeArgs,
      },
    },
    async ({ metric, from, to }) => {
      const slice = store.get();
      type Row = { date: string; value: number };
      const pick = (date: string, value: number | undefined): Row | null =>
        value !== undefined && inRange(date, from, to) ? { date, value } : null;

      const nutritionKeys = ["calories", "protein_g", "carb_g", "fat_g"] as const;
      let rows: Row[];
      if (metric === "weight_lb") {
        rows = slice.weight.points.map((p) => pick(p.date, p.lb)).filter((r): r is Row => r !== null);
      } else if ((nutritionKeys as readonly string[]).includes(metric)) {
        const key = metric as (typeof nutritionKeys)[number];
        rows = slice.nutrition.days.map((d) => pick(d.date, d[key])).filter((r): r is Row => r !== null);
      } else {
        const key = metric as "recovery_pct" | "hrv_ms" | "resting_hr_bpm" | "sleep_hours" | "day_strain" | "calories_burned" | "steps";
        rows = slice.whoop.days.map((d) => pick(d.date, d[key])).filter((r): r is Row => r !== null);
      }
      rows.sort((a, b) => a.date.localeCompare(b.date));
      return text({ metric, series: rows });
    },
  );
}
