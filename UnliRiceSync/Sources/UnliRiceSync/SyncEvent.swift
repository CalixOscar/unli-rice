import Foundation
import SwiftData
import UnliRiceCore

/// The CloudKit-synced mirror of `Event`. One `SyncEvent` per `Event`, ever —
/// this project's append-only design (PROJECT_NOTES.md decision #1: notes are
/// never edited or deleted in place, every change is a new `Event`) is exactly
/// what CloudKit sync wants. Every device only ever *creates* records here,
/// never mutates one in place, so there is no field-level conflict for
/// CloudKit to reconcile — merging two devices' histories is just a union of
/// records, deduplicated by `id`.
///
/// SwiftData + CloudKit constraints that shaped this type (from Apple's
/// documented `ModelConfiguration(cloudKitDatabase:)` requirements — not
/// verified against a real build, there is no macOS 14 SDK available in the
/// environment that wrote this):
///   - No `@Attribute(.unique)`. CloudKit's schema has no concept of a unique
///     constraint, so `id` cannot be marked unique here the way it might be in
///     a local-only SwiftData model. Uniqueness is instead enforced by
///     `SyncCoordinator` at merge time, keyed on `id`.
///   - Every stored property must be optional or carry a default value.
///   - No non-optional relationships (this model has none — it's a flat
///     mirror of `Event`, which has none either).
@Model
public final class SyncEvent {
    public var id: UUID = UUID()
    public var noteId: UUID = UUID()
    public var timestamp: Date = Date()
    public var source: String = ""
    public var kindRaw: String = EventKind.created.rawValue
    public var title: String?
    public var text: String?
    public var tag: String?
    public var reason: String?
    public var relatedEventId: UUID?

    public init(event: Event) {
        id = event.id
        noteId = event.noteId
        timestamp = event.timestamp
        source = event.source
        kindRaw = event.kind.rawValue
        title = event.title
        text = event.text
        tag = event.tag
        reason = event.reason
        relatedEventId = event.relatedEventId
    }

    /// `EventKind` isn't stored directly — CloudKit's schema wants primitive
    /// types, not a Swift enum. An unrecognized `kindRaw` (a record written by
    /// a future app version with a case that doesn't exist yet here) falls
    /// back to `.created` rather than crashing or being dropped, matching how
    /// `Projector` already treats forward-compatibility elsewhere: read what
    /// you can, never refuse the whole record over one field.
    public var kind: EventKind {
        EventKind(rawValue: kindRaw) ?? .created
    }

    public func toEvent() -> Event {
        Event(
            id: id,
            noteId: noteId,
            timestamp: timestamp,
            source: source,
            kind: kind,
            title: title,
            text: text,
            tag: tag,
            reason: reason,
            relatedEventId: relatedEventId
        )
    }
}
