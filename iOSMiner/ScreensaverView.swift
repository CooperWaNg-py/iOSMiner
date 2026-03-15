//
//  ScreensaverView.swift
//  iOSMiner
//
//  Mining visualizer with Bitcoin-themed aesthetic.
//  - Amber/gold particle field represents hashing work
//  - Green accents pulse when mining is active
//  - Share submissions trigger a gold explosion
//  - Uses CADisplayLink for smooth, efficient rendering
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ScreensaverView: View {
    let miningManager: MiningManager

    private var engine: MiningEngine { miningManager.engine }
    private var stratum: StratumClient { miningManager.stratum }

    @State private var particles: [Particle] = []
    @State private var explosionParticles: [ExplosionParticle] = []
    @State private var lastSubmitted: Int = 0
    @State private var phase: Double = 0
    @State private var displayLink: DisplayLinkBridge?

    // Rolling average hashrate
    @State private var hashrateSamples: [Double] = []
    @State private var smoothedHashrate: Double = 0
    @State private var frameCount: Int = 0

    private let particleCount = 80

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // Background glow
                backgroundGlow

                // Particle canvas
                Canvas { context, size in
                    drawParticles(context: context, size: size)
                }

                // Stats overlay
                statsOverlay
            }
            .onAppear {
                initParticles()
                startAnimation()
            }
            .onDisappear {
                displayLink?.stop()
                displayLink = nil
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Background

    private var backgroundGlow: some View {
        let intensity = normalizedHashrate
        let mining = miningManager.isRunning

        return Canvas { context, size in
            // Central amber glow when mining
            if mining {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.5
                let gradient = Gradient(stops: [
                    .init(color: Color(hue: 0.10, saturation: 0.7, brightness: 0.12 * intensity), location: 0),
                    .init(color: .clear, location: 1)
                ])
                context.fill(
                    Circle().path(in: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
                )
            }
        }
    }

    // MARK: - Draw

    private func drawParticles(context: GraphicsContext, size: CGSize) {
        // Ambient particles
        for p in particles {
            let x = p.x * size.width
            let y = p.y * size.height
            let rect = CGRect(x: x - p.size / 2, y: y - p.size / 2, width: p.size, height: p.size)
            var ctx = context
            ctx.opacity = p.opacity
            ctx.fill(Circle().path(in: rect), with: .color(p.color))
        }

        // Explosion particles
        for ep in explosionParticles {
            let x = ep.x * size.width
            let y = ep.y * size.height
            let rect = CGRect(x: x - ep.size / 2, y: y - ep.size / 2, width: ep.size, height: ep.size)
            var ctx = context
            ctx.opacity = ep.opacity
            ctx.fill(Circle().path(in: rect), with: .color(ep.color))
        }
    }

    // MARK: - Stats Overlay

    private var statsOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 4) {
                if miningManager.isRunning {
                    Text(miningManager.formattedHashRate)
                        .font(.system(size: 28, weight: .light, design: .monospaced))
                        .foregroundStyle(Color(hue: 0.12, saturation: 0.5, brightness: 0.9).opacity(0.8))
                        .contentTransition(.numericText())

                    Text("\(stratum.acceptedShares) shares")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    Text("iOSMiner")
                        .font(.system(size: 24, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.15))
                }
            }
            .padding(.bottom, 60)
        }
    }

    // MARK: - Particle System

    private func initParticles() {
        particles = (0..<particleCount).map { _ in Particle.random() }
    }

    private func startAnimation() {
        let link = DisplayLinkBridge { [self] in
            tick()
        }
        displayLink = link
        link.start()
    }

    private func tick() {
        frameCount += 1
        phase += 0.05

        // Sample hashrate every 15 frames (~0.25s at 60fps)
        if frameCount % 15 == 0 {
            let rate = engine.hashesPerSecond
            hashrateSamples.append(rate)
            if hashrateSamples.count > 10 { hashrateSamples.removeFirst() }
            smoothedHashrate = hashrateSamples.isEmpty ? 0 : hashrateSamples.reduce(0, +) / Double(hashrateSamples.count)
        }

        updateParticles()
        updateExplosionParticles()
        checkForShareExplosion()
    }

    // MARK: - Particle Updates

    private func updateParticles() {
        let speed = particleSpeed
        let mining = miningManager.isRunning
        let intensity = normalizedHashrate

        for i in particles.indices {
            // Movement
            particles[i].x += particles[i].vx * speed
            particles[i].y += particles[i].vy * speed

            // Gentle swirl
            let swirl = 0.0006 * (1.0 + intensity)
            particles[i].x += sin(phase * particles[i].drift + particles[i].phaseOffset) * swirl
            particles[i].y += cos(phase * particles[i].drift * 0.8 + particles[i].phaseOffset) * swirl

            // Opacity: breathe with hashrate
            let base = mining ? (0.12 + intensity * 0.45) : 0.04
            let pulse = sin(phase * particles[i].drift * 0.4 + particles[i].phaseOffset) * 0.1
            particles[i].opacity = max(0.02, min(0.85, base + pulse))

            // Size pulse
            let bp = particles[i].baseSize
            particles[i].size = max(1.0, bp + sin(phase * particles[i].drift * 0.3 + particles[i].phaseOffset) * bp * 0.2)

            // Recycle off-screen
            if particles[i].y < -0.06 || particles[i].y > 1.06
                || particles[i].x < -0.06 || particles[i].x > 1.06 {
                particles[i] = Particle.random()
                // Spawn from random edge
                switch Int.random(in: 0...3) {
                case 0: particles[i].y = -0.04; particles[i].x = Double.random(in: 0...1)
                case 1: particles[i].y = 1.04;  particles[i].x = Double.random(in: 0...1)
                case 2: particles[i].x = -0.04; particles[i].y = Double.random(in: 0...1)
                default: particles[i].x = 1.04;  particles[i].y = Double.random(in: 0...1)
                }
            }
        }
    }

    // MARK: - Explosion

    private func updateExplosionParticles() {
        var remove: [Int] = []
        for i in explosionParticles.indices {
            explosionParticles[i].x += explosionParticles[i].vx
            explosionParticles[i].y += explosionParticles[i].vy
            explosionParticles[i].vx *= 0.95
            explosionParticles[i].vy *= 0.95
            explosionParticles[i].opacity -= 0.02
            explosionParticles[i].size *= 0.98
            if explosionParticles[i].opacity <= 0 { remove.append(i) }
        }
        for i in remove.reversed() { explosionParticles.remove(at: i) }
    }

    private func checkForShareExplosion() {
        let current = miningManager.sharesSubmitted
        if current > lastSubmitted {
            lastSubmitted = current
            triggerExplosion()
        }
    }

    private func triggerExplosion() {
        // Gold/amber explosion — on-theme
        let count = 40
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.008...0.022)
            // Hues: gold (0.10-0.14), amber (0.06-0.09), warm white (0.12)
            let hue = Double.random(in: 0.06...0.15)
            explosionParticles.append(ExplosionParticle(
                x: 0.5 + Double.random(in: -0.015...0.015),
                y: 0.5 + Double.random(in: -0.015...0.015),
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                size: Double.random(in: 4...12),
                opacity: Double.random(in: 0.7...1.0),
                color: Color(hue: hue, saturation: Double.random(in: 0.6...1.0), brightness: Double.random(in: 0.85...1.0))
            ))
        }

        // Push nearby ambient particles
        for i in particles.indices {
            let dx = particles[i].x - 0.5
            let dy = particles[i].y - 0.5
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 0.3 && dist > 0.001 {
                let push = (0.3 - dist) * 0.015
                particles[i].vx += (dx / dist) * push
                particles[i].vy += (dy / dist) * push
            }
        }
    }

    // MARK: - Computed Values

    private var normalizedHashrate: Double {
        guard smoothedHashrate > 0 else { return 0 }
        return min(1.0, log10(max(smoothedHashrate, 1)) / 5.0)
    }

    private var particleSpeed: Double {
        let base = 0.12
        return miningManager.isRunning ? base + normalizedHashrate * 1.5 : base * 0.25
    }
}

// MARK: - Particle Model

private struct Particle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var size: Double
    var baseSize: Double
    var opacity: Double
    var color: Color
    var baseHue: Double
    var drift: Double
    var phaseOffset: Double

    static func random() -> Particle {
        // Bitcoin-themed palette: amber/gold dominant, green accent, warm tones
        let hue: Double
        let roll = Double.random(in: 0...1)
        if roll < 0.45 {
            hue = Double.random(in: 0.07...0.14)   // gold/amber
        } else if roll < 0.75 {
            hue = Double.random(in: 0.14...0.20)   // warm yellow
        } else if roll < 0.90 {
            hue = Double.random(in: 0.28...0.38)   // green accent
        } else {
            hue = Double.random(in: 0.04...0.07)   // deep orange accent
        }

        let size = Double.random(in: 1.5...5.5)
        let angle = Double.random(in: 0...(2 * .pi))
        let speed = Double.random(in: 0.001...0.004)

        return Particle(
            x: Double.random(in: 0...1),
            y: Double.random(in: 0...1),
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            size: size,
            baseSize: size,
            opacity: Double.random(in: 0.05...0.4),
            color: Color(hue: hue, saturation: Double.random(in: 0.5...0.85), brightness: Double.random(in: 0.55...0.9)),
            baseHue: hue,
            drift: Double.random(in: 0.3...2.0),
            phaseOffset: Double.random(in: 0...(2 * .pi))
        )
    }
}

// MARK: - Explosion Particle

private struct ExplosionParticle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var size: Double
    var opacity: Double
    var color: Color
}

// MARK: - CADisplayLink Bridge

/// Wraps CADisplayLink for use in SwiftUI — fires on each vsync for smooth animation.
private final class DisplayLinkBridge {
    private var displayLink: CADisplayLink?
    private let onFrame: () -> Void

    init(onFrame: @escaping () -> Void) {
        self.onFrame = onFrame
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(handleFrame))
        // 30 FPS for efficiency on A10
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        onFrame()
    }
}
