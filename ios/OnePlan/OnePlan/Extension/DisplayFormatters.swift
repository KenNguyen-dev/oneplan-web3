//
//  DisplayFormatters.swift
//  OnePlan
//
//  Locale-aware *display* formatting helpers for the localization effort.
//
//  IMPORTANT — display vs. wire:
//  These helpers produce strings shown to the USER, so they follow the
//  current locale (Vietnamese, English, …). They must NOT be used to build
//  values sent to / parsed from the server. Wire formats (e.g. `yyyy-MM-dd`,
//  `HH:mm` sent to `createPlanItem`, ISO timestamps, dictionary keys) MUST
//  stay on fixed `Locale(identifier: "en_US_POSIX")` formatters at their own
//  call sites — do not route them through here.
//

import Foundation

enum DisplayFormatters {
    // MARK: - Dates

    /// Medium calendar date for labels, e.g. "Jun 2, 2026" / "2 thg 6, 2026".
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Month + day only, e.g. "Jun 2" / "2 thg 6". Used in compact rows.
    static func monthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Month + year, e.g. "Jun 2026" / "thg 6 2026". Used for "member since".
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year())
    }

    /// Short time-of-day for labels, e.g. "3:30 PM" / "15:30" (locale decides
    /// 12h vs 24h). Never use for the wire `startTime` — that stays POSIX.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Duration

    /// A recording / elapsed duration as minutes:seconds, e.g. "1:05".
    static func minutesSeconds(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }

    // MARK: - Distance

    /// A distance in meters rendered in the user's preferred units
    /// (auto-converts km↔miles by locale), e.g. "1.2 km" / "0.7 mi".
    static func distance(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
