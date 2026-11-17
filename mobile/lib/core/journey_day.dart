/// The day of the journey that [at] falls on, counting the day of [startedAt]
/// as day 1. Calendar days in local time, whatever the hour.
int journeyDay(DateTime startedAt, DateTime at) {
  final start = startedAt.toLocal();
  final day = at.toLocal();
  // UTC dates, so a daylight saving change does not shorten a day.
  return DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays + 1;
}
