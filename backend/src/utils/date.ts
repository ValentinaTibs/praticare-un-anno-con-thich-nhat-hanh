export function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

const ROME_OFFSET = new Intl.DateTimeFormat('en-US', { timeZone: 'Europe/Rome', timeZoneName: 'longOffset' });

function romeOffsetMinutes(instant: Date) {
  const offset = ROME_OFFSET.formatToParts(instant).find((part) => part.type === 'timeZoneName')!.value;
  const match = /GMT([+-])(\d{2}):(\d{2})/.exec(offset);
  if (!match) return 0; // "GMT" alone means UTC+0
  const [, sign, hours, minutes] = match;
  return (sign === '+' ? 1 : -1) * (Number(hours) * 60 + Number(minutes));
}

const ROME_CALENDAR = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Rome',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

// The YYYY-MM-DD calendar date in Italy at this instant.
export function calendarDateInRome(instant: Date): string {
  return ROME_CALENDAR.format(instant);
}

// The instant when clocks in Italy show this HH:MM on a YYYY-MM-DD calendar date.
// A time skipped when clocks go forward falls one hour later.
export function wallTimeInRome(date: string, time: string): Date {
  const asUtc = new Date(`${date}T${time}:00.000Z`);
  const guess = addMinutes(asUtc, -romeOffsetMinutes(asUtc));
  return addMinutes(asUtc, -romeOffsetMinutes(guess));
}

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
