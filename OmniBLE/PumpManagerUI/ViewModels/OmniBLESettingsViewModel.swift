//
//  DashSettingsViewModel.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 3/8/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit


enum DashSettingsViewAlert {
    case suspendError(Error)
    case resumeError(Error)
    case syncTimeError(OmniBLEPumpManagerError)
    case changeConfirmationBeepsError(OmniBLEPumpManagerError)
}

public enum ReservoirLevelHighlightState: String, Equatable {
    case normal
    case warning
    case critical
}

struct DashSettingsNotice {
    let title: String
    let description: String
}

class OmniBLESettingsViewModel: ObservableObject {
    
    @Published var lifeState: PodLifeState
    
    @Published var activatedAt: Date?

    @Published var expiresAt: Date?

    @Published var changingConfirmationBeeps: Bool = false

    var confirmationBeeps: Bool {
        get {
            pumpManager.confirmationBeeps
        }
    }
    
    var activatedAtString: String {
        if let activatedAt = activatedAt {
            return dateFormatter.string(from: activatedAt)
        } else {
            return "—"
        }
    }
    
    var expiresAtString: String {
        if let expiresAt = expiresAt {
            return dateFormatter.string(from: expiresAt)
        } else {
            return "—"
        }
    }

    // Expiration reminder date for current pod
    @Published var expirationReminderDate: Date?
    
    var allowedScheduledReminderDates: [Date]? {
        return pumpManager.allowedExpirationReminderDates
    }

    // Hours before expiration
    @Published var expirationReminderDefault: Int {
        didSet {
            self.pumpManager.defaultExpirationReminderOffset = .hours(Double(expirationReminderDefault))
        }
    }
    
    // Units to alert at
    @Published var lowReservoirAlertValue: Int
    
    @Published var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?

    @Published var basalDeliveryRate: Double?

    @Published var activeAlert: DashSettingsViewAlert? = nil {
        didSet {
            if activeAlert != nil {
                alertIsPresented = true
            }
        }
    }

    @Published var alertIsPresented: Bool = false {
        didSet {
            if !alertIsPresented {
                activeAlert = nil
            }
        }
    }
    
    @Published var reservoirLevel: ReservoirLevel?
    
    @Published var reservoirLevelHighlightState: ReservoirLevelHighlightState?
    
    @Published var synchronizingTime: Bool = false

    @Published var podCommState: PodCommState

    
    var timeZone: TimeZone {
        return pumpManager.status.timeZone
    }
    
    var podDetails: PodDetails? {
        return pumpManager.podDetails
    }
        
    var viewTitle: String {
        return pumpManager.localizedTitle
    }
    
    var isClockOffset: Bool {
        return pumpManager.isClockOffset
    }

    var isPodDataStale: Bool {
        return Date().timeIntervalSince(pumpManager.lastSync ?? .distantPast) > .minutes(12)
    }

    var recoveryText: String? {
        if case .fault = podCommState {
            return LocalizedString("Insulin delivery stopped. Change Pod now.", comment: "The action string on pod status page when pod faulted")
        } else if isPodDataStale {
            return LocalizedString("Make sure your phone and pod are close to each other. If communication issues persist, move to a new area.", comment: "The action string on pod status page when pod data is stale")
        } else if let podTimeRemaining = pumpManager.podTimeRemaining, podTimeRemaining < 0 {
            return LocalizedString("Change Pod now. Insulin delivery will stop 8 hours after the Pod has expired or when no more insulin remains.", comment: "The action string on pod status page when pod expired")
        } else {
            return nil
        }
    }
    
    var notice: DashSettingsNotice? {
        if pumpManager.isClockOffset {
            return DashSettingsNotice(
                title: LocalizedString("Time Change Detected", comment: "title for time change detected notice"),
                description: LocalizedString("The time on your pump is different from the current time. Your pump’s time controls your scheduled basal rates. You can review the time difference and configure your pump.", comment: "description for time change detected notice"))
        } else {
            return nil
        }
    }

    var isScheduledBasal: Bool {
        switch basalDeliveryState {
        case .active(_), .initiatingTempBasal:
            return true
        case .tempBasal(_), .cancelingTempBasal, .suspending, .suspended(_), .resuming, .none:
            return false
        }
    }
    
    let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        dateFormatter.doesRelativeDateFormatting = true
        return dateFormatter
    }()
    
    let timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .none
        return dateFormatter
    }()

    let basalRateFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.minimumIntegerDigits = 1
        return numberFormatter
    }()
    
    let reservoirVolumeFormatter = QuantityFormatter(for: .internationalUnit())
    
    var didFinish: (() -> Void)?
    
    var navigateTo: ((DashUIScreen) -> Void)?
    
    private let pumpManager: OmniBLEPumpManager
    
    init(pumpManager: OmniBLEPumpManager) {
        self.pumpManager = pumpManager
        
        lifeState = pumpManager.lifeState
        activatedAt = pumpManager.podActivatedAt
        expiresAt = pumpManager.expiresAt
        basalDeliveryState = pumpManager.status.basalDeliveryState
        basalDeliveryRate = self.pumpManager.basalDeliveryRate
        reservoirLevel = self.pumpManager.reservoirLevel
        reservoirLevelHighlightState = self.pumpManager.reservoirLevelHighlightState
        expirationReminderDate = self.pumpManager.scheduledExpirationReminder
        expirationReminderDefault = Int(self.pumpManager.defaultExpirationReminderOffset.hours)
        lowReservoirAlertValue = Int(self.pumpManager.state.lowReservoirReminderValue)
        podCommState = self.pumpManager.podCommState
        pumpManager.addPodStateObserver(self, queue: DispatchQueue.main)
        
        // Trigger refresh
        pumpManager.getPodStatus(emitConfirmationBeep: false) { _ in }
    }
    
    func changeTimeZoneTapped() {
        synchronizingTime = true
        pumpManager.setTime { (error) in
            DispatchQueue.main.async {
                self.synchronizingTime = false
                self.lifeState = self.pumpManager.lifeState
                if let error = error {
                    self.activeAlert = .syncTimeError(error)
                }
            }
        }
    }
    
    func doneTapped() {
        self.didFinish?()
    }
    
    func stopUsingOmnipodTapped() {
        self.pumpManager.notifyDelegateOfDeactivation {
            DispatchQueue.main.async {
                self.didFinish?()
            }
        }
    }
    
    func suspendDelivery(duration: TimeInterval) {
        pumpManager.suspendDelivery(withSuspendReminders: duration) { (error) in
            DispatchQueue.main.async {
                if let error = error {
                    self.activeAlert = .suspendError(error)
                }
            }
        }
    }
    
    func resumeDelivery() {
        pumpManager.resumeDelivery { (error) in
            DispatchQueue.main.async {
                if let error = error {
                    self.activeAlert = .resumeError(error)
                }
            }
        }
    }
    
    func saveScheduledExpirationReminder(_ selectedDate: Date, _ completion: @escaping (Error?) -> Void) {
        if let podExpiresAt = pumpManager.podExpiresAt {
            let intervalBeforeExpiration = podExpiresAt.timeIntervalSince(selectedDate)
            pumpManager.updateExpirationReminder(.hours(round(intervalBeforeExpiration.hours))) { (error) in
                DispatchQueue.main.async {
                    if error == nil {
                        self.expirationReminderDate = selectedDate
                    }
                    completion(error)
                }
            }
        }
    }

    func saveLowReservoirReminder(_ selectedValue: Int, _ completion: @escaping (Error?) -> Void) {
        pumpManager.updateLowReservoirReminder(selectedValue) { (error) in
            DispatchQueue.main.async {
                if error == nil {
                    self.lowReservoirAlertValue = selectedValue
                }
                completion(error)
            }
        }
    }
 
    func setConfirmationBeeps(enabled: Bool) {
        self.changingConfirmationBeeps = true
        pumpManager.setConfirmationBeeps(enabled: enabled) { error in
            DispatchQueue.main.async {
                self.changingConfirmationBeeps = false
                if let error = error {
                    self.activeAlert = .changeConfirmationBeepsError(error)
                }
            }
        }
    }
    
    var podOk: Bool {
        guard basalDeliveryState != nil else { return false }

        switch podCommState {
        case .noPod, .activating, .deactivating, .fault:
            return false
        default:
            return true
        }
    }

    var podError: String? {
        switch podCommState {
        case .fault(let status):
            switch status.faultEventCode.faultType {
            case .reservoirEmpty:
                return LocalizedString("No Insulin", comment: "Error message for reservoir view when reservoir empty")
            case .exceededMaximumPodLife80Hrs:
                return LocalizedString("Pod Expired", comment: "Error message for reservoir view when pod expired")
            case .occluded, .occlusionCheckStartup1, .occlusionCheckStartup2, .occlusionCheckTimeouts1, .occlusionCheckTimeouts2, .occlusionCheckTimeouts3, .occlusionCheckPulseIssue, .occlusionCheckBolusProblem, .occlusionCheckAboveThreshold, .occlusionCheckValueTooHigh:
                return LocalizedString("Pod Occlusion", comment: "Error message for reservoir view when pod occlusion checks failed")
            default:
                return LocalizedString("Pod Error", comment: "Error message for reservoir view during general pod fault")
            }
        case .active:
            if isPodDataStale {
                return LocalizedString("No Data", comment: "Error message for reservoir view during general pod fault")
            } else {
                return nil
            }
        default:
            return nil
        }

    }
    
    func reservoirText(for level: ReservoirLevel) -> String {
        switch level {
        case .aboveThreshold:
            let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: Pod.maximumReservoirReading)
            let thresholdString = reservoirVolumeFormatter.string(from: quantity, for: .internationalUnit(), includeUnit: false) ?? ""
            let unitString = reservoirVolumeFormatter.string(from: .internationalUnit(), forValue: Pod.maximumReservoirReading, avoidLineBreaking: true)
            return String(format: LocalizedString("%1$@+ %2$@", comment: "Format string for reservoir level above max measurable threshold. (1: measurable reservoir threshold) (2: units)"),
                          thresholdString, unitString)
        case .valid(let value):
            let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: value)
            return reservoirVolumeFormatter.string(from: quantity, for: .internationalUnit()) ?? ""
        }
    }

    var suspendResumeActionText: String {
        let defaultText = LocalizedString("Suspend Insulin Delivery", comment: "Text for suspend resume button when insulin delivery active")

        guard podOk else {
            return defaultText
        }

        switch basalDeliveryState {
        case .suspending:
            return LocalizedString("Suspending insulin delivery...", comment: "Text for suspend resume button when insulin delivery is suspending")
        case .suspended:
            return LocalizedString("Tap to Resume Insulin Delivery", comment: "Text for suspend resume button when insulin delivery is suspended")
        case .resuming:
            return LocalizedString("Resuming insulin delivery...", comment: "Text for suspend resume button when insulin delivery is resuming")
        default:
            return defaultText
        }
    }

    var basalTransitioning: Bool {
        switch basalDeliveryState {
        case .suspending, .resuming:
            return true
        default:
            return false
        }
    }

    func suspendResumeButtonColor(guidanceColors: GuidanceColors) -> Color {
        guard podOk else {
            return Color.secondary
        }
        switch basalDeliveryState {
        case .suspending, .resuming:
            return Color.secondary
        case .suspended:
            return guidanceColors.warning
        default:
            return .accentColor
        }
    }

    func suspendResumeActionColor() -> Color {
        guard podOk else {
            return Color.secondary
        }
        switch basalDeliveryState {
        case .suspending, .resuming:
            return Color.secondary
        default:
            return Color.accentColor
        }
    }

    var isSuspendedOrResuming: Bool {
        switch basalDeliveryState {
        case .suspended, .resuming:
            return true
        default:
            return false
        }
    }

}

extension OmniBLESettingsViewModel: PodStateObserver {
    func podStateDidUpdate(_ state: PodState?) {
        lifeState = self.pumpManager.lifeState
        basalDeliveryState = self.pumpManager.status.basalDeliveryState
        basalDeliveryRate = self.pumpManager.basalDeliveryRate
        reservoirLevel = self.pumpManager.reservoirLevel
        activatedAt = state?.activatedAt
        expiresAt = state?.expiresAt
        reservoirLevelHighlightState = self.pumpManager.reservoirLevelHighlightState
        expirationReminderDate = self.pumpManager.scheduledExpirationReminder
        podCommState = self.pumpManager.podCommState
    }
}

extension OmniBLEPumpManager {
    var lifeState: PodLifeState {
        switch podCommState {
        case .fault(let status):
            switch status.faultEventCode.faultType {
            case .exceededMaximumPodLife80Hrs:
                return .expired
            default:
                let remaining = Pod.nominalPodLife - (status.faultEventTimeSinceActivation ?? Pod.nominalPodLife)
                if remaining > 0 {
                    return .timeRemaining(remaining)
                } else {
                    return .expired
                }
            }

        case .noPod:
            return .noPod
        case .activating:
            return .podActivating
        case .deactivating:
            return .podDeactivating
        case .active:
            if let podTimeRemaining = podTimeRemaining {
                if podTimeRemaining > 0 {
                    return .timeRemaining(podTimeRemaining)
                } else {
                    return .expired
                }
            } else {
                return .podDeactivating
            }
        }
    }
    
    var basalDeliveryRate: Double? {
        if let tempBasal = state.podState?.unfinalizedTempBasal, !tempBasal.isFinished() {
            return tempBasal.rate
        } else {
            switch state.podState?.suspendState {
            case .resumed:
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = state.timeZone
                return state.basalSchedule.currentRate(using: calendar, at: dateGenerator())
            case .suspended, .none:
                return nil
            }
        }
    }
}
