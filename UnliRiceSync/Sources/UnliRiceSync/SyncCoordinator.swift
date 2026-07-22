import Foundation
import SwiftData
import UnliRiceCore

/// Two-way bridge between the local append-only `events.jsonl` (the source of
/// truth every MCP client and the GUI already read/write — PROJECT_NOTES.md
/// decision #1) and a CloudKit-backed SwiftData store, which is the thing that
/// actually moves bytes between devices signed into the same iCloud account.
///
/// Deliberately holds no opinion about *when* to run. This project already has
/// a pure decision function for "should something run now" (`RoutineScheduler`)
/// separate from the thing that runs it (`RoutineDriver`); `SyncCoordinator`
/// plays the second role only. Call `sync()` from wherever already decides —
/// app launch, `RoutineDriver`, or a CloudKit remote-change notification.
///
/// Not yet built or run against a real container — there is no macOS 14 SDK in
/// the environment that wrote this. Treat this as a draft to compile and
/// exercise on the Mac, not as verified working code.
public actor SyncCoordinator {
    private let container: ModelContainer
    private let store: EventStore

    public init(container: ModelContainer, store: EventStore) {
        self.container = container
        self.store = store
    }

    /// Builds the CloudKit-backed container and wraps it. Call this from app
    /// startup, after the iCloud container entitlement exists (see repo root
    /// `PROJECT_NOTES.md`, deferred item #4, and this package's README) —
    /// without the entitlement this throws rather than silently degrading to a
    /// local-only store. A sync layer that looks connected but isn't is worse
    /// than one that visibly fails: the same reasoning behind this project's
    /// `NoticeStore` never collapsing a failure into its success case.
    public static func makeCloudKitBacked(store: EventStore) throws -> SyncCoordinator {
        let schema = Schema([SyncEvent.self])
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SyncCoordinator(container: container, store: store)
    }

    /// Pulls anything CloudKit has that the local log doesn't, appends it in
    /// timestamp order, then pushes anything the local log has that CloudKit
    /// doesn't. Both directions are idempotent, keyed on `Event.id` — a UUID
    /// minted once at creation (`Event.init`) and never reused — so running
    /// this twice in a row, or from two devices at once, converges instead of
    /// duplicating.
    ///
    /// Pull runs before push on purpose: a device that just woke up from being
    /// offline should fold in everyone else's history before deciding what of
    /// its own is missing remotely, so a long-offline device doesn't shove a
    /// backlog upstream ahead of catching up downstream.
    public func sync() async throws {
        try await pull()
        try push()
    }

    private func pull() async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SyncEvent>(sortBy: [SortDescriptor(\.timestamp)])
        let remote = try context.fetch(descriptor)

        let localIds = Set(try store.readAll().map(\.id))
        let missing = remote
            .map { $0.toEvent() }
            .filter { !localIds.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }

        // EventStore.append is per-event and flock-serialized against every
        // other writer (other MCP client processes included) — see its doc
        // comment. Folding remote events in one at a time, in order, is what
        // keeps this consistent with how every other writer already appends.
        for event in missing {
            try store.append(event)
        }
    }

    private func push() throws {
        let context = ModelContext(container)
        let remoteIds = Set(try context.fetch(FetchDescriptor<SyncEvent>()).map(\.id))

        let missing = try store.readAll().filter { !remoteIds.contains($0.id) }
        guard !missing.isEmpty else { return }

        for event in missing {
            context.insert(SyncEvent(event: event))
        }
        try context.save()
    }
}
