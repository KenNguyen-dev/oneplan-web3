//
//  StorageUploadService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import UIKit

typealias UploadTarget = Components.Schemas.UploadTarget
typealias PresignedUrlDto = Components.Schemas.PresignedUrlDto
typealias UploadResultDto = Components.Schemas.UploadResultDto
typealias DownloadUrlDto = Components.Schemas.DownloadUrlDto

@MainActor
@Observable
final class StorageUploadService {
    var isUploading = false
    var uploadProgress: Double = 0
    var error: String?

    private var client: Client { APIClient.shared }

    /// Full upload flow: compress -> presign -> PUT to S3 -> confirm
    func uploadImage(
        _ image: UIImage,
        target: UploadTarget,
        entityId: Int,
        caption: String? = nil
    ) async throws -> UploadResultDto {
        isUploading = true
        uploadProgress = 0
        error = nil
        defer { isUploading = false }

        do {
            // 1. Compress image to JPEG
            guard let imageData = image.jpegData(compressionQuality: 0.85) else {
                throw UploadError.compressionFailed
            }
            uploadProgress = 0.1

            // 2. Request presigned URL from server
            let presignResponse = try await client.createPresignedUpload(
                .init(body: .json(.init(
                    target: .init(value1: target),
                    entityId: entityId,
                    contentType: "image/jpeg"
                )))
            )
            let presigned = try presignResponse.ok.body.json
            uploadProgress = 0.2

            // 3. PUT directly to Supabase Storage using presigned URL
            guard let uploadUrl = URL(string: presigned.uploadUrl) else {
                throw UploadError.invalidPresignedUrl
            }

            var request = URLRequest(url: uploadUrl)
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.httpBody = imageData

            let (_, urlResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw UploadError.s3UploadFailed
            }
            uploadProgress = 0.8

            // 4. Confirm upload with server
            let confirmResponse = try await client.confirmUpload(
                .init(body: .json(.init(
                    target: .init(value1: target),
                    entityId: entityId,
                    objectKey: presigned.objectKey,
                    caption: caption
                )))
            )
            let result = try confirmResponse.ok.body.json
            uploadProgress = 1.0

            return result
        } catch let uploadError as UploadError {
            self.error = uploadError.errorDescription
            throw uploadError
        } catch {
            self.error = String(localized: "Upload failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Upload audio flow: presign -> PUT to S3 -> confirm -> return objectKey
    func uploadAudio(
        _ audioData: Data,
        tripId: Int,
        contentType: String = "audio/mp4"
    ) async throws -> String {
        isUploading = true
        uploadProgress = 0
        error = nil
        defer { isUploading = false }

        do {
            // 1. Request presigned URL
            let presignResponse = try await client.createPresignedUpload(
                .init(body: .json(.init(
                    target: .init(value1: .plan_hyphen_item_hyphen_voice),
                    entityId: tripId,
                    contentType: contentType
                )))
            )
            let presigned = try presignResponse.ok.body.json
            uploadProgress = 0.2

            // 2. PUT to S3
            guard let uploadUrl = URL(string: presigned.uploadUrl) else {
                throw UploadError.invalidPresignedUrl
            }
            var request = URLRequest(url: uploadUrl)
            request.httpMethod = "PUT"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = audioData

            let (_, urlResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw UploadError.s3UploadFailed
            }
            uploadProgress = 0.8

            // 3. Confirm upload
            let confirmResponse = try await client.confirmUpload(
                .init(body: .json(.init(
                    target: .init(value1: .plan_hyphen_item_hyphen_voice),
                    entityId: tripId,
                    objectKey: presigned.objectKey
                )))
            )
            _ = try confirmResponse.ok.body.json
            uploadProgress = 1.0

            return presigned.objectKey
        } catch let uploadError as UploadError {
            self.error = uploadError.errorDescription
            throw uploadError
        } catch {
            self.error = String(localized: "Upload failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Get a fresh presigned download URL for a stored object key
    func imageURL(for objectKey: String) async throws -> URL {
        let response = try await client.getDownloadUrl(
            .init(query: .init(objectKey: objectKey))
        )
        let dto = try response.ok.body.json
        guard let url = URL(string: dto.url) else {
            throw UploadError.invalidDownloadUrl
        }
        return url
    }

    enum UploadError: Error, LocalizedError {
        case compressionFailed
        case invalidPresignedUrl
        case s3UploadFailed
        case invalidDownloadUrl

        var errorDescription: String? {
            switch self {
            case .compressionFailed: "Failed to compress image"
            case .invalidPresignedUrl: "Invalid upload URL received"
            case .s3UploadFailed: "Failed to upload to storage"
            case .invalidDownloadUrl: "Invalid download URL received"
            }
        }
    }
}
