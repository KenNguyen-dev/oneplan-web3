//
//  AnalyticsEvent.swift
//  OnePlan
//

import Foundation

/// Single source of truth for analytics event names: the OpenAPI-generated
/// enum, which mirrors the server's Prisma `AnalyticsEventName` enum.
///
/// Adding a new event is a one-step change on iOS: update the server enum
/// and run `pnpm openapi:generate`. The Xcode build plugin regenerates
/// `Components.Schemas.TrackEventDto.eventNamePayload` and the new case
/// becomes available here automatically.
typealias AnalyticsEvent = Components.Schemas.TrackEventDto.eventNamePayload
