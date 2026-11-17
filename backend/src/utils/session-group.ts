// The session user's group, as both /api/users/me and the login send it. The
// app shows the journey day ("Giorno N di D") from startedAt and durationDays.
export const sessionGroupSelect = {
  select: { id: true, startedAt: true, endedAt: true, cycle: { select: { durationDays: true } } },
} as const;

type SelectedGroup = { id: string; startedAt: Date; endedAt: Date | null; cycle: { durationDays: number } };

export function sessionGroup(group: SelectedGroup | null | undefined) {
  if (!group) return null;
  const { cycle, ...rest } = group;
  return { ...rest, durationDays: cycle.durationDays };
}
