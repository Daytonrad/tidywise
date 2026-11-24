// Turns a series of pictures into an animated GIF – used for the demo at the top of the README.
// Usage: swift make_gif.swift <output.gif> <width> <seconds per picture> <picture.png> …
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 5, let width = Int(args[2]), let seconds = Double(args[3]) else {
    print("Usage: swift make_gif.swift <output.gif> <width> <seconds per picture> <picture.png> …")
    exit(1)
}
let output = URL(fileURLWithPath: args[1])
let pictures = args.dropFirst(4).map { URL(fileURLWithPath: $0) }

guard let gif = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, pictures.count, nil) else {
    print("Cannot write \(output.path)")
    exit(1)
}
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

var images: [CGImage] = []
for url in pictures {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("Cannot read \(url.path)")
        exit(1)
    }
    images.append(image)
}
func scaledHeight(_ image: CGImage) -> Int { Int(Double(image.height) * Double(width) / Double(image.width)) }
// All frames of a GIF share one size: the tallest picture sets it.
let height = images.map(scaledHeight).max() ?? 0

for image in images {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
    context.interpolationQuality = .high
    let own = scaledHeight(image)
    // A shorter window is continued downwards with its own bottom edge, so sidebar and page colours carry on.
    if own < height, let edge = image.cropping(to: CGRect(x: 0, y: image.height - 10, width: image.width, height: 2)) {
        context.draw(edge, in: CGRect(x: 0, y: 0, width: width, height: height - own))
    }
    context.draw(image, in: CGRect(x: 0, y: height - own, width: width, height: own))
    guard let frame = context.makeImage() else { exit(1) }
    CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: seconds]] as CFDictionary)
}
guard CGImageDestinationFinalize(gif) else {
    print("Writing the GIF failed")
    exit(1)
}
print("✓ \(output.path)")
