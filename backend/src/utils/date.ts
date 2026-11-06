export function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

const ROME_OFFSET = new Intl.DateTimeFormat('en-US', { timeZone: 'Europe/Rome', timeZoneName: 'longOffset' });

// The instant of 00:00 in Italy on a YYYY-MM-DD calendar date, or null if no such date exists.
export function startOfDayInRome(date: string): Date | null {
  const utcMidnight = new Date(`${date}T00:00:00.000Z`);
  if (Number.isNaN(utcMidnight.getTime()) || utcMidnight.toISOString().slice(0, 10) !== date) return null;

  // Clocks change at 01:00 UTC, so the offset at 00:00 UTC is still the one in force at midnight in Italy.
  const offset = ROME_OFFSET.formatToParts(utcMidnight).find((part) => part.type === 'timeZoneName')!.value;
  const [, sign, hours, minutes] = /GMT([+-])(\d{2}):(\d{2})/.exec(offset)!;
  const offsetMinutes = (sign === '+' ? 1 : -1) * (Number(hours) * 60 + Number(minutes));
  return addMinutes(utcMidnight, -offsetMinutes);
}
