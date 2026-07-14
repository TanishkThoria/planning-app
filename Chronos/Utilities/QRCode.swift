import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Generates a crisp QR code from text, entirely on-device. Used to hand off
/// your availability with a scan.
enum QRCode {
    private static let context = CIContext()

    static func image(from string: String) -> Image? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: cg))
        #else
        return Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        #endif
    }
}
