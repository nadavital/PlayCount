import MediaPlayer
import SwiftUI
import UIKit

struct SystemIntegrationView: View {
    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.openURL) private var openURL
    @State private var indexStatus = PlayCountSearchIndexStatus(
        state: .notRun,
        lastUpdated: nil,
        songCount: 0,
        albumCount: 0,
        artistCount: 0
    )
    @State private var isRebuildingIndex = false

    var body: some View {
        List {
            Section("Status") {
                statusRow(
                    title: "Media Library",
                    detail: mediaPermissionDetail,
                    systemImage: mediaPermissionIsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    isReady: mediaPermissionIsReady
                )

                statusRow(
                    title: "Siri & Spotlight Index",
                    detail: indexStatusDetail,
                    systemImage: indexStatusIsReady ? "checkmark.circle.fill" : "sparkle.magnifyingglass",
                    isReady: indexStatusIsReady
                )

                statusRow(
                    title: "Recap Reliability",
                    detail: recapReliabilityDetail,
                    systemImage: manager.recapReliabilityStatus.isUsingLastReliableUpdate
                        ? "checkmark.shield.fill"
                        : "checkmark.circle.fill",
                    isReady: true
                )
            }

            Section("Try Saying") {
                phrase("What are my top songs in PlayCount?")
                phrase("How many times have I played this song in PlayCount?")
                phrase("Show my latest PlayCount recap.")
                phrase("Who is my top artist this year in PlayCount?")
            }

            Section {
                Button(action: rebuildIndex) {
                    HStack {
                        Label("Rebuild Siri & Spotlight Index", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRebuildingIndex {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isRebuildingIndex || !mediaPermissionIsReady)

                if !mediaPermissionIsReady {
                    Button("Open PlayCount Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }

                NavigationLink {
                    RecapDiagnosticsView(manager: manager)
                } label: {
                    Label("Recap Diagnostics", systemImage: "stethoscope")
                }
            } footer: {
                Text("Recap diagnostics explain monthly coverage and counter health without exposing music names.")
            }
        }
        .playCountSoftTopScrollEdge()
        .navigationTitle("Siri & Shortcuts")
        .playCountPushedTitleDisplayMode()
        .task {
            repeat {
                indexStatus = await PlayCountSiriIntegration.searchIndexStatus()
                if indexStatus.state != .notRun { break }
                try? await Task.sleep(for: .milliseconds(500))
            } while !Task.isCancelled
        }
    }

    private var mediaPermissionIsReady: Bool {
        manager.authorizationStatus == .authorized
    }

    private var mediaPermissionDetail: String {
        mediaPermissionIsReady ? "Authorized" : "Permission required"
    }

    private var indexStatusIsReady: Bool {
        if case .ready = indexStatus.state { return true }
        return false
    }

    private var indexStatusDetail: String {
        switch indexStatus.state {
        case .notRun:
            return "Waiting for the first library refresh"
        case .ready:
            return "\(indexStatus.songCount) songs, \(indexStatus.albumCount) albums, \(indexStatus.artistCount) artists"
        case .failed(let message):
            return "Needs attention: \(message)"
        }
    }

    private var recapReliabilityDetail: String {
        let status = manager.recapReliabilityStatus
        if status.isUsingLastReliableUpdate {
            return "Protected an unreliable library update"
        }
        if let lastTrustedUpdate = status.lastTrustedUpdate {
            return "Last verified \(lastTrustedUpdate.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Waiting for the first library update"
    }

    private func statusRow(title: String, detail: String, systemImage: String, isReady: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isReady ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func phrase(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "quote.bubble")
                .foregroundStyle(.secondary)
        }
    }

    private func rebuildIndex() {
        guard !isRebuildingIndex else { return }
        isRebuildingIndex = true
        Task {
            indexStatus = await PlayCountSiriIntegration.rebuildSearchIndex(
                songs: manager.topSongs,
                albums: manager.topAlbums,
                artists: manager.topArtists
            )
            isRebuildingIndex = false
        }
    }
}

private struct RecapDiagnosticsView: View {
    @ObservedObject var manager: MediaLibraryManager
    @State private var report: RecapDiagnosticsReport?
    @State private var exportText = ""

    var body: some View {
        List {
            if let report {
                Section("Integrity") {
                    diagnosticStatusRow(
                        title: "Month ledger",
                        detail: report.hasCanonicalMonthLedger
                            ? "One canonical record per tracked month"
                            : "Duplicate or noncanonical months detected",
                        systemImage: report.hasCanonicalMonthLedger ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        isHealthy: report.hasCanonicalMonthLedger
                    )
                    diagnosticStatusRow(
                        title: "Yearly totals",
                        detail: report.yearlyTotalsMatchMonthlyLedgers
                            ? "Matches the sum of unique monthly ledgers"
                            : "Does not match monthly evidence",
                        systemImage: report.yearlyTotalsMatchMonthlyLedgers ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        isHealthy: report.yearlyTotalsMatchMonthlyLedgers
                    )
                    LabeledContent("Reliability policy", value: "Version \(report.reliabilityPolicyVersion)")
                    LabeledContent("Cloud summaries", value: report.cloudSummaryCount.formatted())
                    LabeledContent("Stored snapshots", value: report.totalStoredSnapshots.formatted())
                    if report.unattributedIntervalCount > 0 {
                        LabeledContent(
                            "Unattributed gap plays",
                            value: report.unattributedPlayDelta.formatted()
                        )
                    }
                }

                Section("Updates") {
                    LabeledContent("Last trusted") {
                        Text(report.lastTrustedUpdate?.formatted(date: .abbreviated, time: .shortened) ?? "None")
                    }
                    LabeledContent("Rejected observations", value: report.recentRejectedObservationCount.formatted())
                    if let lastRejectedObservation = report.lastRejectedObservation {
                        LabeledContent("Last protected") {
                            Text(lastRejectedObservation.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                Section("Monthly Coverage") {
                    if report.months.isEmpty {
                        ContentUnavailableView(
                            "No Recap History",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("PlayCount will add coverage after it observes your library.")
                        )
                    } else {
                        ForEach(report.months) { month in
                            RecapDiagnosticMonthRow(month: month)
                        }
                    }
                }

                Section {
                    ShareLink(item: exportText) {
                        Label("Share Diagnostic Report", systemImage: "square.and.arrow.up")
                    }
                    .disabled(exportText.isEmpty)
                } footer: {
                    Text("The report contains dates, aggregate counts, and reliability state. It never includes song, album, artist, or device names.")
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking recap history…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .playCountSoftTopScrollEdge()
        .navigationTitle("Recap Diagnostics")
        .playCountPushedTitleDisplayMode()
        .refreshable {
            refreshReport()
        }
        .task {
            refreshReport()
        }
    }

    private func refreshReport() {
        let updated = manager.recapDiagnosticsReport()
        guard updated != report else { return }
        report = updated
        exportText = manager.privacySafeRecapDiagnostics()
    }

    private func diagnosticStatusRow(
        title: String,
        detail: String,
        systemImage: String,
        isHealthy: Bool
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(isHealthy ? PlayCountBrand.accent : .orange)
        }
    }
}

private struct RecapDiagnosticMonthRow: View {
    let month: RecapDiagnosticMonth

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.monthStart.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Spacer()
                Text("\(month.totalPlayDelta.formatted()) plays")
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 12) {
                Label("\(Int((month.totalListeningDuration / 60).rounded()).formatted()) min", systemImage: "clock")
                Label(month.sourceDescription, systemImage: "camera.metering.matrix")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if month.unattributedPlayDelta > 0 {
                Label(
                    "\(month.unattributedPlayDelta.formatted()) plays occurred outside measured monthly coverage",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
