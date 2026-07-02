import Contacts
import Foundation
import UIKit

// MARK: - Lookup Actor

/// Performs blocking CNContactStore calls off the main thread.
private actor ContactsLookupActor {
    private let store = CNContactStore()

    private static let keys: [CNKeyDescriptor] = [
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]

    /// Returns thumbnail image data for the best matching contact, or nil if not found.
    func thumbnailData(email: String?, name: String) -> Data? {
        var contact: CNContact?

        // 1. Try exact email match first — most reliable
        if let email {
            contact = (try? store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingEmailAddress: email),
                keysToFetch: Self.keys
            ))?.first
        }

        // 2. Fall back to name match
        if contact == nil, !name.isEmpty {
            contact = (try? store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingName: name),
                keysToFetch: Self.keys
            ))?.first
        }

        return contact?.thumbnailImageData
    }
}

// MARK: - Service

/// Manages Contacts permission and provides cached attendee photos.
@MainActor
final class ContactsService: ObservableObject {

    @Published private(set) var authorizationStatus: CNAuthorizationStatus =
        CNContactStore.authorizationStatus(for: .contacts)

    private var cache: [String: UIImage?] = [:]
    private let lookupActor = ContactsLookupActor()

    // MARK: – Permission

    /// Requests Contacts access if not yet determined; updates `authorizationStatus`.
    func requestAccess() async {
        let current = CNContactStore.authorizationStatus(for: .contacts)
        guard current == .notDetermined else {
            authorizationStatus = current
            return
        }
        do {
            let store = CNContactStore()
            let granted = try await store.requestAccess(for: .contacts)
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            authorizationStatus = .denied
        }
    }

    // MARK: – Photo lookup

    /// Returns the cached contact thumbnail for an attendee, or nil if unavailable.
    func photo(for attendee: Attendee) async -> UIImage? {
        let key = attendee.email ?? attendee.id

        // Return cached result (including confirmed misses stored as nil)
        if let cached = cache[key] { return cached }

        guard authorizationStatus == .authorized else {
            return nil
        }

        let data = await lookupActor.thumbnailData(email: attendee.email, name: attendee.name)
        let image = data.flatMap { UIImage(data: $0) }
        cache[key] = image
        return image
    }
}
