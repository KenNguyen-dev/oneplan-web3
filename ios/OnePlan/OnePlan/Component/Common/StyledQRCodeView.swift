//
//  StyledQRCodeView.swift
//  OnePlan
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct StyledQRCodeView: View {
    let content: String
    let color: Color
    let size: CGFloat
    /// How round each module is, as a fraction of its size. The default keeps
    /// the barely-rounded squares the friend invite QR has always drawn; the
    /// deposit screen passes 0.5 for the circular dots its design calls for.
    var moduleRoundness: CGFloat = 0.16

    private static let ciContext = CIContext()

    var body: some View {
        if let matrix = generateMatrix() {
            Canvas { context, canvasSize in
                let moduleCount = matrix.count
                let moduleSize = canvasSize.width / CGFloat(moduleCount)
                let dotSize = moduleSize * 0.98
                let cornerRadius = moduleSize * moduleRoundness

                for row in 0..<moduleCount {
                    for col in 0..<moduleCount {
                        guard matrix[row][col] else { continue }

                        let x = CGFloat(col) * moduleSize + (moduleSize - dotSize) / 2
                        let y = CGFloat(row) * moduleSize + (moduleSize - dotSize) / 2
                        let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: cornerRadius),
                            with: .color(color)
                        )
                    }
                }
            }
            .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .frame(width: size, height: size)
                .overlay {
                    Text("QR unavailable")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func generateMatrix() -> [[Bool]]? {
        guard let data = content.data(using: .ascii) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        guard let cgImage = Self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var matrix = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                matrix[y][x] = bytes[offset] == 0
            }
        }
        return matrix
    }
}

#Preview {
    StyledQRCodeView(
        content: "oneplan://friend/abc123",
        color: .blue,
        size: 222
    )
}
