//
//  PinEnrichmentService.swift
//  OnePlan
//
//  Headless MKLocalSearch wrapper for reconciling streamed Gemini pins
//  against Apple Maps. One short network call per pin; returns nil on no
//  match so the caller can fall back to the model-emitted address.
//

import CoreLocation
import Foundation
import MapKit

@MainActor
final class PinEnrichmentService {
    // Per-session cache of city/country → MKCoordinateRegion. Populated lazily
    // the first time a pin in that city is enriched.
    private var regionCache: [String: MKCoordinateRegion] = [:]

    // Resolve a pin against Apple Maps. Returns the canonical address and
    // coordinate when MKLocalSearch returns a plausible match — meaning the
    // result is country-consistent AND (when we know the city) actually sits
    // inside or near the geocoded city region. Returns nil otherwise; the
    // caller keeps Gemini's emitted address and marks the pin unverified.
    //
    // Note: MKLocalSearch.Request.region biases ranking — it does NOT filter.
    // The post-search resultIsInRegion check is what actually rejects
    // cross-region false matches.
    func enrich(
        name: String,
        city: String?,
        country: String?
    ) async -> (address: String, coordinate: CLLocationCoordinate2D)? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedCity = city?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedCountry = country?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // Path 1: city-aware region-first.
        if let city = trimmedCity {
            if let region = await geocodedRegion(
                city: city, country: trimmedCountry
            ) {
                // Scan ALL returned candidates, not just mapItems.first.
                // Apple's POI ranking is non-deterministic across runs
                // (server-side ranking, recent-searches bias, cache state),
                // so the top result can flip between a wrong-region and
                // the correct in-region hit for the same query. Iterating
                // until we find a passing candidate gives a stable verdict.
                let items = await search(query: trimmedName, region: region)
                for item in items {
                    if countryMatches(item: item, pinCountry: trimmedCountry),
                       resultIsInRegion(item: item, city: city, region: region) {
                        return (
                            formatAddress(item.placemark),
                            item.placemark.coordinate
                        )
                    }
                }
                // Geocoder succeeded but NO candidate matched the region. A
                // global query would re-introduce the wrong-city bug, so we
                // stop and leave the pin unverified.
                return nil
            }
            // Geocoder itself failed (network blip, unknown city). Fall
            // through to Path 2 — best-effort beats dropping the pin.
        }

        // Path 2: no city, or geocoder failed → global query + country check.
        let combined = [trimmedName, trimmedCity, trimmedCountry]
            .compactMap { $0 }
            .joined(separator: ", ")
        let items = await search(query: combined, region: nil)
        for item in items {
            if countryMatches(item: item, pinCountry: trimmedCountry) {
                return (formatAddress(item.placemark), item.placemark.coordinate)
            }
        }
        return nil
    }

    // Tier-A name-match + Tier-B distance gate. Either tier passing accepts.
    private func resultIsInRegion(
        item: MKMapItem,
        city: String,
        region: MKCoordinateRegion
    ) -> Bool {
        let placemark = item.placemark

        // Tier A — name match. Locality first (most specific), then subAdmin
        // (district), then admin (province) — for Vietnamese addresses the
        // city often surfaces at the subAdmin level. Edge case: a very short
        // ward name that is a substring of the city ("Lat" inside "Da Lat")
        // can false-pass here; Tier B catches it.
        let candidateNames = [
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
        ]
        .compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }

        if candidateNames.contains(where: { name in
            name.localizedCaseInsensitiveContains(city)
                || city.localizedCaseInsensitiveContains(name)
        }) {
            return true
        }

        // Tier B — coordinate within 50 km of region centre. We pick 50 km
        // (vs the 30 km region span) to cover wards Apple Maps geocodes just
        // outside the tight city box, while still rejecting neighbouring
        // cities (Bao Loc is ~75 km from Da Lat; Cau Kieu in HCMC is
        // >250 km — both correctly rejected).
        let centre = CLLocation(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
        let candidate = CLLocation(
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
        return centre.distance(from: candidate) <= 50_000
    }

    private func search(
        query: String,
        region: MKCoordinateRegion?
    ) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let region {
            request.region = region
        }
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems
        } catch {
            return []
        }
    }

    private func geocodedRegion(
        city: String?,
        country: String?
    ) async -> MKCoordinateRegion? {
        let cityKey = city?.lowercased() ?? ""
        let countryKey = country?.lowercased() ?? ""
        let key = "\(cityKey)|\(countryKey)"
        guard !cityKey.isEmpty || !countryKey.isEmpty else { return nil }

        if let cached = regionCache[key] { return cached }

        let queryParts = [city, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !queryParts.isEmpty else { return nil }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(
                queryParts.joined(separator: ", ")
            )
            guard let location = placemarks.first?.location else { return nil }
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 30_000,
                longitudinalMeters: 30_000
            )
            regionCache[key] = region
            return region
        } catch {
            return nil
        }
    }

    private func countryMatches(item: MKMapItem, pinCountry: String?) -> Bool {
        guard let pinCountry = pinCountry?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pinCountry.isEmpty,
              let itemCountry = item.placemark.country?.trimmingCharacters(in: .whitespacesAndNewlines),
              !itemCountry.isEmpty else {
            // Either side missing → don't reject.
            return true
        }
        // Apple Maps returns the LOCALIZED country name (e.g. "Việt Nam") while
        // Gemini emits the English exonym ("Vietnam"). A plain case-insensitive
        // contains never matches across the space + diacritics, so EVERY
        // in-region candidate was wrongly rejected. Fold diacritics/case/spacing
        // first: "Việt Nam" and "Vietnam" both normalize to "vietnam".
        let a = Self.normalizedForMatch(pinCountry)
        let b = Self.normalizedForMatch(itemCountry)
        guard !a.isEmpty, !b.isEmpty else { return true }
        return a.contains(b) || b.contains(a)
    }

    // Strict variant for AI-suggested venues, whose names may be outright
    // hallucinated: a candidate is accepted only when its POI name actually
    // resembles the query, and there is NO global-search fallback — a
    // suggestion that can't be confidently verified inside the trip's region
    // should be discarded by the caller, not kept. Returns Apple's canonical
    // name so callers can overwrite the model's spelling.
    func enrichStrict(
        name: String,
        city: String?,
        country: String?
    ) async -> (
        name: String, address: String, coordinate: CLLocationCoordinate2D
    )? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedCity = city?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedCountry = country?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let region = await geocodedRegion(
            city: trimmedCity, country: trimmedCountry
        )
        let items = await search(query: trimmedName, region: region)
        for item in items {
            guard
                let itemName = item.name,
                Self.nameResembles(query: trimmedName, candidate: itemName),
                countryMatches(item: item, pinCountry: trimmedCountry)
            else { continue }
            if let city = trimmedCity, let region,
               !resultIsInRegion(item: item, city: city, region: region) {
                continue
            }
            return (
                itemName,
                formatAddress(item.placemark),
                item.placemark.coordinate
            )
        }
        return nil
    }

    // True when the normalized names contain each other, or when most (≥60%)
    // of the query's words appear in the candidate name. Guards against
    // MKLocalSearch's fuzzy matching returning an unrelated POI for a
    // hallucinated query.
    static func nameResembles(query: String, candidate: String) -> Bool {
        let normQuery = normalizedForMatch(query)
        let normCandidate = normalizedForMatch(candidate)
        guard !normQuery.isEmpty, !normCandidate.isEmpty else { return false }
        if normCandidate.contains(normQuery) || normQuery.contains(normCandidate) {
            return true
        }
        let tokens = query
            .folding(
                options: .diacriticInsensitive,
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        guard !tokens.isEmpty else { return false }
        let hits = tokens.filter { normCandidate.contains($0) }.count
        return Double(hits) / Double(tokens.count) >= 0.6
    }

    // Lowercase, strip diacritics, and drop everything non-alphanumeric so place
    // names compare across languages and scripts.
    static func normalizedForMatch(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func formatAddress(_ placemark: MKPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")

        // Rural POIs (national parks, waterfalls) often have no street AND no
        // locality — fall back through district/province so the address is
        // never just the country (or empty).
        let area = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea

        let parts: [String] = [street, area, placemark.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return parts.joined(separator: ", ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
