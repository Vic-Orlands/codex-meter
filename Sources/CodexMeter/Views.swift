import AppKit
import SwiftUI

private enum MeterPalette {
    static let accent = Color.accentColor
    static let radius: CGFloat = 18
    static let rowRadius: CGFloat = 5
    static let chipRadius: CGFloat = 5
    static let fontSize: CGFloat = 13
    static let iconSize: CGFloat = 13
    static let iconTextGap: CGFloat = 8
    /// Height for provider tabs and primary buttons. 6 + ~16pt text + 6 = 28.
    static let buttonHeight: CGFloat = 28
    static let buttonVerticalPadding: CGFloat = 6
    /// Height for menu rows. 7 + ~16pt text + 7 = 30.
    static let controlHeight: CGFloat = 30
    static let controlVerticalPadding: CGFloat = 7
    /// Gap between account chips and the Current Account block.
    static let accountSectionGap: CGFloat = 8
    static let panelInset: CGFloat = 8
    /// Shared leading/trailing inset for section content. Matches Cursor Auto/Models,
    /// Token activity, and Add account / Status icon rows (panelInset + contentInset).
    static let contentInset: CGFloat = 10
    static let panelFill = Color(red: 0.105, green: 0.105, blue: 0.11)
    static let glassTint = NSColor(calibratedWhite: 0.08, alpha: 0.22)
    static let iconGray = Color.primary.opacity(0.55)
    /// Hairline for the stats grid — same gray as icons, much fainter.
    static let gridStroke = Color.primary.opacity(0.16)
    static let gridStrokeWidth: CGFloat = 0.5
    /// Hover fill for interactive rows. Not used as a section-card background.
    static let chipFill = Color.primary.opacity(0.055)
    /// Account chips: selected is quiet but still stronger than idle.
    static let chipSelectedFill = Color.primary.opacity(0.07)
    static let chipIdleFill = Color.primary.opacity(0.02)
    static let chipHoverFill = Color.primary.opacity(0.04)
}

private struct MeterSymbolImage: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: MeterPalette.iconSize, weight: .medium))
            .imageScale(.medium)
            .foregroundStyle(MeterPalette.iconGray)
            .symbolRenderingMode(.monochrome)
            .frame(width: MeterPalette.iconSize, height: MeterPalette.iconSize)
            .accessibilityHidden(true)
    }
}

private enum ProviderSelection: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case cursor = "Cursor"
    var id: Self { self }
}

struct MenuContentView: View {
    @EnvironmentObject private var store: AccountStore
    @State private var selectedID: UUID?
    @State private var provider: ProviderSelection = .codex
    @State private var providerTransitionForward = true
    @Namespace private var providerTabAnimation

    private var selectedProfile: AccountProfile? {
        let id = selectedID ?? store.activeID
        return store.profiles.first(where: { $0.id == id }) ?? store.profiles.first
    }

    private var selectedSnapshot: AccountSnapshot? {
        selectedProfile.flatMap { store.snapshots[$0.id] }
    }

    var body: some View {
        panel
            .modifier(MeterPopoverChrome())
            .onAppear(perform: handleAppear)
            .onChange(of: store.activeID) { _, id in
                if selectedID == nil { selectedID = id }
            }
            .onChange(of: provider) { _, newValue in
                store.refreshExpandedData(showingCursor: newValue == .cursor)
            }
            .alert("Codex Meter", isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.alertMessage ?? "")
            }
    }

    private func handleAppear() {
        selectedID = selectedID ?? store.activeID ?? store.profiles.first?.id
        store.refreshExpandedData(showingCursor: provider == .cursor)
        WindowTransparencyView.pinOpenWindows()
        DispatchQueue.main.async {
            WindowTransparencyView.pinOpenWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            WindowTransparencyView.pinOpenWindows()
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            MeterInsetDivider()
            providerPicker
            MeterInsetDivider()
            providerBody
                .id(provider)
                .transition(.asymmetric(
                    insertion: .move(edge: providerTransitionForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: providerTransitionForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
    }

    @ViewBuilder
    private var providerBody: some View {
        switch provider {
        case .codex:
            if store.profiles.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if let profile = selectedProfile {
                            accountPanel(profile: profile)
                            quickStats
                            TokenActivityCard(dailyUsage: selectedSnapshot?.dailyUsage ?? [])
                            actions
                        }
                    }
                    .padding(.horizontal, MeterPalette.panelInset)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                }
                .scrollContentBackground(.hidden)
            }
        case .cursor:
            ScrollView(showsIndicators: false) {
                CursorProviderView(
                    snapshot: store.cursorSnapshot,
                    error: store.cursorError,
                    isRefreshing: store.isRefreshing
                )
                .padding(.horizontal, MeterPalette.panelInset)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var header: some View {
        HStack(spacing: MeterPalette.iconTextGap) {
            SwitchLogo(size: MeterPalette.iconSize, color: MeterPalette.iconGray)
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Meter")
                    .font(.system(size: 13, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    if let fetchedAt = provider == .codex ? selectedSnapshot?.fetchedAt : store.cursorSnapshot?.fetchedAt {
                        Text("Updated \(fetchedAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.isRefreshing ? "Reading usage…" : "Local account monitor")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                MeterToolbarButton(symbol: store.isRefreshing ? nil : "arrow.clockwise", help: "Refresh usage", disabled: store.isRefreshing) {
                    store.refreshAll(includeCursorActivity: provider == .cursor)
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                SettingsLink {
                    Image(systemName: "gearshape.fill")
                }
                .meterToolbarChrome()
                .help("Settings")
                MeterToolbarButton(symbol: "power", help: "Quit Codex Meter") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var providerPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProviderSelection.allCases) { item in
                ProviderTab(
                    item: item,
                    isSelected: provider == item,
                    namespace: providerTabAnimation
                ) {
                    guard provider != item else { return }
                    providerTransitionForward = item == .cursor
                    withAnimation(.easeInOut(duration: 0.2)) { provider = item }
                }
            }
        }
        .padding(2)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: MeterPalette.rowRadius + 2, style: .continuous)
        )
        .padding(.horizontal, MeterPalette.panelInset)
        .padding(.horizontal, MeterPalette.contentInset)
        .padding(.vertical, 5)
    }

    private var accountStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.profiles) { profile in
                    let isSelected = selectedProfile?.id == profile.id
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { selectedID = profile.id }
                    } label: {
                        Text(shortName(profile))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .contentShape(RoundedRectangle(cornerRadius: MeterPalette.chipRadius, style: .continuous))
                    }
                    .buttonStyle(MeterPressStyle())
                    .meterSelectable(isSelected: isSelected, shape: RoundedRectangle(cornerRadius: MeterPalette.chipRadius, style: .continuous))
                }

                Button { store.addAccount() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: MeterPalette.iconSize, weight: .semibold))
                        .imageScale(.medium)
                        .foregroundStyle(MeterPalette.iconGray)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(MeterPressStyle())
                .meterSelectable(isSelected: false, shape: Circle())
                .disabled(store.isAddingAccount)
                .help("Add account")
            }
        }
        .frame(height: 28)
    }

    private func accountPanel(profile: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: MeterPalette.accountSectionGap) {
            accountStrip
            accountHero(profile: profile)
                .id(profile.id)
                .transition(.opacity)
        }
        .padding(.horizontal, MeterPalette.contentInset)
    }

    private func accountHero(profile: AccountProfile) -> some View {
        let snapshot = selectedSnapshot
        let limits = snapshot?.rateLimits

        return VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: MeterPalette.iconTextGap) {
                    ProviderProductIcon(product: .codex, size: MeterPalette.iconSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(snapshot?.email ?? "Waiting for account details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                if let plan = snapshot?.planType {
                    Text(plan.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MeterPalette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MeterPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: MeterPalette.chipRadius, style: .continuous))
                }
            }

            if let error = store.accountErrors[profile.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            QuotaRail(title: "5-hour", window: limits?.primary)
            QuotaRail(title: "Weekly", window: limits?.secondary, dimmed: true)

            if store.activeID != profile.id {
                MeterPrimaryButton(title: "Use this account") {
                    store.switchAccount(to: profile)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickStats: some View {
        StatGrid(items: [
            .init(title: "Credits", value: creditLabel, symbol: "creditcard.fill"),
            .init(title: "Lifetime", value: tokenLabel(selectedSnapshot?.usage?.lifetimeTokens), symbol: "chart.bar.doc.horizontal.fill"),
            .init(title: "Streak", value: streakLabel, symbol: "flame.fill"),
        ])
    }

    private var actions: some View {
        VStack(spacing: 2) {
            MeterMenuRow(title: "Add account", symbol: "person.badge.plus.fill", disabled: store.isAddingAccount) {
                store.addAccount()
            }
            MeterMenuRow(title: "Open status", symbol: "info.circle.fill") {
                NSWorkspace.shared.open(URL(string: "https://status.openai.com")!)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            SwitchLogo(size: 44, color: MeterPalette.accent)
            Text("Connect your first account")
                .font(.system(size: 15, weight: .semibold))
            Text("Sign-in opens in your browser and stays with the official Codex CLI.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Add account") { store.addAccount() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 48)
    }

    private var creditLabel: String {
        guard let credits = selectedSnapshot?.rateLimits?.credits else { return "—" }
        if credits.unlimited { return "Unlimited" }
        return credits.balance ?? (credits.hasCredits ? "Available" : "None")
    }

    private var streakLabel: String {
        guard let days = selectedSnapshot?.usage?.currentStreakDays else { return "—" }
        return "\(days)d"
    }

    private func tokenLabel(_ count: Int?) -> String {
        count?.formatted(.number.notation(.compactName)) ?? "—"
    }

    private func shortName(_ profile: AccountProfile) -> String {
        let source = store.snapshots[profile.id]?.email ?? profile.name
        return source.split(separator: "@").first.map(String.init) ?? source
    }
}

private struct QuotaRail: View {
    let title: String
    let window: RateLimitWindow?
    var dimmed = false

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(window?.usedPercent ?? 0)% used")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(MeterPalette.accent.opacity(dimmed ? 0.55 : 1))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, window?.usedPercent ?? 0))) / 100)
                }
            }
            .frame(height: 5)
            HStack {
                Spacer()
                if let reset = window?.resetDate {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("Resets \(reset, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Reset unavailable")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct CursorProviderView: View {
    let snapshot: CursorSnapshot?
    let error: String?
    let isRefreshing: Bool

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: MeterPalette.iconTextGap) {
                    ProviderProductIcon(product: .cursor, size: MeterPalette.iconSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor")
                            .font(.system(size: 13, weight: .semibold))
                        Text(snapshot?.email ?? cursorStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let membership = snapshot?.membershipType {
                        Text(planName(membership).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MeterPalette.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(MeterPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: MeterPalette.chipRadius, style: .continuous))
                    }
                }

                CursorRail(title: "Auto", percent: snapshot?.autoPercentUsed)
                CursorRail(title: "Models", percent: snapshot?.apiPercentUsed, dimmed: true)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Included usage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(includedUsage)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    Spacer()
                    if let reset = snapshot?.billingCycleEnd {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Cycle resets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(reset, format: .dateTime.month(.abbreviated).day())
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .padding(.horizontal, MeterPalette.contentInset)
            .padding(.top, 6)
            .padding(.bottom, 10)

            StatGrid(items: [
                .init(title: "Tokens", value: compact(snapshot?.totalTokens), symbol: "chart.bar.doc.horizontal.fill"),
                .init(title: "On demand", value: money(snapshot?.onDemandUsedCents), symbol: "bolt.fill"),
                .init(title: "Plan left", value: "\(Int((100 - (snapshot?.planPercentUsed ?? 0)).rounded()))%", symbol: "gauge.with.needle.fill"),
            ])

            TokenActivityCard(dailyUsage: snapshot?.dailyUsage ?? [])

            VStack(spacing: 2) {
                MeterMenuRow(title: "Dashboard", symbol: "chart.bar.fill") {
                    NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard?tab=usage")!)
                }
                MeterMenuRow(title: "Cursor status", symbol: "info.circle.fill") {
                    NSWorkspace.shared.open(URL(string: "https://status.cursor.com")!)
                }
            }
        }
        .padding(.top, 4)
    }

    private var cursorStatus: String {
        if let error { return error }
        return isRefreshing ? "Reading Cursor usage…" : "Open Cursor and sign in"
    }

    private var includedUsage: String {
        guard let snapshot else { return "—" }
        return "\(money(snapshot.planUsedCents)) of \(money(snapshot.planLimitCents))"
    }

    private func money(_ cents: Int?) -> String {
        guard let cents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    private func compact(_ value: Int?) -> String {
        value.map { $0.formatted(.number.notation(.compactName)) } ?? "—"
    }

    private func planName(_ value: String) -> String {
        switch value.lowercased() {
        case "free_trial": return "Pro trial"
        case "pro_plus": return "Pro+"
        case "pro_student": return "Pro"
        default: return value.replacingOccurrences(of: "_", with: " ")
        }
    }
}

private struct CursorRail: View {
    let title: String
    let percent: Double?
    var dimmed = false

    var body: some View {
        let used = max(0, min(100, percent ?? 0))
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percent == nil ? "—" : "\(Int(used.rounded()))% used")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(MeterPalette.accent.opacity(dimmed ? 0.55 : 1))
                        .frame(width: proxy.size.width * used / 100)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct StatGridItem: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let symbol: String
}

private struct StatGrid: View {
    let items: [StatGridItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(MeterPalette.gridStroke)
                        .frame(width: MeterPalette.gridStrokeWidth)
                }
                StatPill(title: item.title, value: item.value, symbol: item.symbol)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MeterPalette.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MeterPalette.chipRadius, style: .continuous)
                .strokeBorder(MeterPalette.gridStroke, lineWidth: MeterPalette.gridStrokeWidth)
        }
        .padding(.horizontal, MeterPalette.contentInset)
    }
}

private struct StatPill: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: MeterPalette.iconTextGap) {
            MeterSymbolImage(name: symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
    }
}

private enum ActivityMode: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case cumulative = "Total"
    var id: Self { self }
}

private struct TokenActivityCard: View {
    let dailyUsage: [DailyUsageBucket]
    @State private var mode: ActivityMode = .daily

    private let calendar = Calendar.autoupdatingCurrent
    private let weeks = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Token activity")
                        .font(.system(size: 13, weight: .semibold))
                    Text(activitySubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Activity mode", selection: $mode) {
                    ForEach(ActivityMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 168)
            }

            let values = activityValues
            let maximum = max(values.max() ?? 0, 1)
            GeometryReader { proxy in
                let spacing: CGFloat = 3
                let columns = CGFloat(weeks)
                let cellWidth = max(2, (proxy.size.width - spacing * (columns - 1)) / columns)
                let rows = Array(repeating: GridItem(.fixed(8), spacing: spacing), count: 7)
                LazyHGrid(rows: rows, spacing: spacing) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(activityColor(value: value, maximum: maximum))
                            .frame(width: cellWidth, height: 8)
                            .help(value == 0 ? "No recorded activity" : "\(value.formatted()) tokens")
                    }
                }
            }
            .frame(height: 74)
            .animation(.easeOut(duration: 0.2), value: mode)

            HStack {
                ForEach(monthLabels.indices, id: \.self) { index in
                    Text(monthLabels[index]).frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == monthLabels.count - 1 ? .trailing : .center))
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, MeterPalette.contentInset)
        .padding(.vertical, 10)
    }

    private var dates: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0 - (weeks * 7 - 1), to: today) }
    }

    private var dailyValues: [Int] {
        let buckets = dailyUsage.reduce(into: [String: Int]()) { result, bucket in
            result[String(bucket.startDate.prefix(10)), default: 0] += bucket.tokens
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return dates.map { buckets[formatter.string(from: $0)] ?? 0 }
    }

    private var activityValues: [Int] {
        switch mode {
        case .daily:
            return dailyValues
        case .weekly:
            return dailyValues.indices.map { index in
                dailyValues[max(0, index - 6)...index].reduce(0, +)
            }
        case .cumulative:
            var total = 0
            return dailyValues.map { total += $0; return total }
        }
    }

    private var activitySubtitle: String {
        let recordedDays = dailyValues.filter { $0 > 0 }.count
        return recordedDays == 0 ? "Waiting for daily usage history" : "\(recordedDays) active day\(recordedDays == 1 ? "" : "s") in this view"
    }

    private var monthLabels: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let indexes = [0, 35, 70, dates.count - 1]
        return indexes.map { formatter.string(from: dates[$0]) }
    }

    private func activityColor(value: Int, maximum: Int) -> Color {
        guard value > 0 else { return Color.primary.opacity(0.16) }
        let intensity = Double(value) / Double(maximum)
        if intensity > 0.74 { return MeterPalette.accent }
        if intensity > 0.42 { return MeterPalette.accent.opacity(0.72) }
        if intensity > 0.16 { return MeterPalette.accent.opacity(0.42) }
        return MeterPalette.accent.opacity(0.2)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AccountStore
    @AppStorage("showDockIcon") private var showDockIcon = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show Dock icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, value in
                        NSApp.applicationIconImage = AppIconRenderer.make()
                        NSApp.setActivationPolicy(value ? .regular : .accessory)
                    }
            }
            Section("Codex CLI") {
                TextField("Path to codex", text: $store.customCodexPath, prompt: Text("Auto-detect"))
                Text("Auto-detects /opt/homebrew/bin/codex and /usr/local/bin/codex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("OAuth and usage requests are handled by the official Codex CLI. Codex Meter never parses auth.json; switching uses an atomic local file copy with 0600 permissions.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 330)
        .padding()
    }
}

private final class WindowTransparencyView: NSView {
    private var moveObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
        observeWindow()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configure()
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }

    private func observeWindow() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        guard let window else { return }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { _ in
            WindowTransparencyView.pin(window)
        }
    }

    private func configure() {
        guard let window else { return }
        WindowTransparencyView.style(window)
    }

    static func style(_ window: NSWindow) {
        hidePopoverAnchor(of: window)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        clip(window.contentView)
        clip(window.contentView?.superview)
        clearOpaqueChrome(window.contentView)
        clearOpaqueChrome(window.contentView?.superview)
        styleSystemGlass(window.contentView)
        styleSystemGlass(window.contentView?.superview)
        window.invalidateShadow()
        pin(window)
        DispatchQueue.main.async {
            pin(window)
        }
    }

    private static func clip(_ view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.mask = nil
        view.layer?.masksToBounds = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }

    private static func hidePopoverAnchor(of window: NSWindow) {
        var responder: NSResponder? = window
        while let node = responder {
            if node.responds(to: NSSelectorFromString("setShouldHideAnchor:")) {
                node.setValue(true, forKey: "shouldHideAnchor")
            }
            responder = node.nextResponder
        }
    }

    private static func clearOpaqueChrome(_ root: NSView?) {
        guard let root else { return }
        var stack = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            view.wantsLayer = true
            view.layer?.isOpaque = false
            if view is NSVisualEffectView { continue }
            view.layer?.backgroundColor = NSColor.clear.cgColor
            if let clip = view as? NSClipView {
                clip.drawsBackground = false
                clip.backgroundColor = .clear
            }
            if let scroll = view as? NSScrollView {
                scroll.drawsBackground = false
                scroll.backgroundColor = .clear
            }
        }
    }

    private static func styleSystemGlass(_ root: NSView?) {
        guard let root else { return }
        var stack = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
                glass.layer?.mask = nil
                glass.cornerRadius = MeterPalette.radius
                glass.style = .clear
                glass.tintColor = MeterPalette.glassTint
            }
        }
    }

    static func pinOpenWindows() {
        for window in NSApp.windows where window.frame.width >= 360 && window.frame.height >= 500 {
            style(window)
        }
    }

    private static var pinningWindows = Set<ObjectIdentifier>()

    static func pin(_ window: NSWindow) {
        let identity = ObjectIdentifier(window)
        guard !pinningWindows.contains(identity) else { return }
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        guard let primary else { return }
        let visible = primary.visibleFrame
        var origin = window.frame.origin
        let size = window.frame.size
        origin.y = visible.maxY - size.height
        if origin.x + size.width < visible.minX || origin.x > visible.maxX {
            origin.x = visible.midX - size.width / 2
        }
        if abs(origin.x - window.frame.origin.x) > 0.5 || abs(origin.y - window.frame.origin.y) > 0.5 {
            pinningWindows.insert(identity)
            window.setFrameOrigin(origin)
            pinningWindows.remove(identity)
        }
    }
}

private struct WindowTransparency: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowTransparencyView {
        WindowTransparencyView()
    }

    func updateNSView(_ nsView: WindowTransparencyView, context: Context) {
        if let window = nsView.window {
            WindowTransparencyView.style(window)
        }
    }
}

private struct MeterPopoverChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: MeterPalette.fontSize))
            .frame(width: 400, height: 640)
            .overlay {
                RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
            .preferredColorScheme(.dark)
            .modifier(MeterWindowGlass())
            .background(WindowTransparency())
    }
}

private struct MeterWindowGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(for: .window) {
                MeterGlassFill()
            }
        } else {
            content.background { MeterGlassFill() }
        }
    }
}

private struct MeterGlassFill: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .clear.tint(Color.black.opacity(0.22)),
                    in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous)
                )
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

private struct MeterInsetDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }
}

private struct ProviderTab: View {
    let item: ProviderSelection
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MeterPalette.iconTextGap) {
                ProviderProductIcon(product: item == .codex ? .codex : .cursor, size: MeterPalette.iconSize)
                Text(item.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, MeterPalette.buttonVerticalPadding)
            .frame(height: MeterPalette.buttonHeight)
            .contentShape(RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .matchedGeometryEffect(id: "provider-tab", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }
            }
        }
        .buttonStyle(MeterPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

private struct MeterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MeterSelectable<S: Shape>: ViewModifier {
    var isSelected: Bool
    var shape: S
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(isSelected ? MeterPalette.chipSelectedFill : (hovering ? MeterPalette.chipHoverFill : MeterPalette.chipIdleFill))
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}

private struct MeterPrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: MeterPalette.fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, MeterPalette.buttonVerticalPadding)
                .frame(height: MeterPalette.buttonHeight)
                .contentShape(RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous)
                        .fill(MeterPalette.accent)
                    RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.16 : 0))
                }
        }
        .buttonStyle(MeterPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

private struct MeterMenuRow: View {
    let title: String
    var symbol: String?
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MeterPalette.iconTextGap) {
                if let symbol {
                    MeterSymbolImage(name: symbol)
                }
                Text(title)
                    .font(.system(size: MeterPalette.fontSize))
                    .foregroundStyle(hovering && !disabled ? Color.primary : Color.primary.opacity(0.82))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, MeterPalette.contentInset)
            .padding(.vertical, MeterPalette.controlVerticalPadding)
            .frame(height: MeterPalette.controlHeight)
            .contentShape(RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous))
        }
        .buttonStyle(MeterPressStyle())
        .disabled(disabled)
        .background {
            RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous)
                .fill(hovering && !disabled ? MeterPalette.chipFill : Color.clear)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .opacity(disabled ? 0.45 : 1)
    }
}

private struct MeterToolbarButton<Label: View>: View {
    var symbol: String?
    let help: String
    var disabled = false
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    init(symbol: String?, help: String, disabled: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.symbol = symbol
        self.help = help
        self.disabled = disabled
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action, label: label)
            .disabled(disabled)
            .help(help)
            .meterToolbarChrome()
    }
}

private extension MeterToolbarButton where Label == Image {
    init(symbol: String, help: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.init(symbol: symbol, help: help, disabled: disabled, action: action) {
            Image(systemName: symbol)
        }
    }
}

private struct MeterToolbarChrome: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(MeterPressStyle())
            .font(.system(size: MeterPalette.iconSize, weight: .medium))
            .imageScale(.medium)
            .foregroundStyle(MeterPalette.iconGray)
            .symbolRenderingMode(.monochrome)
            .frame(width: 28, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous)
                    .fill(.primary.opacity(hovering ? 0.08 : 0))
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

private extension View {
    func meterToolbarChrome() -> some View {
        modifier(MeterToolbarChrome())
    }

    func meterSelectable(isSelected: Bool) -> some View {
        modifier(MeterSelectable(isSelected: isSelected, shape: RoundedRectangle(cornerRadius: MeterPalette.rowRadius, style: .continuous)))
    }

    func meterSelectable<S: Shape>(isSelected: Bool, shape: S) -> some View {
        modifier(MeterSelectable(isSelected: isSelected, shape: shape))
    }
}
