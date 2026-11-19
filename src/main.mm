// Spelltide: the Mac window, drawing, keys and sound.
// The rules live in Game.hpp (plain C++). This file is the thin Apple layer.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include <unordered_map>

#include "Game.hpp"

using namespace tide;

namespace {

// Everything is drawn in a fixed 600 x 840 space, then scaled to the window.
const CGFloat W = 600, H = 840;
const CGFloat kTile = 58, kGap = 8, kPitch = kTile + kGap;
const CGFloat kBoardX = 40, kBoardY = 152;
const CGFloat kBoard = kTile * kSide + kGap * (kSide - 1);  // 520
const NSRect kTank = {{24, 136}, {552, 552}};
const CGFloat kTankR = 26;
const CGFloat kShelfY = 762;

struct RGB { CGFloat r, g, b; };
const RGB kAbyssTop{0.059, 0.231, 0.306};
const RGB kAbyssBot{0.020, 0.090, 0.135};
const RGB kWell{0.012, 0.063, 0.094};
const RGB kWater{0.169, 0.702, 0.659};
const RGB kWaterDeep{0.055, 0.365, 0.451};
const RGB kFoam{0.949, 0.984, 0.969};
const RGB kGlassHi{0.878, 0.969, 0.941};
const RGB kGlassLo{0.647, 0.863, 0.816};
const RGB kGlassEdge{0.337, 0.612, 0.600};
const RGB kInk{0.035, 0.196, 0.251};
const RGB kAmberHi{1.000, 0.890, 0.620};
const RGB kAmberLo{1.000, 0.706, 0.263};
const RGB kAmberEdge{0.769, 0.463, 0.094};
const RGB kAmberInk{0.290, 0.157, 0.000};
const RGB kCoral{1.000, 0.353, 0.235};
const RGB kCoralDeep{0.640, 0.150, 0.090};
const RGB kWhite{1, 1, 1};

CGFloat gGlow = 1;    // glow sizes do not follow the drawing scale, so we do it by hand
CGFloat gPixels = 2;  // screen pixels per drawing unit

NSColor* C(RGB c, CGFloat a = 1) { return [NSColor colorWithSRGBRed:c.r green:c.g blue:c.b alpha:a]; }

RGB Mix(RGB a, RGB b, CGFloat t) {
    t = std::clamp<CGFloat>(t, 0, 1);
    return {a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t};
}

// 0 -> 1 with a little overshoot. Used when a tile appears.
CGFloat Pop(double age) {
    if (age <= 0) return 0;
    if (age >= 0.6) return 1;
    return 1 - exp(-9 * age) * cos(13 * age);
}

NSFont* Font(NSString* name, CGFloat size) {
    static NSMutableDictionary<NSString*, NSFont*>* cache = [NSMutableDictionary new];
    NSString* key = [NSString stringWithFormat:@"%@/%.1f", name, size];
    NSFont* f = cache[key];
    if (!f) {
        f = [NSFont fontWithName:name size:size] ?: [NSFont systemFontOfSize:size weight:NSFontWeightHeavy];
        cache[key] = f;
    }
    return f;
}
NSFont* Display(CGFloat s) { return Font(@"Superclarendon-Black", s); }
NSFont* Body(CGFloat s) { return Font(@"AvenirNext-Medium", s); }
NSFont* BodyBold(CGFloat s) { return Font(@"AvenirNext-DemiBold", s); }

// Draws one line with the middle of its capital letters at y.
// align: -1 starts at x, 0 centres on x, 1 ends at x.
void Label(NSString* s, NSFont* f, NSColor* col, CGFloat x, CGFloat y, int align) {
    NSDictionary* a = @{NSFontAttributeName: f, NSForegroundColorAttributeName: col};
    CGFloat w = [s sizeWithAttributes:a].width;
    CGFloat left = align < 0 ? x : align == 0 ? x - w / 2 : x - w;
    [s drawAtPoint:NSMakePoint(left, y - f.ascender + f.capHeight / 2) withAttributes:a];
}

void GlowOn(RGB c, CGFloat alpha, CGFloat blur) {
    NSShadow* s = [NSShadow new];
    s.shadowColor = C(c, alpha);
    s.shadowBlurRadius = blur * gGlow;
    s.shadowOffset = NSZeroSize;
    [s set];
}

NSBezierPath* RR(NSRect r, CGFloat rad) {
    return [NSBezierPath bezierPathWithRoundedRect:r xRadius:rad yRadius:rad];
}

NSString* Num(int n) {
    static NSNumberFormatter* f;
    if (!f) { f = [NSNumberFormatter new]; f.numberStyle = NSNumberFormatterDecimalStyle; }
    return [f stringFromNumber:@(n)];
}

NSRect CellRect(int i) {
    return NSMakeRect(kBoardX + (i % kSide) * kPitch, kBoardY + (i / kSide) * kPitch, kTile, kTile);
}

// One sea-glass tile, centred on the origin. Amber when it is part of the word.
void DrawTileFace(CGFloat size, char ch, bool amber, CGFloat bad, CGFloat alpha) {
    static NSGradient* glass = [[NSGradient alloc] initWithStartingColor:C(kGlassHi) endingColor:C(kGlassLo)];
    static NSGradient* gold = [[NSGradient alloc] initWithStartingColor:C(kAmberHi) endingColor:C(kAmberLo)];

    CGFloat depth = size * 0.06, rad = size * 0.26;
    NSRect face = NSMakeRect(-size / 2, -size / 2, size, size - depth);
    NSRect slab = NSOffsetRect(face, 0, depth);
    RGB hi = amber ? kAmberHi : kGlassHi, lo = amber ? kAmberLo : kGlassLo;
    RGB edge = amber ? kAmberEdge : kGlassEdge, ink = amber ? kAmberInk : kInk;
    if (bad > 0) {
        hi = Mix(hi, kCoral, bad * 0.55);
        lo = Mix(lo, kCoral, bad * 0.85);
        edge = Mix(edge, kCoralDeep, bad);
    }

    [NSGraphicsContext saveGraphicsState];
    if (amber) GlowOn(kAmberLo, 0.8 * alpha, 16);
    [C(edge, alpha) setFill];
    [RR(slab, rad) fill];
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath* p = RR(face, rad);
    if (bad > 0 || alpha < 1) {
        [[[NSGradient alloc] initWithStartingColor:C(hi, alpha) endingColor:C(lo, alpha)] drawInBezierPath:p angle:90];
    } else {
        [(amber ? gold : glass) drawInBezierPath:p angle:90];
    }
    NSBezierPath* rim = RR(NSInsetRect(face, 0.75, 0.75), rad - 0.75);
    rim.lineWidth = 1;
    [C(kWhite, 0.6 * alpha) setStroke];
    [rim stroke];

    NSString* s = [NSString stringWithFormat:@"%c", toupper(ch)];
    Label(s, Display(size * 0.5), C(ink, alpha), 0, NSMidY(face), 0);
}

// Tiles are painted once per letter, kept as pictures, then stamped each frame.
// That is much faster than painting 64 tiles from scratch 60 times a second.
struct TileSprites {
    CGFloat pixels = 0;
    std::unordered_map<int, CGImageRef> images;
};
TileSprites gSprites;

CGFloat SpritePad(bool amber) { return amber ? 24 : 2; }  // amber needs room for its glow

CGImageRef TileSprite(char ch, bool amber) {
    if (gSprites.pixels != gPixels) {
        for (auto& entry : gSprites.images) CGImageRelease(entry.second);
        gSprites.images.clear();
        gSprites.pixels = gPixels;
    }
    int key = (ch - 'a') * 2 + (amber ? 1 : 0);
    auto found = gSprites.images.find(key);
    if (found != gSprites.images.end()) return found->second;

    CGFloat side = kTile + 2 * SpritePad(amber);
    size_t px = (size_t)ceil(side * gPixels);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = CGBitmapContextCreate(NULL, px, px, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(c, px / 2.0, px / 2.0);
    CGContextScaleCTM(c, px / side, -(px / side));
    CGFloat keep = gGlow;
    gGlow = gPixels;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:c flipped:YES];
    DrawTileFace(kTile, ch, amber, 0, 1);
    [NSGraphicsContext restoreGraphicsState];
    gGlow = keep;
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    CGColorSpaceRelease(cs);
    gSprites.images[key] = img;
    return img;
}

// Stamps a tile centred on the origin. Falls back to live painting for the red "not a word" flash.
void DrawTile(CGFloat size, char ch, bool amber, CGFloat bad, CGFloat alpha) {
    if (bad > 0) { DrawTileFace(size, ch, amber, bad, alpha); return; }
    CGImageRef img = TileSprite(ch, amber);
    CGFloat half = (kTile / 2 + SpritePad(amber)) * size / kTile;
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(cg);
    CGContextScaleCTM(cg, 1, -1);
    CGContextSetAlpha(cg, alpha);
    CGContextSetInterpolationQuality(cg, kCGInterpolationLow);
    CGContextDrawImage(cg, CGRectMake(-half, -half, 2 * half, 2 * half), img);
    CGContextRestoreGState(cg);
}

struct Bubble { CGFloat x, y, vx, vy, r, life, maxLife; RGB col; };
struct Ghost { int cell; char ch; double at; bool amber; };
struct Floater { CGFloat x, y; double at; int points; };

}  // namespace

// ---------------------------------------------------------------- the view

@interface GameView : NSView
- (void)startClock;
- (void)stage:(const char*)scene;
- (void)drawBackdropIn:(NSRect)r;
- (void)renderScene;
- (IBAction)newGame:(id)sender;
@end

@implementation GameView {
    Game _game;
    std::mt19937 _rng;
    std::vector<Bubble> _bursts;   // bubbles from cleared tiles
    std::vector<Bubble> _drift;    // slow bubbles rising in the water
    std::vector<Ghost> _ghosts;
    std::vector<Floater> _floaters;
    double _last, _shown, _level, _driftDebt;
    double _shakeAt, _shakeSize, _scoreAt, _levelAt, _overAt, _pickAt, _missAt;
    char _missCh;
    BOOL _paused, _headless;
    CGImageRef _backdrop;
    NSTimer* _timer;
    NSMutableDictionary<NSString*, NSSound*>* _sounds;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        NSString* words = [NSBundle.mainBundle pathForResource:@"words" ofType:@"txt"];
        if (!words || !_game.loadWords(words.UTF8String)) _game.loadWords("/usr/share/dict/words");
        _game.best = (int)[NSUserDefaults.standardUserDefaults integerForKey:@"best"];
        _rng.seed(std::random_device{}());
        _shakeAt = _scoreAt = _levelAt = _overAt = _pickAt = _missAt = -100;
        _shakeSize = 1;
        _sounds = [NSMutableDictionary new];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (CGFloat)rnd:(CGFloat)lo to:(CGFloat)hi {
    return std::uniform_real_distribution<CGFloat>(lo, hi)(_rng);
}

// ------------------------------------------------------------ game loop

- (void)startClock {
    _last = CACurrentMediaTime();
    if (@available(macOS 14.0, *)) {
        CADisplayLink* link = [self displayLinkWithTarget:self selector:@selector(tick)];
        link.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    } else {
        _timer = [NSTimer timerWithTimeInterval:1.0 / 60 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}

- (void)tick {
    double now = CACurrentMediaTime();
    double dt = std::min(now - _last, 0.05);
    _last = now;
    // Looking away pauses the game.
    _paused = _game.phase == Phase::Playing && !NSApp.isActive;
    if (!_paused) [self advance:dt];
    self.needsDisplay = YES;
}

- (void)advance:(double)dt {
    _game.update(dt);
    for (const Event& e : _game.events) [self react:e];
    _game.events.clear();

    _shown += (_game.score - _shown) * std::min(1.0, dt * 9);
    _level += (_game.fill() - _level) * std::min(1.0, dt * 5);

    for (Bubble& b : _bursts) {
        b.vy -= 170 * dt;
        b.vx *= 1 - 2.4 * dt;
        b.vy *= 1 - 1.2 * dt;
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        b.life -= dt;
    }
    std::erase_if(_bursts, [](const Bubble& b) { return b.life <= 0; });

    CGFloat surface = [self surfaceY];
    _driftDebt += dt * 7 * _level;
    while (_driftDebt >= 1) {
        _driftDebt -= 1;
        CGFloat x = [self rnd:NSMinX(kTank) + 12 to:NSMaxX(kTank) - 12];
        _drift.push_back({x, NSMaxY(kTank) + 4, 0, -[self rnd:22 to:60], [self rnd:1.4 to:3.8], 1, 1, kFoam});
    }
    for (Bubble& b : _drift) {
        b.y += b.vy * dt;
        b.x += sin(_game.clock * 3 + b.r * 9) * 8 * dt;
    }
    std::erase_if(_drift, [surface](const Bubble& b) { return b.y < surface + 4; });

    double now = _game.clock;
    std::erase_if(_ghosts, [now](const Ghost& g) { return now - g.at > 0.4; });
    std::erase_if(_floaters, [now](const Floater& f) { return now - f.at > 1.1; });
}

- (void)react:(const Event&)e {
    double now = _game.clock;
    switch (e.kind) {
        case Event::Pick:
            _pickAt = now;
            break;
        case Event::Miss:
            _missAt = now; _missCh = e.ch;
            _shakeAt = now; _shakeSize = 0.4;
            break;
        case Event::Clear: {
            bool amber = e.value > 0;
            _ghosts.push_back({e.cell, e.ch, now, amber});
            NSRect r = CellRect(e.cell);
            for (int k = 0, n = amber ? 9 : 3; k < n; ++k) {
                CGFloat ang = [self rnd:0 to:2 * M_PI], speed = [self rnd:40 to:190];
                CGFloat life = [self rnd:0.5 to:1.1];
                RGB col = amber ? Mix(kAmberLo, kFoam, [self rnd:0 to:1]) : Mix(kGlassLo, kFoam, [self rnd:0 to:1]);
                _bursts.push_back({NSMidX(r), NSMidY(r), cos(ang) * speed, sin(ang) * speed - 40,
                                   [self rnd:2 to:6], life, life, col});
            }
            break;
        }
        case Event::Scored: {
            NSRect r = CellRect(e.cell);
            _floaters.push_back({NSMidX(r), NSMidY(r), now, e.value});
            _scoreAt = now;
            [self play:@"Pop" volume:0.5];
            break;
        }
        case Event::Reject:
            _shakeAt = now; _shakeSize = 1;
            [self play:@"Basso" volume:0.2];
            break;
        case Event::LevelUp:
            _levelAt = now;
            [self play:@"Glass" volume:0.25];
            break;
        case Event::GameOver:
            _overAt = now;
            if (!_headless) [NSUserDefaults.standardUserDefaults setInteger:_game.best forKey:@"best"];
            [self play:@"Submarine" volume:0.5];
            break;
        default:
            break;
    }
}

- (void)play:(NSString*)name volume:(float)volume {
    if (_headless) return;
    NSSound* s = _sounds[name];
    if (!s) {
        s = [NSSound soundNamed:name];
        if (!s) return;
        _sounds[name] = s;
    }
    [s stop];
    s.volume = volume;
    [s play];
}

- (IBAction)newGame:(__unused id)sender {
    _bursts.clear(); _ghosts.clear(); _floaters.clear();
    _shown = 0;
    _game.start();
}

// ------------------------------------------------------------ input

- (void)keyDown:(NSEvent*)e {
    if (e.modifierFlags & NSEventModifierFlagCommand) { [super keyDown:e]; return; }
    unsigned short k = e.keyCode;
    BOOL go = k == 36 || k == 76 || k == 49;  // return, enter, space

    if (_game.phase != Phase::Playing) {
        // The short wait stops a late Enter from skipping the final score.
        BOOL ready = _game.phase == Phase::Title || _game.clock - _overAt > 0.8;
        if (go && ready && !e.isARepeat) [self newGame:nil];
        return;
    }
    if (k == 51) { _game.backspace(); return; }     // delete
    if (k == 53) { _game.clearPicked(); return; }   // escape
    if (e.isARepeat) return;
    if (go) { _game.submit(); return; }
    NSString* s = e.charactersIgnoringModifiers.lowercaseString;
    if (s.length == 1) {
        unichar ch = [s characterAtIndex:0];
        if (ch >= 'a' && ch <= 'z') _game.typeLetter((char)ch);
    }
}

- (void)mouseDown:(NSEvent*)e {
    if (_game.phase != Phase::Playing) {
        if (_game.phase == Phase::Title || _game.clock - _overAt > 0.8) [self newGame:nil];
        return;
    }
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSRect b = self.bounds;
    CGFloat s = std::min(b.size.width / W, b.size.height / H);
    p.x = (p.x - (b.size.width - W * s) / 2) / s;
    p.y = (p.y - (b.size.height - H * s) / 2) / s;
    for (int i = 0; i < kCells; ++i) {
        if (NSPointInRect(p, NSInsetRect(CellRect(i), -kGap / 2, -kGap / 2))) { _game.clickCell(i); break; }
    }
}

// ------------------------------------------------------------ drawing

- (void)drawRect:(__unused NSRect)dirty {
    double t0 = CACurrentMediaTime();
    NSRect b = self.bounds;
    CGFloat s = std::min(b.size.width / W, b.size.height / H);
    gGlow = s;
    gPixels = s * (self.window ? self.window.backingScaleFactor : 2);
    [self drawBackdropIn:b];
    NSAffineTransform* t = [NSAffineTransform transform];
    [t translateXBy:(b.size.width - W * s) / 2 yBy:(b.size.height - H * s) / 2];
    [t scaleBy:s];
    [NSGraphicsContext saveGraphicsState];
    [t concat];
    [self renderScene];
    [NSGraphicsContext restoreGraphicsState];

    // SPELLTIDE_STATS=1 prints how long drawing takes and how many frames we get.
    static const bool stats = getenv("SPELLTIDE_STATS") != nullptr;
    static double spent = 0, since = t0;
    static int frames = 0;
    spent += CACurrentMediaTime() - t0;
    if (stats && ++frames == 120) {
        double now = CACurrentMediaTime();
        fprintf(stderr, "draw %.1f ms, %.0f frames a second\n", spent * 1000 / frames, frames / (now - since));
        spent = 0; frames = 0; since = now;
    }
}

// Deep water with light from above, plus the empty tank. Painted once per window size, then reused.
- (void)drawBackdropIn:(NSRect)r {
    CGContextRef d = NSGraphicsContext.currentContext.CGContext;
    CGRect dev = CGContextConvertRectToDeviceSpace(d, r);
    size_t w = (size_t)llround(dev.size.width), h = (size_t)llround(dev.size.height);
    if (w == 0 || h == 0) return;
    if (!_backdrop || CGImageGetWidth(_backdrop) != w || CGImageGetHeight(_backdrop) != h) {
        CGImageRelease(_backdrop);
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedLast);
        CGFloat base[] = {kAbyssTop.r, kAbyssTop.g, kAbyssTop.b, 1, kAbyssBot.r, kAbyssBot.g, kAbyssBot.b, 1};
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, base, NULL, 2);
        CGContextDrawLinearGradient(c, g, CGPointMake(0, h), CGPointMake(0, h * 0.15), kCGGradientDrawsAfterEndLocation);
        CGFloat light[] = {0.30, 0.78, 0.74, 0.30, 0.30, 0.78, 0.74, 0};
        CGGradientRef lg = CGGradientCreateWithColorComponents(cs, light, NULL, 2);
        CGPoint sun = CGPointMake(w * 0.62, h * 1.12);
        CGContextDrawRadialGradient(c, lg, sun, 0, sun, h * 0.8, 0);

        // The empty tank never changes, so it is painted here too.
        CGFloat k = w / r.size.width, fit = std::min(r.size.width / W, r.size.height / H);
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, 0, h);
        CGContextScaleCTM(c, k, -k);
        CGContextTranslateCTM(c, (r.size.width - W * fit) / 2, (r.size.height - H * fit) / 2);
        CGContextScaleCTM(c, fit, fit);
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:c flipped:YES];
        [[[NSGradient alloc] initWithStartingColor:C(kWell, 0.5) endingColor:C(kWell, 0.78)]
            drawInBezierPath:RR(kTank, kTankR) angle:90];
        [C(kFoam, 0.2) setFill];
        for (int row = 1; row < kSide; ++row) {  // depth marks down the left wall
            CGFloat y = kBoardY - kGap / 2 + row * kPitch;
            NSRectFillUsingOperation(NSMakeRect(NSMinX(kTank), y - 0.5, row % 2 ? 6 : 10, 1), NSCompositingOperationSourceOver);
        }
        [C(kFoam, 0.045) setFill];
        for (int i = 0; i < kCells; ++i) [RR(NSInsetRect(CellRect(i), 4, 4), 12) fill];
        [NSGraphicsContext restoreGraphicsState];
        CGContextRestoreGState(c);

        // A pinch of grain hides the stripes that dark gradients get.
        uint8_t* px = (uint8_t*)CGBitmapContextGetData(c);
        size_t stride = CGBitmapContextGetBytesPerRow(c);
        uint32_t seed = 2463534242u;
        for (size_t y = 0; y < h; ++y) {
            uint8_t* row = px + y * stride;
            for (size_t x = 0; x < w; ++x, row += 4) {
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
                int n = int(seed % 5) - 2;
                for (int k = 0; k < 3; ++k) row[k] = (uint8_t)std::clamp(row[k] + n, 0, 255);
            }
        }
        _backdrop = CGBitmapContextCreateImage(c);
        CGGradientRelease(g);
        CGGradientRelease(lg);
        CGContextRelease(c);
        CGColorSpaceRelease(cs);
    }
    CGContextSaveGState(d);
    CGContextTranslateCTM(d, r.origin.x, r.origin.y + r.size.height);
    CGContextScaleCTM(d, 1, -1);
    CGContextSetInterpolationQuality(d, kCGInterpolationNone);
    CGContextDrawImage(d, CGRectMake(0, 0, r.size.width, r.size.height), _backdrop);
    CGContextRestoreGState(d);
}

- (void)renderScene {
    [self drawHeader];
    [self drawTank];
    [self drawFloaters];
    [self drawShelf];
    [self drawBanner];
    [self drawOverlay];
}

- (void)drawHeader {
    double now = _game.clock;
    Label(@"Spelltide", Display(26), C(kFoam), 40, 64, -1);
    Label([NSString stringWithFormat:@"Level %d", _game.level], Body(14), C(kFoam, 0.62), 41, 100, -1);

    CGFloat s = 1 + 0.2 * exp(-(now - _scoreAt) * 9);
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(cg);
    CGContextTranslateCTM(cg, 560, 62);
    CGContextScaleCTM(cg, s, s);
    Label(Num((int)llround(_shown)), Display(44), C(kFoam), 0, 0, 1);
    CGContextRestoreGState(cg);

    int best = std::max(_game.best, _game.score);
    if (best > 0) Label([NSString stringWithFormat:@"Best %@", Num(best)], Body(14), C(kFoam, 0.62), 560, 100, 1);
}

- (CGFloat)surfaceY {
    return (kBoardY + kBoard + 12) - _level * (kBoard + 24);
}

// The wavy water surface at levelY. With a floor it becomes a filled shape down to that y.
- (NSBezierPath*)wave:(CGFloat)levelY phase:(CGFloat)ph amp:(CGFloat)amp floor:(CGFloat)floorY {
    double t = _game.clock;
    CGFloat x0 = NSMinX(kTank), x1 = NSMaxX(kTank);
    NSBezierPath* p = [NSBezierPath bezierPath];
    BOOL first = YES;
    for (CGFloat x = x0; x <= x1 + 0.5; x += 8) {
        CGFloat y = levelY + amp * (sin(x * 0.030 + t * 1.5 + ph) + 0.5 * sin(x * 0.071 - t * 2.2 + ph * 2));
        if (first) [p moveToPoint:NSMakePoint(x, y)]; else [p lineToPoint:NSMakePoint(x, y)];
        first = NO;
    }
    if (!isnan(floorY)) {
        [p lineToPoint:NSMakePoint(x1, floorY)];
        [p lineToPoint:NSMakePoint(x0, floorY)];
        [p closePath];
    }
    return p;
}

- (void)drawTank {
    double now = _game.clock;
    CGFloat danger = std::min(1.0, _game.fullFor / 0.4);
    // Full tank: the water turns red and gets rough.
    RGB wcol = Mix(kWater, kCoral, danger * (0.72 + 0.12 * sin(now * 9)));
    RGB dcol = Mix(kWaterDeep, kCoralDeep, 0.9 * danger);
    CGFloat levelY = [self surfaceY];
    CGFloat amp = 3 + 3 * danger;
    NSBezierPath* tank = RR(kTank, kTankR);

    // Every see-through layer the size of the tank costs real time, so there are only two:
    // the water behind the tiles and a thin tint in front of them.
    [NSGraphicsContext saveGraphicsState];
    [tank addClip];
    [C(dcol, 0.6) setFill];
    [[self wave:levelY - 6 phase:2.1 amp:amp floor:levelY + 2 * amp] fill];  // a second wave just behind
    NSBezierPath* body = [self wave:levelY phase:0 amp:amp floor:NSMaxY(kTank)];
    [C(Mix(dcol, wcol, 0.55), 0.87) setFill];
    [body fill];

    for (int i = 0; i < kCells; ++i) if (_game.grid[i].order < 0) [self drawTile:i];

    // water in front: tiles under the surface look sunk
    [C(wcol, 0.2 - 0.06 * danger) setFill];
    [body fill];
    NSBezierPath* line = [self wave:levelY phase:0 amp:amp floor:NAN];
    line.lineWidth = 1.6;
    [C(kFoam, 0.8) setStroke];
    [line stroke];

    for (const Bubble& b : _drift) {
        NSBezierPath* o = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(b.x - b.r, b.y - b.r, 2 * b.r, 2 * b.r)];
        o.lineWidth = 1;
        [C(kFoam, 0.4) setStroke];
        [o stroke];
    }
    [NSGraphicsContext restoreGraphicsState];

    // picked tiles sit above the water
    for (int i = 0; i < kCells; ++i) if (_game.grid[i].order >= 0) [self drawTile:i];

    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    for (const Ghost& g : _ghosts) {
        CGFloat k = (now - g.at) / 0.4;
        NSRect r = CellRect(g.cell);
        CGContextSaveGState(cg);
        CGContextTranslateCTM(cg, NSMidX(r), NSMidY(r) - 10 * k);
        CGContextScaleCTM(cg, 1 + 0.45 * k, 1 + 0.45 * k);
        DrawTile(kTile, g.ch, g.amber, 0, (1 - k) * (1 - k));
        CGContextRestoreGState(cg);
    }
    for (const Bubble& b : _bursts) {
        CGFloat a = std::min<CGFloat>(1, b.life / (b.maxLife * 0.5));
        NSBezierPath* o = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(b.x - b.r, b.y - b.r, 2 * b.r, 2 * b.r)];
        [C(b.col, 0.28 * a) setFill];
        [o fill];
        o.lineWidth = 1.2;
        [C(b.col, 0.95 * a) setStroke];
        [o stroke];
    }

    // rim, and the countdown that runs around it when the tank is full
    tank.lineWidth = 1.5;
    [C(Mix(kFoam, kCoral, danger), 0.26 + 0.3 * danger) setStroke];
    [tank stroke];
    if (_game.fullFor > 0 && _game.phase == Phase::Playing) {
        CGFloat left = std::max(0.002, 1 - _game.fullFor / kFullLimit);
        CGFloat around = 2 * (kTank.size.width + kTank.size.height) - 8 * kTankR + 2 * M_PI * kTankR;
        CGFloat dash[2] = {around * left, around};
        NSBezierPath* ring = RR(kTank, kTankR);
        [ring setLineDash:dash count:2 phase:0];
        ring.lineCapStyle = NSLineCapStyleRound;
        const CGFloat widths[] = {18, 11, 5}, alphas[] = {0.12, 0.22, 1};  // wide faint strokes make the glow
        for (int k = 0; k < 3; ++k) {
            ring.lineWidth = widths[k];
            [C(kCoral, alphas[k]) setStroke];
            [ring stroke];
        }
    }
}

- (void)drawTile:(int)i {
    const Tile& t = _game.grid[i];
    double now = _game.clock, age = now - t.born;
    if (!t.ch || age < 0) return;
    bool on = t.order >= 0;
    NSRect r = CellRect(i);
    CGFloat s = Pop(age) * (on ? 1.06 : 1);
    CGFloat dx = 0, dy = on ? -3 : 0;
    double rj = now - t.rejectedAt;
    CGFloat bad = rj < 0.45 ? 1 - rj / 0.45 : 0;
    dx += sin(rj * 55) * 7 * bad;
    if (_game.phase == Phase::Playing && _game.fullFor > 0) {  // the full tank trembles
        dx += round(sin(now * 37 + i * 1.7) * 0.9 * gPixels) / gPixels;
        dy += round(cos(now * 41 + i * 2.3) * 0.9 * gPixels) / gPixels;
    }

    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(cg);
    CGContextTranslateCTM(cg, NSMidX(r) + dx, NSMidY(r) + dy);
    if (age < 0.4) {  // ripple where the letter lands
        CGFloat k = age / 0.4, rad = 22 + 26 * k;
        NSBezierPath* ring = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-rad, -rad, 2 * rad, 2 * rad)];
        ring.lineWidth = 2;
        [C(kFoam, 0.55 * (1 - k)) setStroke];
        [ring stroke];
    }
    CGContextScaleCTM(cg, s, s);
    DrawTile(kTile, t.ch, on, bad, 1);
    CGContextRestoreGState(cg);
}

- (void)drawFloaters {
    double now = _game.clock;
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    for (const Floater& f : _floaters) {
        double a = now - f.at;
        CGFloat alpha = a < 0.7 ? 1 : std::max(0.0, 1 - (a - 0.7) / 0.4);
        CGFloat s = 0.6 + 0.4 * Pop(a);
        CGContextSaveGState(cg);
        CGContextTranslateCTM(cg, std::clamp<CGFloat>(f.x, 90, W - 90), f.y - 20 - 46 * a);
        CGContextScaleCTM(cg, s, s);
        GlowOn(kInk, 0.9 * alpha, 10);
        Label([NSString stringWithFormat:@"+%d", f.points], Display(34), C(kAmberHi, alpha), 0, 0, 0);
        CGContextRestoreGState(cg);
    }
}

// The word being spelled, as small tiles standing on a line under the tank.
- (void)drawShelf {
    double now = _game.clock;
    bool playing = _game.phase == Phase::Playing;
    std::string w = _game.word();
    bool valid = _game.isWord(w);
    size_t n = w.size();

    double sh = now - _shakeAt;
    CGFloat dx = sh < 0.4 ? sin(sh * 50) * 9 * (1 - sh / 0.4) * _shakeSize : 0;

    NSBezierPath* line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(40 + dx, kShelfY)];
    [line lineToPoint:NSMakePoint(560 + dx, kShelfY)];
    line.lineCapStyle = NSLineCapStyleRound;
    if (valid) {
        const CGFloat widths[] = {12, 7}, alphas[] = {0.12, 0.2};
        for (int k = 0; k < 2; ++k) {
            line.lineWidth = widths[k];
            [C(kAmberLo, alphas[k]) setStroke];
            [line stroke];
        }
    }
    line.lineWidth = 2;
    [C(valid ? kAmberLo : kFoam, valid ? 1 : 0.24) setStroke];
    [line stroke];

    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    if (n) {
        CGFloat gap = 6;
        CGFloat size = std::min<CGFloat>(44, (520 - (n - 1) * gap) / n);
        CGFloat x0 = 300 - (n * (size + gap) - gap) / 2 + size / 2;
        for (size_t k = 0; k < n; ++k) {
            CGFloat s = k == n - 1 ? 0.7 + 0.3 * Pop(now - _pickAt) : 1;
            CGContextSaveGState(cg);
            CGContextTranslateCTM(cg, x0 + k * (size + gap) + dx, kShelfY - 9 - size / 2);
            CGContextScaleCTM(cg, s, s);
            DrawTile(size, w[k], true, 0, 1);
            CGContextRestoreGState(cg);
        }
    } else if (playing && fmod(now, 1.0) < 0.55) {
        [C(kFoam, 0.5) setFill];
        NSRectFillUsingOperation(NSMakeRect(299, kShelfY - 44, 2, 34), NSCompositingOperationSourceOver);
    }

    if (!playing) return;
    CGFloat y = kShelfY + 32;
    if (valid) Label([NSString stringWithFormat:@"+%d", Game::pointsFor(n)], Display(22), C(kAmberLo), 560, y, 1);

    if (_game.fullFor > 0) {
        NSString* s = [NSString stringWithFormat:@"Tank is full. Flooding in %.1fs", std::max(0.0, kFullLimit - _game.fullFor)];
        Label(s, BodyBold(16), C(kCoral), 40, y, -1);
    } else if (now - _missAt < 1.3) {
        Label([NSString stringWithFormat:@"No free %c in the tank", toupper(_missCh)], Body(15), C(kFoam, 0.75), 40, y, -1);
    } else if (n == 0) {
        Label(@"Type letters to spell a word", Body(15), C(kFoam, 0.55), 40, y, -1);
    } else if (valid) {
        Label(@"Press Enter to clear it", Body(15), C(kFoam, 0.85), 40, y, -1);
    } else if (n < kMinWord) {
        Label(@"Words need 2 letters or more", Body(15), C(kFoam, 0.55), 40, y, -1);
    } else {
        Label(@"Not a word yet", Body(15), C(kFoam, 0.55), 40, y, -1);
    }
}

- (void)drawBanner {
    double a = _game.clock - _levelAt;
    if (a > 1.5 || _game.phase != Phase::Playing) return;
    CGFloat alpha = std::min(1.0, a / 0.12) * (a < 1.1 ? 1 : std::max(0.0, 1 - (a - 1.1) / 0.4));
    CGFloat s = 0.8 + 0.2 * Pop(a);
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(cg);
    CGContextTranslateCTM(cg, W / 2, NSMidY(kTank));
    CGContextScaleCTM(cg, s, s);
    GlowOn(kWell, alpha, 18);
    Label([NSString stringWithFormat:@"Level %d", _game.level], Display(52), C(kFoam, alpha), 0, -14, 0);
    Label(@"Letters come faster", BodyBold(17), C(kFoam, alpha), 0, 32, 0);
    CGContextRestoreGState(cg);
}

// A dark card over the tank for the start, pause and game-over messages.
- (void)card:(NSRect)r alpha:(CGFloat)alpha {
    NSBezierPath* p = RR(r, 30);
    [C(kWell, 0.975 * alpha) setFill];
    [p fill];
    p.lineWidth = 1.5;
    [C(kFoam, 0.22 * alpha) setStroke];
    [p stroke];
}

- (void)drawOverlay {
    double now = _game.clock;
    Phase ph = _game.phase;
    if (ph == Phase::Playing && !_paused) return;
    CGFloat pulse = 0.65 + 0.35 * sin(now * 3.2);
    CGFloat cx = W / 2;

    if (_paused) {
        [self card:NSMakeRect(70, 322, 460, 160) alpha:1];
        Label(@"Paused", Display(44), C(kFoam), cx, 384, 0);
        Label(@"Click the window to keep playing", Body(16), C(kFoam, 0.7), cx, 436, 0);
        return;
    }

    if (ph == Phase::Title) {
        [self card:NSMakeRect(50, 226, 500, 372) alpha:1];
        [NSGraphicsContext saveGraphicsState];
        GlowOn(kWater, 0.55, 26);
        Label(@"Spelltide", Display(62), C(kFoam), cx, 296, 0);
        [NSGraphicsContext restoreGraphicsState];
        Label(@"Letters flood the tank. Spell words to drain it.", Body(18), C(kFoam, 0.92), cx, 356, 0);

        NSArray<NSString*>* rules = @[
            @"Type letters to pick tiles, then press Enter.",
            @"Longer words score more: 2 letters is 40, 6 letters is 360.",
            @"If the tank stays full for 5 seconds, the game ends.",
        ];
        for (NSUInteger k = 0; k < rules.count; ++k) Label(rules[k], Body(15), C(kFoam, 0.62), cx, 412 + k * 28, 0);

        if (_game.wordCount() == 0) Label(@"Word list is missing. Run build.sh again.", BodyBold(16), C(kCoral), cx, 546, 0);
        else Label(@"Press space to start", BodyBold(18), C(kAmberLo, pulse), cx, 546, 0);
        return;
    }

    // game over
    CGFloat fade = std::min(1.0, (now - _overAt) / 0.5);
    [self card:NSMakeRect(50, 216, 500, 384) alpha:fade];
    Label(@"Flooded", Display(44), C(kCoral, fade), cx, 276, 0);
    Label(Num(_game.score), Display(92), C(kFoam, fade), cx, 368, 0);
    if (_game.newBest) Label(@"New best", BodyBold(18), C(kAmberLo, fade), cx, 444, 0);
    else Label([NSString stringWithFormat:@"Best %@", Num(_game.best)], Body(16), C(kFoam, 0.7 * fade), cx, 444, 0);

    NSString* stats = _game.words == 1 ? @"1 word" : [NSString stringWithFormat:@"%d words", _game.words];
    if (!_game.longest.empty()) stats = [stats stringByAppendingFormat:@". Longest: %s", _game.longest.c_str()];
    Label(stats, Body(15), C(kFoam, 0.62 * fade), cx, 478, 0);
    if (now - _overAt > 0.8) Label(@"Press space to play again", BodyBold(18), C(kAmberLo, pulse), cx, 548, 0);
}

// ------------------------------------------------------------ test scenes
// Puts the game in a known state so a picture of it can be saved without playing.

- (void)stage:(const char*)scene {
    _headless = YES;
    auto run = [&](double secs) { for (double t = 0; t < secs; t += 1.0 / 60) [self advance:1.0 / 60]; };
    auto put = [&](int cell, char ch) {
        _game.grid[cell] = Tile{};
        _game.grid[cell].ch = ch;
        _game.grid[cell].born = _game.clock - 2;
    };
    std::string s = scene;
    if (s == "title") { run(4); return; }

    _game.best = 1890;
    _game.start();
    run(21);
    if (s == "play") {
        const int a[] = {50, 43, 36, 29};
        for (int k = 0; k < 4; ++k) { put(a[k], "tide"[k]); _game.clickCell(a[k]); }
        _game.submit();
        run(0.2);
        const int b[] = {17, 18, 19, 20, 21};
        for (int k = 0; k < 5; ++k) { put(b[k], "spell"[k]); _game.clickCell(b[k]); }
        run(0.5);
        return;
    }
    _game.score = 2480; _game.words = 19; _game.longest = "quartz";
    _game.elapsed = 400;
    while (!_game.full()) run(0.1);
    if (s == "danger") {
        const int b[] = {10, 11, 12};
        for (int k = 0; k < 3; ++k) { put(b[k], "ebb"[k]); _game.clickCell(b[k]); }
        while (_game.fullFor < 2.8) run(1.0 / 60);
    } else {
        while (_game.phase != Phase::Over) run(1.0 / 60);
        run(1.5);
    }
}

@end

// ---------------------------------------------------------------- the app

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate {
    NSWindow* _window;
    GameView* _view;
}

- (void)applicationDidFinishLaunching:(__unused NSNotification*)note {
    NSMenu* bar = [NSMenu new];
    NSMenuItem* item = [NSMenuItem new];
    [bar addItem:item];
    NSMenu* menu = [NSMenu new];
    [menu addItemWithTitle:@"New Game" action:@selector(newGame:) keyEquivalent:@"n"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit Spelltide" action:@selector(terminate:) keyEquivalent:@"q"];
    item.submenu = menu;
    NSApp.mainMenu = bar;

    NSRect screen = NSScreen.mainScreen.visibleFrame;
    CGFloat h = std::min<CGFloat>(H, screen.size.height - 60), w = h * W / H;
    NSRect r = NSMakeRect(0, 0, w, h);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    _window = [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"Spelltide";
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _window.backgroundColor = C(kAbyssBot);
    _window.contentAspectRatio = NSMakeSize(W, H);
    _window.contentMinSize = NSMakeSize(W * 0.6, H * 0.6);

    _view = [[GameView alloc] initWithFrame:r];
    _window.contentView = _view;
    [_window center];
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_view];
    [_view startClock];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(__unused NSApplication*)app { return YES; }

@end

// Spelltide --snapshot out.png [title|play|danger|over] saves a picture and quits.
static int Snapshot(const char* path, const char* scene) {
    GameView* v = [[GameView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    [v stage:scene];

    const int scale = 2, pw = int(W) * scale, ph = int(H) * scale;
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:pw pixelsHigh:ph bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep].CGContext;
    CGContextTranslateCTM(cg, 0, ph);
    CGContextScaleCTM(cg, scale, -scale);
    gGlow = gPixels = scale;

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];
    const int frames = 40;
    double t0 = CACurrentMediaTime();
    for (int k = 0; k < frames; ++k) {
        [v drawBackdropIn:NSMakeRect(0, 0, W, H)];
        [v renderScene];
    }
    double ms = (CACurrentMediaTime() - t0) * 1000 / frames;
    [NSGraphicsContext restoreGraphicsState];

    NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    BOOL ok = [png writeToFile:@(path) atomically:YES];
    printf("%s: %s, %.1f ms per frame\n", scene, ok ? "saved" : "could not save", ms);
    return ok ? 0 : 1;
}

// Spelltide --icon out.png paints the 1024 x 1024 app icon: one amber tile riding the tide.
static int Icon(const char* path) {
    const int px = 1024;
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:px pixelsHigh:px bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep].CGContext;
    CGContextTranslateCTM(cg, 0, px);
    CGContextScaleCTM(cg, 1, -1);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];

    const NSRect plate = NSMakeRect(100, 100, 824, 824);  // the size Apple asks for inside a 1024 square
    NSBezierPath* shape = RR(plate, 185);

    [NSGraphicsContext saveGraphicsState];
    NSShadow* drop = [NSShadow new];
    drop.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
    drop.shadowBlurRadius = 22;
    drop.shadowOffset = NSMakeSize(0, -12);
    [drop set];
    [C(kAbyssBot) setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];

    [NSGraphicsContext saveGraphicsState];
    [shape addClip];

    // deep water, lit from above
    [[[NSGradient alloc] initWithStartingColor:C(Mix(kAbyssTop, kWater, 0.22)) endingColor:C(kAbyssBot)]
        drawInRect:plate angle:90];
    NSGradient* light = [[NSGradient alloc] initWithStartingColor:C(kWater, 0.5) endingColor:C(kWater, 0)];
    [light drawFromCenter:NSMakePoint(700, 40) radius:0 toCenter:NSMakePoint(700, 40) radius:640 options:0];

    auto wave = [](CGFloat level, CGFloat ph, CGFloat floorY) {
        NSBezierPath* p = [NSBezierPath bezierPath];
        for (CGFloat x = 96; x <= 930; x += 6) {
            NSPoint pt = NSMakePoint(x, level + 17 * sin(x * 0.0135 + ph) + 7 * sin(x * 0.031 + ph * 2));
            if (x == 96) [p moveToPoint:pt]; else [p lineToPoint:pt];
        }
        if (!isnan(floorY)) {
            [p lineToPoint:NSMakePoint(930, floorY)];
            [p lineToPoint:NSMakePoint(96, floorY)];
            [p closePath];
        }
        return p;
    };
    const CGFloat level = 600;
    [C(kWaterDeep, 0.9) setFill];
    [wave(level - 26, 2.1, 930) fill];
    NSBezierPath* body = wave(level, 0, 930);
    [[[NSGradient alloc] initWithStartingColor:C(kWater) endingColor:C(kWaterDeep)] drawInBezierPath:body angle:90];

    // the tile
    const CGFloat size = 440;
    gGlow = size / kTile * 0.8;
    CGContextSaveGState(cg);
    CGContextTranslateCTM(cg, 512, 480);
    CGContextRotateCTM(cg, -8 * M_PI / 180);
    DrawTileFace(size, 's', true, 0, 1);
    CGContextRestoreGState(cg);

    // water in front, so the tile sits in it
    [C(kWater, 0.34) setFill];
    [body fill];
    NSBezierPath* line = wave(level, 0, NAN);
    line.lineWidth = 7;
    line.lineJoinStyle = NSLineJoinStyleRound;
    [C(kFoam, 0.9) setStroke];
    [line stroke];

    const CGFloat bubbles[][3] = {{214, 706, 15}, {262, 772, 9}, {792, 742, 18}, {738, 812, 10}, {560, 836, 12}, {348, 840, 7}};
    for (const auto& b : bubbles) {
        NSBezierPath* o = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(b[0] - b[2], b[1] - b[2], 2 * b[2], 2 * b[2])];
        o.lineWidth = 4;
        [C(kFoam, 0.14) setFill];
        [o fill];
        [C(kFoam, 0.6) setStroke];
        [o stroke];
    }
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath* rim = RR(NSInsetRect(plate, 2, 2), 183);
    rim.lineWidth = 4;
    [C(kWhite, 0.16) setStroke];
    [rim stroke];
    [NSGraphicsContext restoreGraphicsState];

    NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    BOOL ok = [png writeToFile:@(path) atomically:YES];
    printf("icon: %s\n", ok ? "saved" : "could not save");
    return ok ? 0 : 1;
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        if (argc >= 3 && strcmp(argv[1], "--snapshot") == 0) return Snapshot(argv[2], argc >= 4 ? argv[3] : "play");
        if (argc >= 3 && strcmp(argv[1], "--icon") == 0) return Icon(argv[2]);
        AppDelegate* delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
