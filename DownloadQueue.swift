// Centralized Download Queue for Manifests, DLCs, Depot Manifests, and Game Fixes.
import Foundation

enum DownloadItemStatus: String, Sendable {
    case queued = "queued"
    case downloading = "downloading"
    case installing = "installing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"

    var isActive: Bool {
        self == .queued || self == .downloading || self == .installing
    }

    var wireName: String {
        switch self {
        case .queued: return "queued"
        case .downloading: return "downloading"
        case .installing: return "processing"
        case .completed: return "done"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }
}

final class DownloadQueueItem: @unchecked Sendable {
    let id = UUID()
    let dedupeKey: String
    let appId: Int
    let title: String
    let subtitle: String

    var status: DownloadItemStatus = .queued
    var bytesRead: Int64 = 0
    var totalBytes: Int64? = nil
    var message: String? = nil

    let work: @Sendable (DownloadQueueItem) async throws -> String
    let onFinished: (@Sendable (DownloadQueueItem, Bool) -> Void)?
    var task: Task<Void, Never>?

    init(
        dedupeKey: String,
        appId: Int,
        title: String,
        subtitle: String,
        work: @escaping @Sendable (DownloadQueueItem) async throws -> String,
        onFinished: (@Sendable (DownloadQueueItem, Bool) -> Void)? = nil
    ) {
        self.dedupeKey = dedupeKey
        self.appId = appId
        self.title = title
        self.subtitle = subtitle
        self.work = work
        self.onFinished = onFinished
    }

    var progressFraction: Double {
        guard let totalBytes, totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(bytesRead) / Double(totalBytes)))
    }

    var isIndeterminate: Bool {
        totalBytes == nil || (totalBytes ?? 0) <= 0
    }
}

final class DownloadQueue: @unchecked Sendable {
    static let shared = DownloadQueue()
    static let queueDidChangeNotification = Notification.Name("MacsteamDownloadQueueDidChange")

    private let lock = NSLock()
    private var _items: [DownloadQueueItem] = []

    var items: [DownloadQueueItem] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    var activeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _items.filter { $0.status.isActive }.count
    }

    private init() {}

    func findActive(dedupeKey: String) -> DownloadQueueItem? {
        lock.lock(); defer { lock.unlock() }
        return _items.first { $0.status.isActive && $0.dedupeKey.caseInsensitiveCompare(dedupeKey) == .orderedSame }
    }

    @discardableResult
    func enqueue(_ item: DownloadQueueItem) -> DownloadQueueItem {
        lock.lock()
        if let existing = _items.first(where: { $0.status.isActive && $0.dedupeKey.caseInsensitiveCompare(item.dedupeKey) == .orderedSame }) {
            lock.unlock()
            return existing
        }
        _items.insert(item, at: 0)
        lock.unlock()
        notifyChanged()
        start(item)
        return item
    }

    private func start(_ item: DownloadQueueItem) {
        item.status = .downloading
        notifyChanged()

        item.task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let msg = try await item.work(item)
                if Task.isCancelled {
                    self.finish(item, status: .cancelled, message: L10n.isFrench ? "Annulé" : "Cancelled")
                    return
                }
                self.finish(item, status: .completed, message: msg)
            } catch is CancellationError {
                self.finish(item, status: .cancelled, message: L10n.isFrench ? "Annulé" : "Cancelled")
            } catch {
                self.finish(item, status: .failed, message: error.localizedDescription)
            }
        }
    }

    func updateProgress(for item: DownloadQueueItem, bytesRead: Int64, totalBytes: Int64?) {
        item.bytesRead = bytesRead
        item.totalBytes = totalBytes
        notifyChanged()
    }

    func setInstalling(_ item: DownloadQueueItem) {
        item.status = .installing
        notifyChanged()
    }

    func cancel(_ item: DownloadQueueItem) {
        guard item.status.isActive else { return }
        item.task?.cancel()
        finish(item, status: .cancelled, message: L10n.isFrench ? "Annulé" : "Cancelled")
    }

    func retry(_ item: DownloadQueueItem) {
        lock.lock()
        _items.removeAll { $0.id == item.id }
        lock.unlock()
        let fresh = DownloadQueueItem(
            dedupeKey: item.dedupeKey,
            appId: item.appId,
            title: item.title,
            subtitle: item.subtitle,
            work: item.work,
            onFinished: item.onFinished
        )
        enqueue(fresh)
    }

    func removeInactive(_ item: DownloadQueueItem) {
        guard !item.status.isActive else { return }
        lock.lock()
        _items.removeAll { $0.id == item.id }
        lock.unlock()
        notifyChanged()
    }

    private func finish(_ item: DownloadQueueItem, status: DownloadItemStatus, message: String?) {
        lock.lock()
        guard item.status.isActive else { lock.unlock(); return }
        item.status = status
        item.message = message
        lock.unlock()

        AppSettings.shared.appendHistory(DownloadHistoryRecord(
            appId: item.appId,
            title: item.title,
            source: item.subtitle,
            status: status.rawValue,
            completedAt: Date(),
            message: message
        ))

        item.onFinished?(item, status == .completed)
        notifyChanged()

        if status == .completed {
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self?.removeInactive(item)
            }
        }
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.queueDidChangeNotification, object: nil)
        }
    }
}
