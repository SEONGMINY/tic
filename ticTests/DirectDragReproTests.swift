import XCTest
import UIKit

final class DirectDragReproTests: XCTestCase {
    func testDirectSameDayDragOnSimulator() throws {
        let app = XCUIApplication()
        app.activate()
        sleep(1)

        let beforeShot = XCUIScreen.main.screenshot().pngRepresentation
        let beforeBlock = try XCTUnwrap(findBlueBlock(in: beforeShot), "Blue block not found before drag")
        print("DIRECT-REPRO before:", beforeBlock.debugDescription)

        let start = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: beforeBlock.center.x / beforeBlock.imageSize.width,
                dy: beforeBlock.center.y / beforeBlock.imageSize.height
            )
        )
        let dragDistance: CGFloat = 280
        let end = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: beforeBlock.center.x / beforeBlock.imageSize.width,
                dy: min((beforeBlock.center.y + dragDistance) / beforeBlock.imageSize.height, 0.9)
            )
        )

        start.press(forDuration: 0.8, thenDragTo: end)
        sleep(2)

        let afterShot = XCUIScreen.main.screenshot().pngRepresentation
        let afterBlock = findBlueBlock(in: afterShot)
        print("DIRECT-REPRO after:", afterBlock?.debugDescription ?? "no-blue-block-detected")

        XCTAssertNotNil(afterBlock, "Blue block disappeared after drag")
        if let afterBlock {
            XCTAssertGreaterThan(
                afterBlock.center.y,
                beforeBlock.center.y + 120,
                "Expected block to move downward after same-day drag"
            )
        }
    }

    private func findBlueBlock(in pngData: Data) -> BlueBlockSnapshot? {
        guard let image = UIImage(data: pngData),
              let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else {
            return nil
        }

        let bytes = CFDataGetBytePtr(pixelData)!
        let bytesPerRow = cgImage.bytesPerRow
        let width = cgImage.width
        let height = cgImage.height

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var hits = 0

        for y in 0..<height {
            let row = bytes + (y * bytesPerRow)
            for x in 0..<width {
                let pixel = row + (x * 4)
                let r = Int(pixel[0])
                let g = Int(pixel[1])
                let b = Int(pixel[2])

                guard r >= 40, r <= 130,
                      g >= 160, g <= 210,
                      b >= 230, b <= 255 else {
                    continue
                }

                hits += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard hits > 0 else { return nil }
        return BlueBlockSnapshot(
            hits: hits,
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            imageSize: CGSize(width: width, height: height)
        )
    }
}

private struct BlueBlockSnapshot {
    let hits: Int
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let imageSize: CGSize

    var center: CGPoint {
        CGPoint(
            x: CGFloat(minX + maxX) / 2,
            y: CGFloat(minY + maxY) / 2
        )
    }

    var debugDescription: String {
        "hits=\(hits) bbox=(\(minX),\(minY))-(\(maxX),\(maxY)) center=(\(Int(center.x)),\(Int(center.y)))"
    }
}
