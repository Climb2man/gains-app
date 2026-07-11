import type { HealthSlice } from './slice.js';

export interface SliceStatus {
  loaded: boolean;
  as_of: string | null;
  /** Server-side wall-clock ms when the last push landed (for "synced 2m ago"). */
  received_at: number | null;
  counts: {
    nutrition_days: number;
    workout_days: number;
    whoop_days: number;
    weight_points: number;
  };
}

class SliceStore {
  private slice: HealthSlice | null = null;
  private receivedAt: number | null = null;

  set(slice: HealthSlice): void {
    this.slice = slice;
    this.receivedAt = Date.now();
  }

  /** Throws a typed "no data yet" error so tools return a clear message. */
  get(): HealthSlice {
    if (!this.slice) {
      throw new NoSliceError();
    }
    return this.slice;
  }

  clear(): void {
    this.slice = null;
    this.receivedAt = null;
  }

  status(): SliceStatus {
    const s = this.slice;
    return {
      loaded: s !== null,
      as_of: s?.as_of ?? null,
      received_at: this.receivedAt,
      counts: {
        nutrition_days: s?.nutrition.days.length ?? 0,
        workout_days: s?.workouts.days.length ?? 0,
        whoop_days: s?.whoop.days.length ?? 0,
        weight_points: s?.weight.points.length ?? 0,
      },
    };
  }
}

export class NoSliceError extends Error {
  constructor() {
    super(
      'No data has been synced yet. Open the Gains app on your phone and make sure Personal MCP is on. It pushes your data slice to this server.',
    );
    this.name = 'NoSliceError';
  }
}

export const store = new SliceStore();
