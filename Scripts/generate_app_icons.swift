#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO

enum IconGenerationError: Error, CustomStringConvertible {
    case invalidArguments
    case unreadableImage(URL)
    case bitmapAllocation(Int)
    case contextAllocation(Int)
    case encodingFailure(URL)
    case unsafeTransparency(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Usage: generate_app_icons.swift <source-png> <AppIcon.appiconset>"
        case let .unreadableImage(url):
            return "Could not read a PNG image from \(url.path)"
        case let .bitmapAllocation(size):
            return "Could not allocate a \(size)x\(size) RGBA bitmap"
        case let .contextAllocation(size):
            return "Could not create a \(size)x\(size) graphics context"
        case let .encodingFailure(url):
            return "Could not encode \(url.path)"
        case let .unsafeTransparency(message):
            return "Transparency validation failed: \(message)"
        }
    }
}

struct Rendition {
    let filename: String
    let pixels: Int
}

let renditions = [
    Rendition(filename: "icon_16x16.png", pixels: 16),
    Rendition(filename: "icon_16x16@2x.png", pixels: 32),
    Rendition(filename: "icon_32x32.png", pixels: 32),
    Rendition(filename: "icon_32x32@2x.png", pixels: 64),
    Rendition(filename: "icon_128x128.png", pixels: 128),
    Rendition(filename: "icon_128x128@2x.png", pixels: 256),
    Rendition(filename: "icon_256x256.png", pixels: 256),
    Rendition(filename: "icon_256x256@2x.png", pixels: 512),
    Rendition(filename: "icon_512x512.png", pixels: 512),
    Rendition(filename: "icon_512x512@2x.png", pixels: 1024)
]

func loadCGImage(from url: URL) throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw IconGenerationError.unreadableImage(url)
    }
    return image
}

func makeBitmap(size: Int, drawing image: CGImage) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    ) else {
        throw IconGenerationError.bitmapAllocation(size)
    }

    guard let context = CGContext(
        data: bitmap.bitmapData,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bitmap.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw IconGenerationError.contextAllocation(size)
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return bitmap
}

func removeConnectedBlackCorners(from bitmap: NSBitmapImageRep) throws {
    guard let bytes = bitmap.bitmapData else {
        throw IconGenerationError.bitmapAllocation(bitmap.pixelsWide)
    }

    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    let rowBytes = bitmap.bytesPerRow
    let count = width * height
    var exterior = [Bool](repeating: false, count: count)
    var queue: [Int] = []
    queue.reserveCapacity(count / 3)

    func isNearBlack(_ index: Int) -> Bool {
        let x = index % width
        let y = index / width
        let offset = y * rowBytes + x * 4
        let red = Int(bytes[offset])
        let green = Int(bytes[offset + 1])
        let blue = Int(bytes[offset + 2])
        return max(red, max(green, blue)) <= 28 && (red + green + blue) <= 60
    }

    func enqueue(_ index: Int) {
        guard !exterior[index], isNearBlack(index) else {
            return
        }
        exterior[index] = true
        queue.append(index)
    }

    enqueue(0)
    enqueue(width - 1)
    enqueue((height - 1) * width)
    enqueue(count - 1)

    var cursor = 0
    while cursor < queue.count {
        let index = queue[cursor]
        cursor += 1
        let x = index % width
        let y = index / width
        if x > 0 { enqueue(index - 1) }
        if x + 1 < width { enqueue(index + 1) }
        if y > 0 { enqueue(index - width) }
        if y + 1 < height { enqueue(index + width) }
    }

    guard queue.count > count / 100 else {
        throw IconGenerationError.unsafeTransparency("fewer than 1% of pixels were identified as connected exterior")
    }
    guard queue.count < count / 2 else {
        throw IconGenerationError.unsafeTransparency("more than 50% of pixels were identified as connected exterior")
    }

    var edgeDistance = [UInt8](repeating: 255, count: count)
    for index in queue {
        edgeDistance[index] = 0
    }

    for distance: UInt8 in 1 ... 2 {
        for index in 0 ..< count where edgeDistance[index] == 255 {
            let x = index % width
            let y = index / width
            let previous = distance - 1
            let touchesPrevious =
                (x > 0 && edgeDistance[index - 1] == previous) ||
                (x + 1 < width && edgeDistance[index + 1] == previous) ||
                (y > 0 && edgeDistance[index - width] == previous) ||
                (y + 1 < height && edgeDistance[index + width] == previous)
            if touchesPrevious {
                edgeDistance[index] = distance
            }
        }
    }

    for index in 0 ..< count {
        let alpha: UInt8
        switch edgeDistance[index] {
        case 0:
            alpha = 0
        case 1:
            alpha = 96
        case 2:
            alpha = 192
        default:
            continue
        }

        let x = index % width
        let y = index / width
        let offset = y * rowBytes + x * 4
        if alpha == 0 {
            bytes[offset] = 0
            bytes[offset + 1] = 0
            bytes[offset + 2] = 0
        } else {
            bytes[offset] = UInt8((Int(bytes[offset]) * Int(alpha)) / 255)
            bytes[offset + 1] = UInt8((Int(bytes[offset + 1]) * Int(alpha)) / 255)
            bytes[offset + 2] = UInt8((Int(bytes[offset + 2]) * Int(alpha)) / 255)
        }
        bytes[offset + 3] = alpha
    }
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.encodingFailure(url)
    }
    try data.write(to: url, options: .atomic)
}

func validateTransparentCorners(_ bitmap: NSBitmapImageRep) throws {
    guard let bytes = bitmap.bitmapData else {
        throw IconGenerationError.bitmapAllocation(bitmap.pixelsWide)
    }
    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    let rowBytes = bitmap.bytesPerRow
    let corners = [
        3,
        (width - 1) * 4 + 3,
        (height - 1) * rowBytes + 3,
        (height - 1) * rowBytes + (width - 1) * 4 + 3
    ]
    guard corners.allSatisfy({ bytes[$0] == 0 }) else {
        throw IconGenerationError.unsafeTransparency("one or more master-image corners remained opaque")
    }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw IconGenerationError.invalidArguments
    }

    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let source = try loadCGImage(from: sourceURL)
    let master = try makeBitmap(size: 1024, drawing: source)
    try removeConnectedBlackCorners(from: master)
    try validateTransparentCorners(master)
    guard let masterImage = master.cgImage else {
        throw IconGenerationError.bitmapAllocation(1024)
    }

    for rendition in renditions {
        let bitmap: NSBitmapImageRep
        if rendition.pixels == 1024 {
            bitmap = master
        } else {
            bitmap = try makeBitmap(size: rendition.pixels, drawing: masterImage)
        }
        try writePNG(bitmap, to: outputURL.appendingPathComponent(rendition.filename))
    }

    print("Generated \(renditions.count) icon renditions with transparent connected corners.")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
