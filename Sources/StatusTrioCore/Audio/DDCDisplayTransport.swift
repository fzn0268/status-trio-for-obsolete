import DDCPrivateAPI
import Foundation
import IOKit

// IORegistry and I2C details adapted from AppleSiliconDDC revision
// 67ff964ab8123d9d35fadf7d8e1a7c677d31da14, Copyright © 2021 Istvan T. (MIT).
// The x86_64 DDC/CI path follows MonitorControl's IntelDDC (MIT), written by
// @JoniVR, @theOneyouseek and @waydabber and adapted from @reitermarkus.

#if arch(x86_64)
import IOKit.graphics
import IOKit.i2c
#endif

/// An IOKit service retained for use and release on the serial DDC worker only.
/// This type intentionally does not conform to Sendable.
final class DDCDisplayTarget {
    let uid: String
    let service: IOAVService?
    #if arch(x86_64)
    let framebuffer: io_service_t
    #endif

    init(uid: String, service: IOAVService?, framebuffer: io_service_t = IO_OBJECT_NULL) {
        self.uid = uid
        self.service = service
        #if arch(x86_64)
        self.framebuffer = framebuffer
        #endif
    }

    #if arch(x86_64)
    deinit {
        if framebuffer != IO_OBJECT_NULL {
            IOObjectRelease(framebuffer)
        }
    }
    #endif
}

protocol DDCVolumeTransport: AnyObject {
    func resolve(uid: String) -> DDCDisplayTarget?
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply?
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool
}

/// Direct DDC/CI access for external displays: the Apple Silicon proxy on
/// arm64, the framebuffer I2C interface on Intel.
/// Construct and call this transport on its owning serial worker queue.
final class DDCDisplayTransport: DDCVolumeTransport {
    private static let dataAddress: UInt32 = 0x51
    private static let volumeVCP: UInt8 = 0x62
    #if arch(arm64)
    private static let chipAddress: UInt32 = 0x37
    #endif

    static func uniqueMatch<Handle>(
        uid: String,
        services: [(edidUUID: String, handle: Handle)]
    ) -> (edidUUID: String, handle: Handle)? {
        guard !uid.isEmpty else { return nil }
        let matches = services.filter { $0.edidUUID == uid }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Selects identity before calling the opener, so a failed open cannot hide
    /// a second registry entry with the same UID.
    static func uniqueOpenedMatch<Identity, Handle>(
        uid: String,
        services: [(edidUUID: String, handle: Identity)],
        open: (Identity) -> Handle?
    ) -> (edidUUID: String, handle: Handle)? {
        guard let candidate = uniqueMatch(uid: uid, services: services),
              let opened = open(candidate.handle) else { return nil }
        return (edidUUID: candidate.edidUUID, handle: opened)
    }

    /// The current Apple Silicon registry exposes the display EDID UUID on a
    /// framebuffer branch separate from its DDC proxy. Until a stable direct
    /// relation is available, accept only the unambiguous one-framebuffer,
    /// one-external-service topology.
    static func uniqueFramebufferServiceMatch<Identity, Handle>(
        uid: String,
        externalFramebufferUUIDs: [String?],
        externalServices: [Identity],
        open: (Identity) -> Handle?
    ) -> (edidUUID: String, handle: Handle)? {
        guard !uid.isEmpty,
              externalFramebufferUUIDs.count == 1,
              let framebufferUUID = externalFramebufferUUIDs[0],
              framebufferUUID == uid,
              externalServices.count == 1,
              let opened = open(externalServices[0]) else { return nil }
        return (edidUUID: framebufferUUID, handle: opened)
    }

    static func isConnectedExternalFramebuffer(
        ioNameMatched: String?,
        displayWidth: Int?,
        displayHeight: Int?
    ) -> Bool {
        guard let ioNameMatched,
              ioNameMatched.hasPrefix("dispext"),
              let displayWidth,
              let displayHeight else { return false }
        return displayWidth > 0 && displayHeight > 0
    }

    /// The `{VVVV-PPPP-SSSSSSSS}` block of a graphics HDMI/DisplayPort audio
    /// device UID is the uppercase hex of the EDID manufacturer (bytes 8..<10),
    /// product code (10..<12) and serial (12..<16) read as little-endian
    /// integers, so the framebuffer is matched by identity rather than by a
    /// display name the user can rename.
    static func edidIdentityBlock(_ edid: [UInt8]) -> String? {
        guard edid.count >= 16 else { return nil }
        func littleEndian(_ bytes: Range<Int>) -> UInt32 {
            bytes.reversed().reduce(UInt32(0)) { value, index in (value << 8) | UInt32(edid[index]) }
        }
        return String(format: "{%04X-%04X-%08X}",
                      littleEndian(8..<10), littleEndian(10..<12), littleEndian(12..<16))
    }

    static func audioUID(_ uid: String, matchesEDID edid: [UInt8]) -> Bool {
        guard let block = edidIdentityBlock(edid), !uid.isEmpty else { return false }
        return uid.localizedCaseInsensitiveContains(block)
    }

    #if arch(x86_64)
    private static func connectedFramebuffer(forAudioUID uid: String) -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching(IOFRAMEBUFFER_CONFORMSTO), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var matches: [io_service_t] = []
        while true {
            let framebuffer = IOIteratorNext(iterator)
            guard framebuffer != 0 else { break }
            if let edid = displayEDID(framebuffer), audioUID(uid, matchesEDID: edid), hasI2CBus(framebuffer) {
                matches.append(framebuffer)
            } else {
                IOObjectRelease(framebuffer)
            }
        }
        defer { matches.dropFirst().forEach { IOObjectRelease($0) } }
        return matches.first
    }

    private static func displayEDID(_ framebuffer: io_service_t) -> [UInt8]? {
        guard let dictionary = IODisplayCreateInfoDictionary(framebuffer, IOOptionBits())?
            .takeRetainedValue() as? [String: Any] else { return nil }
        return (dictionary["IODisplayEDID"] as? Data).map(Array.init)
    }

    private static func hasI2CBus(_ framebuffer: io_service_t) -> Bool {
        var busCount = IOItemCount(0)
        return IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS && busCount > 0
    }
    #endif

    func resolve(uid: String) -> DDCDisplayTarget? {
        #if arch(arm64)
        guard !uid.isEmpty else { return nil }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var framebufferUUIDs: [String?] = []
        var externalServices: [io_service_t] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            switch Self.registryName(entry) {
            case "IOMobileFramebufferShim":
                let ioNameMatched = Self.stringProperty("IONameMatched", entry: entry)
                let displayWidth = Self.integerProperty("DisplayWidth", entry: entry)
                let displayHeight = Self.integerProperty("DisplayHeight", entry: entry)
                if Self.isConnectedExternalFramebuffer(
                    ioNameMatched: ioNameMatched,
                    displayWidth: displayWidth,
                    displayHeight: displayHeight
                ) {
                    framebufferUUIDs.append(Self.stringProperty("EDID UUID", entry: entry, recursive: true))
                }
                IOObjectRelease(entry)
            case "DCPAVServiceProxy" where Self.stringProperty("Location", entry: entry) == "External":
                externalServices.append(entry)
            default:
                return IOObjectRelease(entry)
            }
        }
        defer { externalServices.forEach { _ = IOObjectRelease($0) } }

        guard let candidate = Self.uniqueFramebufferServiceMatch(
            uid: uid,
            externalFramebufferUUIDs: framebufferUUIDs,
            externalServices: externalServices,
            open: { entry in
                IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
            }
        ) else { return nil }
        return DDCDisplayTarget(uid: uid, service: candidate.handle)
        #elseif arch(x86_64)
        guard let framebuffer = Self.connectedFramebuffer(forAudioUID: uid) else { return nil }
        guard Self.hasI2CBus(framebuffer) else {
            IOObjectRelease(framebuffer)
            return nil
        }
        return DDCDisplayTarget(uid: uid, service: nil, framebuffer: framebuffer)
        #else
        return nil
        #endif
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply? {
        #if arch(arm64)
        guard let service = target.service else { return nil }
        let request: [UInt8] = [Self.volumeVCP]
        for attempt in 0..<5 {
            usleep(attempt == 0 ? 10_000 : 20_000)
            var packet = Self.packet(for: request, includeDataAddressInChecksum: false)
            let writeResult = packet.withUnsafeMutableBytes {
                IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count))
            }
            guard writeResult == kIOReturnSuccess else { continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            let readResult = reply.withUnsafeMutableBytes {
                IOAVServiceReadI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count))
            }
            if readResult == kIOReturnSuccess, let decoded = DDCVolumeReply.decode(reply) {
                return decoded
            }
        }
        return nil
        #elseif arch(x86_64)
        let frame = Self.intelFrame(for: [Self.volumeVCP])
        for attempt in 0..<5 {
            usleep(attempt == 0 ? 10_000 : 20_000)
            let reply = withI2CInterface(target.framebuffer) { connect -> DDCVolumeReply? in
                // The AMD and Intel framebuffer Kexts only return a complete MCCS
                // reply when the read is its own transaction on the same claim.
                guard intelWrite(connect, frame: frame) else { return nil }
                usleep(50_000)
                return intelRead(connect).flatMap(DDCVolumeReply.decode)
            }
            if let reply { return reply }
        }
        return nil
        #else
        return nil
        #endif
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        #if arch(arm64)
        guard let service = target.service else { return false }
        let command: [UInt8] = [Self.volumeVCP, UInt8(value >> 8), UInt8(value & 0xff)]
        var succeeded = false
        for attempt in 0..<5 {
            for _ in 0..<2 {
                usleep(attempt == 0 ? 10_000 : 20_000)
                var packet = Self.packet(for: command, includeDataAddressInChecksum: true)
                succeeded = packet.withUnsafeMutableBytes {
                    IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count)) == kIOReturnSuccess
                }
            }
            if succeeded { return true }
        }
        return false
        #elseif arch(x86_64)
        let frame = Self.intelFrame(for: [Self.volumeVCP, UInt8(value >> 8), UInt8(value & 0xff)])
        var succeeded = false
        for attempt in 0..<5 {
            for _ in 0..<2 {
                usleep(attempt == 0 ? 10_000 : 20_000)
                succeeded = withI2CInterface(target.framebuffer) {
                    intelWrite($0, frame: frame) ? true : nil
                } ?? false
            }
            if succeeded { return true }
        }
        return false
        #else
        return false
        #endif
    }

    private static func packet(for bytes: [UInt8], includeDataAddressInChecksum: Bool) -> [UInt8] {
        var packet = [UInt8(0x80 | (bytes.count + 1)), UInt8(bytes.count)] + bytes + [0]
        let seed = UInt8(0x37 << 1) ^ (includeDataAddressInChecksum ? UInt8(dataAddress) : 0)
        packet[packet.count - 1] = packet.dropLast().reduce(seed, ^)
        return packet
    }

    #if arch(x86_64)
    private static let intelWriteAddress: UInt32 = 0x6E
    private static let intelReadAddress: UInt32 = 0x6F
    private static let intelReplyBytes = 11

    /// The framebuffer I2C API needs the data address on the wire as the first
    /// payload byte, which the Apple Silicon proxy supplies implicitly.
    private static func intelFrame(for bytes: [UInt8]) -> [UInt8] {
        [UInt8(dataAddress)] + packet(for: bytes, includeDataAddressInChecksum: true)
    }

    /// Claims one bus at a time, mirroring MonitorControl, so a connected
    /// display utility is never locked out by a long-lived claim.
    private func withI2CInterface<T>(_ framebuffer: io_service_t, _ body: (IOI2CConnectRef) -> T?) -> T? {
        var busCount = IOItemCount(0)
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS else { return nil }
        for bus in 0..<busCount {
            var interface = io_service_t(0)
            guard IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(interface) }
            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, IOOptionBits(), &connect) == KERN_SUCCESS, let connect else { continue }
            defer { IOI2CInterfaceClose(connect, IOOptionBits()) }
            if let result = body(connect) { return result }
        }
        return nil
    }

    private func intelWrite(_ connect: IOI2CConnectRef, frame: [UInt8]) -> Bool {
        var payload = frame
        return payload.withUnsafeMutableBytes { buffer in
            var request = IOI2CRequest()
            request.sendAddress = Self.intelWriteAddress
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBuffer = vm_address_t(bitPattern: buffer.baseAddress!)
            request.sendBytes = UInt32(buffer.count)
            request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            return IOI2CSendRequest(connect, IOOptionBits(), &request) == KERN_SUCCESS && request.result == KERN_SUCCESS
        }
    }

    private func intelRead(_ connect: IOI2CConnectRef) -> [UInt8]? {
        var reply = [UInt8](repeating: 0, count: Self.intelReplyBytes)
        let didRead = reply.withUnsafeMutableBytes { buffer -> Bool in
            var request = IOI2CRequest()
            request.replyAddress = Self.intelReadAddress
            request.replySubAddress = UInt8(Self.dataAddress)
            request.replyTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.minReplyDelay = 40_000
            request.replyBuffer = vm_address_t(bitPattern: buffer.baseAddress!)
            request.replyBytes = UInt32(buffer.count)
            return IOI2CSendRequest(connect, IOOptionBits(), &request) == KERN_SUCCESS && request.result == KERN_SUCCESS
        }
        return didRead ? reply : nil
    }
    #endif

    #if arch(arm64)
    private static func registryName(_ entry: io_registry_entry_t) -> String? {
        var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return nil }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func stringProperty(_ key: String, entry: io_registry_entry_t, recursive: Bool = false) -> String? {
        let options = recursive ? IOOptionBits(kIORegistryIterateRecursively) : 0
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, options)?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func integerProperty(_ key: String, entry: io_registry_entry_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return value as? Int
    }
    #endif
}
