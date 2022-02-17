//
//  PodDetailsView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 4/14/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

public struct PodDetails {
    var lotNumber: UInt32
    var sequenceNumber: UInt32
    var firmwareVersion: String
    var bleFirmwareVersion: String
    var deviceName: String
    var totalDelivery: Double?
    var lastStatus: Date?
    var fault: FaultEventCode?
}

struct PodDetailsView: View {
    
    var podDetails: PodDetails
    
    let ageFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .short

        return formatter
    }()
    
    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
    }
    
    var totalDeliveryText: String {
        if let delivery = podDetails.totalDelivery {
            return String(format: LocalizedString("%g U", comment: "Format string for total delivery on pod details screen"), delivery)
        } else {
            return LocalizedString("NA", comment: "String shown on pod details for total delivery when not available.")
        }
    }
    
    var lastStatusText: String {
        if let lastStatus = podDetails.lastStatus, let ageString = ageFormatter.string(from: Date().timeIntervalSince(lastStatus)) {
            return String(format: LocalizedString("%@ ago", comment: "Format string for last status date on pod details screen"), ageString)
        } else {
            return LocalizedString("NA", comment: "String shown on pod details for last status date when not available.")
        }
    }
    
    var body: some View {
        List {
            row(LocalizedString("Device Name", comment: "description label for device name pod details row"), value: String(describing: podDetails.deviceName))
            row(LocalizedString("Lot Number", comment: "description label for lot number pod details row"), value: String(describing: podDetails.lotNumber))
            row(LocalizedString("Sequence Number", comment: "description label for sequence number pod details row"), value: String(describing: podDetails.sequenceNumber))
            row(LocalizedString("Firmware Version", comment: "description label for firmware version pod details row"), value: podDetails.firmwareVersion)
            row(LocalizedString("Total Delivery", comment: "description label for total delivery pod details row"), value: totalDeliveryText)
            row(LocalizedString("Last Status", comment: "description label for last status date pod details row"), value: lastStatusText)
            if let fault = podDetails.fault {
                row(LocalizedString("Fault", comment: "description label for last status date pod details row"), value: fault.localizedDescription)
                row(LocalizedString("Fault Code", comment: "description label for last status date pod details row"), value: String(format: "0x%02x", fault.rawValue))
            }
        }
        .navigationBarTitle(Text(LocalizedString("Device Details", comment: "title for device details page")), displayMode: .automatic)
    }
}

struct PodDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        PodDetailsView(podDetails: PodDetails(lotNumber: 0x1234, sequenceNumber: 0x1234, firmwareVersion: "1.1.1", bleFirmwareVersion: "2.2.2", deviceName: "PreviewPod", totalDelivery: 10, lastStatus: Date()))
    }
}