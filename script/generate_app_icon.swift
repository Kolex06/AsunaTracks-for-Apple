import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Package the existing brand artwork as an opaque, system-masked app icon.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let data = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(data, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let canvas = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Could not read brand artwork") }
canvas.setFillColor(CGColor(srgbRed: 0.02, green: 0.035, blue: 0.086, alpha: 1))
canvas.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
canvas.interpolationQuality = .high
canvas.draw(image, in: CGRect(x: 62, y: 62, width: 900, height: 900))
guard let result = canvas.makeImage(), let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Could not create icon") }
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
