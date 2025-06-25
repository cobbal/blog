func asciiImage(_ pixelAt: (Double, Double) -> Double) -> String {
    let gradient = "@%#*+=-:. ".map { "\($0)" }
    return (0..<50).map { y in
        (0..<100).map { x in
            let pixel = pixelAt(Double(x) / 50 - 1, Double(y) / 25 - 1)
            let iPixel = Int(pixel * Double(gradient.count))
            return gradient[max(0, min(iPixel, gradient.count))]
        }.joined()
    }.joined(separator: "\n")
}

let theOrb = asciiImage { x, y in
    let z = (1 - (x * x + y * y)).squareRoot()
    return z.isNaN ? 1 : (2 * x - 3 * y + 6 * z) / 7
}

print(theOrb)
