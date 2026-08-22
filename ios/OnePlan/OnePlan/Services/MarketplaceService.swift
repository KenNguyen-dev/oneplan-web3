//
//  MarketplaceService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import UIKit

typealias MarketplaceListingDto = Components.Schemas.MarketplaceListingDto
typealias MarketItemDto = Components.Schemas.MarketItemDto
typealias CreateMarketplaceListingDto = Components.Schemas.CreateMarketplaceListingDto
typealias CreateMarketItemDto = Components.Schemas.CreateMarketItemDto
typealias UpdateMarketplaceListingDto = Components.Schemas.UpdateMarketplaceListingDto

struct UpdateTripResult {
    let coverImageUrl: String?
}

@MainActor
@Observable
final class MarketplaceService {
    var isPublishing = false

    private var client: Client { APIClient.shared }
    private let uploadService = StorageUploadService()

    /// Publishes a trip's plan items as a marketplace listing.
    /// Uses compact day numbering: only dates with plans get sequential dayNumbers.
    func publishTrip(
        name: String,
        description: String?,
        selectedCoverImage: UIImage?,
        coverImageUrl: String?,
        cityId: Int?,
        stateId: Int?,
        countryId: Int?,
        price: Double,
        currency: Components.Schemas.Currency,
        durationDays: Int,
        tags: [Components.Schemas.ListingTag],
        planItems: [PlanItemDto],
        planItemImagesById: [Int: [UIImage]]
    ) async -> Bool {
        isPublishing = true
        defer { isPublishing = false }

        var createdListingId: Int?

        do {
            // 1. Create the listing
            let listingBody = Components.Schemas.CreateMarketplaceListingDto(
                name: name,
                description: description,
                coverImageUrl: coverImageUrl,
                cityId: cityId,
                stateId: stateId,
                countryId: countryId,
                price: price,
                currency: .init(value1: currency),
                durationDays: durationDays,
                tags: tags
            )

            let listingResponse = try await client.createListing(
                .init(body: .json(listingBody))
            )
            let listing = try listingResponse.created.body.json
            let listingId = listing.id
            createdListingId = listingId

            // 2. Upload selected cover image and patch listing with the uploaded object key.
            if let selectedCoverImage {
                let uploadedCover = try await uploadService.uploadImage(
                    selectedCoverImage,
                    target: .market_hyphen_item_hyphen_image,
                    entityId: Int(listingId)
                )
                let coverPatch = UpdateMarketplaceListingDto(
                    coverImageUrl: uploadedCover.objectKey
                )
                _ = try await client.updateListing(
                    .init(path: .init(id: listingId), body: .json(coverPatch))
                )
            }

            // 3. Compute compact dayNumbers (skip gap days)
            let sortedDates = Set(planItems.compactMap(\.planDate)).sorted()
            var dateToDayNumber: [String: Int] = [:]
            for (index, date) in sortedDates.enumerated() {
                dateToDayNumber[date] = index + 1
            }

            // 4. Upload item images and create each market item
            for item in planItems {
                guard let planDate = item.planDate,
                      let dayNumber = dateToDayNumber[planDate] else { continue }
                let itemImages = Array((planItemImagesById[item.id] ?? []).prefix(5))
                let imageObjectKeys = try await uploadPlanItemImages(
                    itemImages,
                    listingId: Int(listingId)
                )

                let itemBody = Components.Schemas.CreateMarketItemDto(
                    dayNumber: dayNumber,
                    title: item.title,
                    description: item.description,
                    location: item.location,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    address: item.address,
                    startTime: item.startTime,
                    category: item.category.map { .init(value1: $0.value1) },
                    imageUrls: imageObjectKeys,
                    sortOrder: Int(item.sortOrder)
                )

                _ = try await client.createMarketItem(
                    .init(
                        path: .init(listingId: listingId),
                        body: .json(itemBody)
                    )
                )
            }

            return true
        } catch {
            // Best effort rollback if publish failed after listing creation.
            if let listingId = createdListingId {
                do {
                    _ = try await client.deleteListing(.init(path: .init(id: listingId)))
                } catch {
                    print("MarketplaceService.publishTrip rollback failed: \(error)")
                }
            }
            print("MarketplaceService.publishTrip error: \(error)")
            return false
        }
    }

    /// Updates an existing marketplace listing and its items.
    func updateTrip(
        listingId: Int,
        name: String,
        description: String?,
        selectedCoverImage: UIImage?,
        cityId: Int?,
        stateId: Int?,
        countryId: Int?,
        price: Double,
        currency: Components.Schemas.Currency,
        durationDays: Int,
        tags: [Components.Schemas.ListingTag],
        planItems: [PlanItemDto],
        existingItemIds: Set<Int>,
        planItemImagesById: [Int: [UIImage]]
    ) async -> UpdateTripResult? {
        isPublishing = true
        defer { isPublishing = false }

        do {
            // 1. Build listing patch
            var listingPatch = UpdateMarketplaceListingDto(
                name: name,
                description: description,
                cityId: cityId,
                stateId: stateId,
                countryId: countryId,
                price: price,
                currency: .init(value1: currency),
                durationDays: durationDays,
                tags: tags
            )

            // 2. Upload cover image if changed
            if let selectedCoverImage {
                let uploadedCover = try await uploadService.uploadImage(
                    selectedCoverImage,
                    target: .market_hyphen_item_hyphen_image,
                    entityId: listingId
                )
                listingPatch.coverImageUrl = uploadedCover.objectKey
            }

            let updateResponse = try await client.updateListing(
                .init(path: .init(id: listingId), body: .json(listingPatch))
            )
            let updatedListing = try updateResponse.ok.body.json
            let newCoverImageUrl = updatedListing.coverImageUrl

            // 3. Compute compact dayNumbers
            let sortedDates = Set(planItems.compactMap(\.planDate)).sorted()
            var dateToDayNumber: [String: Int] = [:]
            for (index, date) in sortedDates.enumerated() {
                dateToDayNumber[date] = index + 1
            }

            let retainedItemIds = Set(planItems.map(\.id))

            // 4. Update existing items and create new ones
            for item in planItems {
                guard let planDate = item.planDate,
                      let dayNumber = dateToDayNumber[planDate] else { continue }
                let itemImages = Array((planItemImagesById[item.id] ?? []).prefix(5))

                if existingItemIds.contains(item.id) {
                    var updateBody = Components.Schemas.UpdateMarketItemDto(
                        dayNumber: dayNumber,
                        title: item.title,
                        description: item.description,
                        location: item.location,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        address: item.address,
                        startTime: item.startTime,
                        category: item.category.map { .init(value1: $0.value1) },
                        sortOrder: Int(item.sortOrder)
                    )

                    if !itemImages.isEmpty {
                        updateBody.imageUrls = try await uploadPlanItemImages(
                            itemImages, listingId: listingId
                        )
                    }

                    _ = try await client.updateMarketItem(
                        .init(
                            path: .init(listingId: listingId, id: item.id),
                            body: .json(updateBody)
                        )
                    )
                } else {
                    let imageObjectKeys = try await uploadPlanItemImages(
                        itemImages, listingId: listingId
                    )

                    let itemBody = Components.Schemas.CreateMarketItemDto(
                        dayNumber: dayNumber,
                        title: item.title,
                        description: item.description,
                        location: item.location,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        address: item.address,
                        startTime: item.startTime,
                        category: item.category.map { .init(value1: $0.value1) },
                        imageUrls: imageObjectKeys,
                        sortOrder: Int(item.sortOrder)
                    )

                    _ = try await client.createMarketItem(
                        .init(
                            path: .init(listingId: listingId),
                            body: .json(itemBody)
                        )
                    )
                }
            }

            let deletedItemIds = existingItemIds.subtracting(retainedItemIds)
            for itemId in deletedItemIds {
                _ = try await client.deleteMarketItem(
                    .init(path: .init(listingId: listingId, id: itemId))
                )
            }

            return UpdateTripResult(coverImageUrl: newCoverImageUrl)
        } catch {
            print("MarketplaceService.updateTrip error: \(error)")
            return nil
        }
    }

    func deleteListing(listingId: Int) async -> Bool {
        isPublishing = true
        defer { isPublishing = false }

        do {
            _ = try await client.deleteListing(.init(path: .init(id: listingId)))
            return true
        } catch {
            print("MarketplaceService.deleteListing error: \(error)")
            return false
        }
    }

    private func uploadPlanItemImages(
        _ images: [UIImage],
        listingId: Int
    ) async throws -> [String] {
        var objectKeys: [String] = []
        objectKeys.reserveCapacity(images.count)

        for image in images {
            let uploadResult = try await uploadService.uploadImage(
                image,
                target: .market_hyphen_item_hyphen_image,
                entityId: listingId
            )
            objectKeys.append(uploadResult.objectKey)
        }

        return objectKeys
    }
}
