// Spelltide game rules. Plain C++ only: no Apple code in this file.
#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <random>
#include <string>
#include <unordered_set>
#include <vector>

namespace tide {

constexpr int kSide = 8;
constexpr int kCells = kSide * kSide;
constexpr int kMinWord = 2;
constexpr double kFullLimit = 5.0;      // seconds the board may sit full
constexpr double kLevelSeconds = 15.0;  // play time between speed-ups
constexpr int kStartTiles = 14;

enum class Phase { Title, Playing, Over };

struct Tile {
    char ch = 0;               // 0 = empty cell
    double born = 0;           // clock time it appears (can be slightly ahead)
    int order = -1;            // place in the word being spelled, or -1
    double rejectedAt = -100;  // clock time of the last failed word using it
};

// Things that just happened, for the screen to react to.
struct Event {
    enum Kind { Spawn, Pick, Unpick, Miss, Clear, Scored, Reject, LevelUp, GameOver } kind;
    int cell = -1;
    char ch = 0;
    int value = 0;
};

class Game {
public:
    std::array<Tile, kCells> grid{};
    std::vector<int> picked;     // cells of the word being spelled, in order
    std::vector<Event> events;   // drained by the screen every frame
    Phase phase = Phase::Title;
    double clock = 0;            // always runs
    double elapsed = 0;          // play time this round
    double fullFor = 0;          // how long the board has been full
    int score = 0, best = 0, level = 1, words = 0;
    bool newBest = false;
    std::string longest;

    explicit Game(unsigned seed = std::random_device{}()) : rng_(seed) {}

    bool loadWords(const std::string& path) {
        std::ifstream in(path);
        std::string line;
        while (std::getline(in, line)) {
            while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
            if (line.size() < kMinWord) continue;
            bool ok = std::all_of(line.begin(), line.end(), [](char c) { return c >= 'a' && c <= 'z'; });
            if (ok) dict_.insert(line);
        }
        return !dict_.empty();
    }

    size_t wordCount() const { return dict_.size(); }

    int count() const {
        int n = 0;
        for (const Tile& t : grid) n += t.ch != 0;
        return n;
    }
    double fill() const { return double(count()) / kCells; }
    bool full() const { return count() == kCells; }

    // Seconds between new letters. Shrinks every level.
    double spawnInterval() const { return std::max(0.24, 1.25 * std::pow(0.88, level - 1)); }

    // Longer words are worth much more: 2 letters = 40, 5 = 250, 8 = 640.
    static int pointsFor(size_t letters) { return int(10 * letters * letters); }

    std::string word() const {
        std::string w;
        for (int c : picked) w += grid[c].ch;
        return w;
    }
    bool isWord(const std::string& w) const { return w.size() >= kMinWord && dict_.count(w) > 0; }

    void start() {
        for (Tile& t : grid) t = Tile{};
        picked.clear();
        phase = Phase::Playing;
        elapsed = fullFor = 0;
        score = words = 0;
        level = 1;
        newBest = false;
        longest.clear();
        spawnTimer_ = spawnInterval() + 0.5;
        for (int i = 0; i < kStartTiles; ++i) spawn(i * 0.035);
    }

    void update(double dt) {
        clock += dt;
        if (phase == Phase::Title) { attract(dt); return; }
        if (phase != Phase::Playing) return;

        elapsed += dt;
        int lv = 1 + int(elapsed / kLevelSeconds);
        if (lv > level) { level = lv; events.push_back({Event::LevelUp, -1, 0, level}); }

        if (full()) {
            fullFor += dt;
            if (fullFor >= kFullLimit) finish();
            return;
        }
        fullFor = 0;
        spawnTimer_ -= dt;
        if (spawnTimer_ <= 0) { spawn(); spawnTimer_ += spawnInterval(); }
    }

    // Typing a letter picks the oldest free tile showing it.
    bool typeLetter(char c) {
        if (phase != Phase::Playing) return false;
        int found = -1;
        for (int i = 0; i < kCells; ++i) {
            const Tile& t = grid[i];
            if (t.ch != c || t.order >= 0 || t.born > clock) continue;
            if (found < 0 || t.born < grid[found].born) found = i;
        }
        if (found < 0) { events.push_back({Event::Miss, -1, c}); return false; }
        pick(found);
        return true;
    }

    // Clicking a free tile picks it. Clicking a picked tile takes it (and later ones) back.
    void clickCell(int i) {
        if (phase != Phase::Playing || i < 0 || i >= kCells || !grid[i].ch) return;
        if (grid[i].order < 0) { pick(i); return; }
        size_t keep = size_t(grid[i].order);
        while (picked.size() > keep) unpickLast();
    }

    void backspace() { if (phase == Phase::Playing) unpickLast(); }
    void clearPicked() { while (!picked.empty()) unpickLast(); }

    bool submit() {
        if (phase != Phase::Playing || picked.empty()) return false;
        std::string w = word();
        if (!isWord(w)) {
            for (int c : picked) grid[c].rejectedAt = clock;
            events.push_back({Event::Reject});
            return false;
        }
        int pts = pointsFor(w.size());
        score += pts;
        ++words;
        if (w.size() > longest.size()) longest = w;
        for (int c : picked) {
            events.push_back({Event::Clear, c, grid[c].ch, pts});
            grid[c] = Tile{};
        }
        events.push_back({Event::Scored, picked[picked.size() / 2], 0, pts});
        picked.clear();
        fullFor = 0;
        return true;
    }

private:
    std::unordered_set<std::string> dict_;
    std::mt19937 rng_;
    double spawnTimer_ = 0;

    void pick(int i) {
        grid[i].order = int(picked.size());
        picked.push_back(i);
        events.push_back({Event::Pick, i, grid[i].ch});
    }

    void unpickLast() {
        if (picked.empty()) return;
        int i = picked.back();
        picked.pop_back();
        grid[i].order = -1;
        events.push_back({Event::Unpick, i, grid[i].ch});
    }

    void finish() {
        phase = Phase::Over;
        clearPicked();
        newBest = score > best;
        best = std::max(best, score);
        events.push_back({Event::GameOver, -1, 0, score});
    }

    // Letters drawn roughly like a word-game bag, nudged so the board
    // never runs short of vowels or drowns in them.
    char randomLetter() {
        static const std::string bag =
            "eeeeeeeeeeeeaaaaaaaaaiiiiiiiioooooooonnnnnnrrrrrrttttttllllssssssuuuu"
            "ddddgggbbccmmmppffhhhvwwyykjxqz";
        static const std::string vowels = "eeeeaaaiiioou";
        int total = 0, v = 0;
        for (const Tile& t : grid) {
            if (!t.ch) continue;
            ++total;
            v += std::string("aeiou").find(t.ch) != std::string::npos;
        }
        auto from = [&](const std::string& s) { return s[rng_() % s.size()]; };
        if (total >= 6 && v < total * 0.30) return from(vowels);
        char c = from(bag);
        if (total >= 6 && v > total * 0.50) {
            for (int tries = 0; tries < 8 && std::string("aeiou").find(c) != std::string::npos; ++tries) c = from(bag);
        }
        return c;
    }

    int spawn(double delay = 0) {
        std::vector<int> empty;
        for (int i = 0; i < kCells; ++i) if (!grid[i].ch) empty.push_back(i);
        if (empty.empty()) return -1;
        int i = empty[rng_() % empty.size()];
        grid[i] = Tile{};
        grid[i].ch = randomLetter();
        grid[i].born = clock + delay;
        events.push_back({Event::Spawn, i, grid[i].ch});
        return i;
    }

    // Title screen: the board fills by itself, then drains, forever.
    void attract(double dt) {
        spawnTimer_ -= dt;
        while (spawnTimer_ <= 0) {
            if (full()) {
                for (int i = 0; i < kCells; ++i) {
                    events.push_back({Event::Clear, i, grid[i].ch, 0});
                    grid[i] = Tile{};
                }
                spawnTimer_ += 1.2;
            } else {
                spawn();
                spawnTimer_ += 0.11;
            }
        }
    }
};

}  // namespace tide
