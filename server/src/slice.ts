import { z } from "zod";

const Goals = z.object({
  calories: z.number(),
  protein_g: z.number(),
  carb_g: z.number(),
  fat_g: z.number(),
  steps: z.number().optional(),
});

const Profile = z.object({
  name: z.string().nullable().optional(),
  sex: z.string().optional(),
  age_years: z.number().optional(),
  height: z.string().optional(),
  weight_lb: z.number().optional(),
  goals: Goals.optional(),
});

const Streaks = z.object({
  current_days: z.number(),
  longest_days: z.number(),
  last7: z.object({ hits: z.number(), total: z.number() }),
});

const JournalItem = z.object({
  name: z.string(),
  calories: z.number(),
  protein_g: z.number(),
  carb_g: z.number(),
  fat_g: z.number(),
  is_water: z.boolean().optional(),
  assumptions: z.string().nullable().optional(),
  confidence: z.number().nullable().optional(),
});

const JournalLine = z.object({
  text: z.string(),
  logged_at: z.string().optional(),
  status: z.string().optional(),
  items: z.array(JournalItem).default([]),
});

const NutritionDay = z.object({
  date: z.string(),
  calories: z.number(),
  protein_g: z.number(),
  carb_g: z.number(),
  fat_g: z.number(),
  sugar_g: z.number().optional(),
  fiber_g: z.number().optional(),
  sodium_mg: z.number().optional(),
  water_ml: z.number().optional(),
  journal: z.array(JournalLine).optional(),
});

const WorkoutSession = z.object({
  title: z.string().nullable().optional(),
  logged_at: z.string().optional(),
  raw: z.string().optional(),
  exercises: z.array(z.string()).default([]),
});

const WorkoutDay = z.object({
  date: z.string(),
  sessions: z.array(WorkoutSession).default([]),
});

const WhoopDay = z.object({
  date: z.string(),
  recovery_pct: z.number().optional(),
  hrv_ms: z.number().optional(),
  resting_hr_bpm: z.number().optional(),
  sleep_hours: z.number().optional(),
  sleep_performance_pct: z.number().optional(),
  day_strain: z.number().optional(),
  calories_burned: z.number().optional(),
  steps: z.number().optional(),
});

const WeightPoint = z.object({
  date: z.string(),
  lb: z.number(),
  body_fat_pct: z.number().optional(),
});

export const HealthSlice = z.object({
  as_of: z.string(),
  timezone: z.string().optional(),
  profile: Profile.optional(),
  streaks: Streaks.optional(),
  nutrition: z.object({ days: z.array(NutritionDay).default([]) }).default({ days: [] }),
  workouts: z.object({ days: z.array(WorkoutDay).default([]) }).default({ days: [] }),
  whoop: z.object({ days: z.array(WhoopDay).default([]) }).default({ days: [] }),
  weight: z.object({ points: z.array(WeightPoint).default([]) }).default({ points: [] }),
});

export type HealthSlice = z.infer<typeof HealthSlice>;
export type NutritionDay = z.infer<typeof NutritionDay>;
export type WorkoutDay = z.infer<typeof WorkoutDay>;
export type WhoopDay = z.infer<typeof WhoopDay>;
export type WeightPoint = z.infer<typeof WeightPoint>;
