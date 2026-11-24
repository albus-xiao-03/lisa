// PROOF ONLY — Apps/Proof never ships. Renders a proof card text as a QR code with Core Image, so the owner can
// read it with another device's camera app instead of typing it. Generation only: the app never uses the camera.

import CoreImage
import CoreImage.CIFilterBuiltins

enum ProofQRCode {
    /// A crisp QR image of `text`, scaled by whole pixels; nil if Core Image produced nothing.
    static func image(for text: String, scale: CGFloat = 8) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else {
            return nil
        }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
