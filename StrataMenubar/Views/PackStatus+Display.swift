import Foundation

extension ModelLibrary.PackStatus {
    /// The row's state: what a run on this pack is doing, otherwise what is on disk.
    func stateText(job: InstallJob?, lastOutcome: InstallOutcome?) -> String {
        if let job, job.pack == pack {
            if job.cancelRequested {
                return "Stopping…"
            }
            return switch job.phase {
            case .checking(let title): "Setting up: \(title)…"
            case .downloading: job.progress.map { "Downloading \(Int($0.fraction * 100))%" } ?? "Downloading…"
            case .preparing: "Preparing…"
            case .writingConfig: "Finishing…"
            }
        }
        let disk = switch state {
        case .installed: "Installed"
        case .downloaded: "Downloaded (prepared at the first start)"
        case .partial(let bytes): "Partially downloaded (\(Self.gigabytes(bytes)) GB)"
        case .notDownloaded: "Not downloaded"
        }
        if case .failed(let failed, _) = lastOutcome, failed == pack {
            return disk + ", setup failed"
        }
        return disk
    }

    var canDownload: Bool {
        switch state {
        case .notDownloaded, .partial: true
        case .installed, .downloaded: false
        }
    }

    /// Why Download or Resume cannot run now; nil when it can. A resume only needs what is still missing.
    func downloadBlocker(setupRunning: Bool, freeBytes: Int64?, memory: MemoryBudget) -> String? {
        if busyElsewhere {
            return "a setup outside this app is working on it"
        }
        if setupRunning {
            return "another setup is running; one runs at a time"
        }
        guard let freeBytes else { return nil }
        let have: Int64 = if case .partial(let bytes) = state { bytes } else { 0 }
        let needed = Int64((pack.requiredFreeGB(memory: memory) * 1e9).rounded()) - have
        if freeBytes < needed {
            return "it needs \(Self.gigabytes(needed)) GB free (the estimate plus 10 GB) and \(Self.gigabytes(freeBytes)) GB is free"
        }
        return nil
    }

    static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1e9)
    }
}

extension InstallOutcome {
    var pack: ModelPack {
        switch self {
        case .installed(let pack), .downloaded(let pack), .cancelled(let pack), .failed(let pack, _): pack
        }
    }
}
