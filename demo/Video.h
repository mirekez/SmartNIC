#pragma once

// Minimal indexed-color canvas and Microsoft RLE8 AVI writer. The demo uses
// no GUI or codec dependency: every completed 500x300 visualization is encoded
// immediately and the AVI headers/index are finalized when the test ends.

#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include <zlib.h>

namespace smartnic_demo
{

struct Rect
{
    int x;
    int y;
    int width;
    int height;
};

class Canvas
{
public:
    static constexpr int WIDTH = 500;
    static constexpr int HEIGHT = 300;

    struct Rgb
    {
        uint8_t red;
        uint8_t green;
        uint8_t blue;
    };

    // The upper palette entries are reserved for exact UI colors. Packet and
    // firmware pixels use the remaining RGB332 palette.
    static constexpr uint8_t UI_CHIP_BOTTOM = 248;
    static constexpr uint8_t UI_CHIP_MIDDLE = 249;
    static constexpr uint8_t UI_ACTIVE = 250;
    static constexpr uint8_t UI_TEXT = 251;
    static constexpr uint8_t UI_GRID = 252;
    static constexpr uint8_t UI_BORDER = 253;
    static constexpr uint8_t UI_PANEL = 254;
    static constexpr uint8_t UI_OUTSIDE = 255;

    std::array<uint8_t, WIDTH * HEIGHT> pixels{};

    static constexpr uint8_t rgb332(uint8_t red, uint8_t green, uint8_t blue)
    {
        const uint8_t color = (uint8_t)((red & 0xe0u)
            | ((green >> 3) & 0x1cu) | (blue >> 6));
        return color < UI_CHIP_BOTTOM ? color : UI_CHIP_BOTTOM - 1;
    }

    static constexpr Rgb palette(uint8_t index)
    {
        switch (index) {
        case UI_CHIP_BOTTOM: return {58, 62, 66};
        case UI_CHIP_MIDDLE: return {92, 96, 100};
        case UI_ACTIVE: return {255, 214, 32};
        case UI_TEXT: return {24, 24, 24};
        case UI_GRID: return {148, 148, 148};
        case UI_BORDER: return {70, 70, 70};
        case UI_PANEL: return {195, 195, 195};
        case UI_OUTSIDE: return {127, 127, 127};
        default:
            return {(uint8_t)(((index >> 5) & 7u) * 255u / 7u),
                (uint8_t)(((index >> 2) & 7u) * 255u / 7u),
                (uint8_t)((index & 3u) * 255u / 3u)};
        }
    }

    static uint8_t word_color(uint16_t word)
    {
        // 0xDCBA: A/B/C select red/green/blue and D multiplies all channels.
        // A zero multiplier nibble means unity so 0x0005/0x0050/0x0500 are
        // visible base red/green/blue, as used by the demo traffic patterns.
        const uint32_t red = word & 0xfu;
        const uint32_t green = (word >> 4) & 0xfu;
        const uint32_t blue = (word >> 8) & 0xfu;
        const uint32_t gain = ((word >> 12) & 0xfu) + 1u;
        return rgb332((uint8_t)std::min(255u, red * 17u * gain),
            (uint8_t)std::min(255u, green * 17u * gain),
            (uint8_t)std::min(255u, blue * 17u * gain));
    }

    void clear(uint8_t color = rgb332(4, 7, 12))
    {
        pixels.fill(color);
    }

    void pixel(int x, int y, uint8_t color)
    {
        if (x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT) {
            pixels[(size_t)y * WIDTH + x] = color;
        }
    }

    void fill(Rect rect, uint8_t color)
    {
        const int left = std::max(0, rect.x);
        const int top = std::max(0, rect.y);
        const int right = std::min(WIDTH, rect.x + rect.width);
        const int bottom = std::min(HEIGHT, rect.y + rect.height);
        for (int y = top; y < bottom; ++y) {
            std::fill(pixels.begin() + (size_t)y * WIDTH + left,
                pixels.begin() + (size_t)y * WIDTH + right, color);
        }
    }

    void outline(Rect rect, uint8_t color)
    {
        for (int x = rect.x; x < rect.x + rect.width; ++x) {
            pixel(x, rect.y, color);
            pixel(x, rect.y + rect.height - 1, color);
        }
        for (int y = rect.y; y < rect.y + rect.height; ++y) {
            pixel(rect.x, y, color);
            pixel(rect.x + rect.width - 1, y, color);
        }
    }

    void hline(int x, int y, int width, uint8_t color)
    {
        for (int offset = 0; offset < width; ++offset) pixel(x + offset, y, color);
    }

    void vline(int x, int y, int height, uint8_t color)
    {
        for (int offset = 0; offset < height; ++offset) pixel(x, y + offset, color);
    }

    static uint16_t glyph(char character)
    {
#define DEMO_GLYPH(a, b, c, d, e) \
        ((uint16_t)(a) << 12 | (uint16_t)(b) << 9 | (uint16_t)(c) << 6 \
            | (uint16_t)(d) << 3 | (uint16_t)(e))
        switch (character) {
        case 'A': return DEMO_GLYPH(2, 5, 7, 5, 5);
        case 'B': return DEMO_GLYPH(6, 5, 6, 5, 6);
        case 'C': return DEMO_GLYPH(3, 4, 4, 4, 3);
        case 'D': return DEMO_GLYPH(6, 5, 5, 5, 6);
        case 'E': return DEMO_GLYPH(7, 4, 6, 4, 7);
        case 'F': return DEMO_GLYPH(7, 4, 6, 4, 4);
        case 'G': return DEMO_GLYPH(3, 4, 5, 5, 3);
        case 'H': return DEMO_GLYPH(5, 5, 7, 5, 5);
        case 'I': return DEMO_GLYPH(7, 2, 2, 2, 7);
        case 'J': return DEMO_GLYPH(1, 1, 1, 5, 2);
        case 'K': return DEMO_GLYPH(5, 5, 6, 5, 5);
        case 'L': return DEMO_GLYPH(4, 4, 4, 4, 7);
        case 'M': return DEMO_GLYPH(5, 7, 7, 5, 5);
        case 'N': return DEMO_GLYPH(5, 7, 7, 7, 5);
        case 'O': return DEMO_GLYPH(2, 5, 5, 5, 2);
        case 'P': return DEMO_GLYPH(6, 5, 6, 4, 4);
        case 'Q': return DEMO_GLYPH(2, 5, 5, 3, 1);
        case 'R': return DEMO_GLYPH(6, 5, 6, 5, 5);
        case 'S': return DEMO_GLYPH(3, 4, 2, 1, 6);
        case 'T': return DEMO_GLYPH(7, 2, 2, 2, 2);
        case 'U': return DEMO_GLYPH(5, 5, 5, 5, 7);
        case 'V': return DEMO_GLYPH(5, 5, 5, 5, 2);
        case 'W': return DEMO_GLYPH(5, 5, 7, 7, 5);
        case 'X': return DEMO_GLYPH(5, 5, 2, 5, 5);
        case 'Y': return DEMO_GLYPH(5, 5, 2, 2, 2);
        case 'Z': return DEMO_GLYPH(7, 1, 2, 4, 7);
        case '0': return DEMO_GLYPH(7, 5, 5, 5, 7);
        case '1': return DEMO_GLYPH(2, 6, 2, 2, 7);
        case '2': return DEMO_GLYPH(6, 1, 7, 4, 7);
        case '3': return DEMO_GLYPH(6, 1, 3, 1, 6);
        case '4': return DEMO_GLYPH(5, 5, 7, 1, 1);
        case '5': return DEMO_GLYPH(7, 4, 6, 1, 6);
        case '6': return DEMO_GLYPH(3, 4, 7, 5, 7);
        case '7': return DEMO_GLYPH(7, 1, 2, 2, 2);
        case '8': return DEMO_GLYPH(7, 5, 7, 5, 7);
        case '9': return DEMO_GLYPH(7, 5, 7, 1, 6);
        case '$': return DEMO_GLYPH(3, 6, 3, 6, 3);
        case ':': return DEMO_GLYPH(0, 2, 0, 2, 0);
        case '-': return DEMO_GLYPH(0, 0, 7, 0, 0);
        case '/': return DEMO_GLYPH(1, 1, 2, 4, 4);
        default: return 0;
        }
#undef DEMO_GLYPH
    }

    void text(int x, int y, std::string_view value, uint8_t color)
    {
        for (char character : value) {
            const uint16_t bitmap = glyph(character);
            for (int row = 0; row < 5; ++row) {
                const uint8_t bits = (bitmap >> ((4 - row) * 3)) & 7u;
                for (int column = 0; column < 3; ++column) {
                    if (bits & (4u >> column)) pixel(x + column, y + row, color);
                }
            }
            x += 4;
        }
    }

    void write_ppm(const std::filesystem::path& path) const
    {
        std::ofstream output(path, std::ios::binary);
        if (!output) throw std::runtime_error("cannot write preview " + path.string());
        output << "P6\n" << WIDTH << ' ' << HEIGHT << "\n255\n";
        for (uint8_t index : pixels) {
            const Rgb color = palette(index);
            output.put((char)color.red);
            output.put((char)color.green);
            output.put((char)color.blue);
        }
    }

    void write_bmp(const std::filesystem::path& path) const
    {
        std::ofstream output(path, std::ios::binary);
        if (!output) throw std::runtime_error("cannot write preview " + path.string());
        const auto put16 = [&output](uint16_t value) {
            output.put((char)value); output.put((char)(value >> 8));
        };
        const auto put32 = [&output](uint32_t value) {
            for (uint32_t byte = 0; byte < 4; ++byte) {
                output.put((char)(value >> (byte * 8)));
            }
        };
        const uint32_t image_bytes = WIDTH * HEIGHT * 3;
        output.put('B'); output.put('M'); put32(54 + image_bytes);
        put32(0); put32(54); put32(40); put32(WIDTH); put32(HEIGHT);
        put16(1); put16(24); put32(0); put32(image_bytes);
        put32(0); put32(0); put32(0); put32(0);
        for (int y = HEIGHT - 1; y >= 0; --y) {
            for (int x = 0; x < WIDTH; ++x) {
                const uint8_t index = pixels[(size_t)y * WIDTH + x];
                const Rgb color = palette(index);
                output.put((char)color.blue);
                output.put((char)color.green);
                output.put((char)color.red);
            }
        }
    }

    void write_png(const std::filesystem::path& path) const
    {
        std::ofstream output(path, std::ios::binary);
        if (!output) throw std::runtime_error("cannot write preview " + path.string());
        const auto crc32 = [](const uint8_t* data, size_t size) {
            uint32_t crc = 0xffffffffu;
            for (size_t index = 0; index < size; ++index) {
                crc ^= data[index];
                for (uint32_t bit = 0; bit < 8; ++bit) {
                    crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
                }
            }
            return crc ^ 0xffffffffu;
        };
        const auto be32 = [&output](uint32_t value) {
            output.put((char)(value >> 24)); output.put((char)(value >> 16));
            output.put((char)(value >> 8)); output.put((char)value);
        };
        const auto chunk = [&output, &be32, &crc32](const char type[4],
            const std::vector<uint8_t>& data) {
            be32((uint32_t)data.size());
            std::vector<uint8_t> checked(4 + data.size());
            std::copy_n((const uint8_t*)type, 4, checked.begin());
            std::copy(data.begin(), data.end(), checked.begin() + 4);
            output.write(type, 4);
            output.write((const char*)data.data(), (std::streamsize)data.size());
            be32(crc32(checked.data(), checked.size()));
        };

        const uint8_t signature[8] = {137, 80, 78, 71, 13, 10, 26, 10};
        output.write((const char*)signature, sizeof(signature));
        std::vector<uint8_t> ihdr = {
            0, 0, (uint8_t)(WIDTH >> 8), (uint8_t)WIDTH,
            0, 0, (uint8_t)(HEIGHT >> 8), (uint8_t)HEIGHT,
            8, 2, 0, 0, 0};
        chunk("IHDR", ihdr);

        std::vector<uint8_t> raw;
        raw.reserve((WIDTH * 3 + 1) * HEIGHT);
        for (int y = 0; y < HEIGHT; ++y) {
            raw.push_back(0); // PNG filter: None
            for (int x = 0; x < WIDTH; ++x) {
                const uint8_t index = pixels[(size_t)y * WIDTH + x];
                const Rgb color = palette(index);
                raw.push_back(color.red);
                raw.push_back(color.green);
                raw.push_back(color.blue);
            }
        }
        std::vector<uint8_t> zlib = {0x78, 0x01};
        size_t offset = 0;
        while (offset < raw.size()) {
            const uint16_t length = (uint16_t)std::min<size_t>(65535,
                raw.size() - offset);
            zlib.push_back(offset + length == raw.size() ? 1 : 0);
            zlib.push_back((uint8_t)length);
            zlib.push_back((uint8_t)(length >> 8));
            const uint16_t inverse = (uint16_t)~length;
            zlib.push_back((uint8_t)inverse);
            zlib.push_back((uint8_t)(inverse >> 8));
            zlib.insert(zlib.end(), raw.begin() + offset,
                raw.begin() + offset + length);
            offset += length;
        }
        uint32_t s1 = 1;
        uint32_t s2 = 0;
        for (uint8_t byte : raw) {
            s1 = (s1 + byte) % 65521u;
            s2 = (s2 + s1) % 65521u;
        }
        const uint32_t adler = s2 << 16 | s1;
        zlib.push_back((uint8_t)(adler >> 24));
        zlib.push_back((uint8_t)(adler >> 16));
        zlib.push_back((uint8_t)(adler >> 8));
        zlib.push_back((uint8_t)adler);
        chunk("IDAT", zlib);
        chunk("IEND", {});
    }
};

// APNG is used for the compositing-friendly copy because AVI/RLE8 has no
// portable alpha semantics. Palette entry zero is the untouched canvas
// background and is transparent; every other RGB332 entry remains opaque.
class ApngWriter
{
    std::fstream output;
    uint32_t fps;
    uint32_t frames = 0;
    uint32_t sequence = 0;
    std::streampos animation_data_position{};
    std::streampos animation_crc_position{};
    bool finished = false;

    static uint32_t crc(const char type[4], const uint8_t* data, size_t size)
    {
        uLong value = crc32(0L, Z_NULL, 0);
        value = crc32(value, (const Bytef*)type, 4);
        value = crc32(value, data, (uInt)size);
        return (uint32_t)value;
    }

    void be16(uint16_t value)
    {
        output.put((char)(value >> 8));
        output.put((char)value);
    }

    void be32(uint32_t value)
    {
        output.put((char)(value >> 24));
        output.put((char)(value >> 16));
        output.put((char)(value >> 8));
        output.put((char)value);
    }

    static void append32(std::vector<uint8_t>& bytes, uint32_t value)
    {
        bytes.push_back((uint8_t)(value >> 24));
        bytes.push_back((uint8_t)(value >> 16));
        bytes.push_back((uint8_t)(value >> 8));
        bytes.push_back((uint8_t)value);
    }

    void chunk(const char type[4], const uint8_t* data, size_t size)
    {
        be32((uint32_t)size);
        output.write(type, 4);
        if (size != 0) {
            output.write((const char*)data, (std::streamsize)size);
        }
        be32(crc(type, data, size));
    }

    void chunk(const char type[4], const std::vector<uint8_t>& data)
    {
        chunk(type, data.data(), data.size());
    }

    static std::vector<uint8_t> compress(const Canvas& canvas)
    {
        std::vector<uint8_t> raw;
        raw.reserve((Canvas::WIDTH + 1) * Canvas::HEIGHT);
        for (int y = 0; y < Canvas::HEIGHT; ++y) {
            raw.push_back(0); // PNG filter: None
            const auto row = canvas.pixels.begin() + (size_t)y * Canvas::WIDTH;
            raw.insert(raw.end(), row, row + Canvas::WIDTH);
        }
        uLongf compressed_size = compressBound((uLong)raw.size());
        std::vector<uint8_t> compressed(compressed_size);
        const int result = compress2(compressed.data(), &compressed_size,
            raw.data(), (uLong)raw.size(), Z_BEST_SPEED);
        if (result != Z_OK) throw std::runtime_error("APNG compression failed");
        compressed.resize(compressed_size);
        return compressed;
    }

public:
    ApngWriter(const std::filesystem::path& path, uint32_t frame_rate,
        uint8_t transparent_index)
        : fps(frame_rate)
    {
        std::filesystem::create_directories(path.parent_path());
        output.open(path, std::ios::binary | std::ios::in | std::ios::out
            | std::ios::trunc);
        if (!output) throw std::runtime_error("cannot create animation "
            + path.string());

        static constexpr uint8_t signature[8] =
            {137, 80, 78, 71, 13, 10, 26, 10};
        output.write((const char*)signature, sizeof(signature));

        std::vector<uint8_t> ihdr;
        append32(ihdr, Canvas::WIDTH);
        append32(ihdr, Canvas::HEIGHT);
        ihdr.insert(ihdr.end(), {8, 3, 0, 0, 0}); // indexed RGB, 8 bits
        chunk("IHDR", ihdr);

        std::vector<uint8_t> palette;
        palette.reserve(256 * 3);
        for (uint32_t color = 0; color < 256; ++color) {
            const Canvas::Rgb rgb = Canvas::palette((uint8_t)color);
            palette.push_back(rgb.red);
            palette.push_back(rgb.green);
            palette.push_back(rgb.blue);
        }
        chunk("PLTE", palette);
        std::vector<uint8_t> alpha((size_t)transparent_index + 1, 255);
        alpha[transparent_index] = 0;
        chunk("tRNS", alpha);

        be32(8); output.write("acTL", 4);
        animation_data_position = output.tellp();
        be32(0); // patched with the final frame count
        be32(0); // loop forever
        animation_crc_position = output.tellp();
        be32(0);
    }

    ~ApngWriter()
    {
        try { finish(); } catch (...) {}
    }

    void write(const Canvas& canvas)
    {
        std::vector<uint8_t> control;
        append32(control, sequence++);
        append32(control, Canvas::WIDTH);
        append32(control, Canvas::HEIGHT);
        append32(control, 0);
        append32(control, 0);
        control.push_back(0);
        control.push_back(1);
        control.push_back((uint8_t)(fps >> 8));
        control.push_back((uint8_t)fps);
        control.push_back(0); // APNG_DISPOSE_OP_NONE
        control.push_back(0); // APNG_BLEND_OP_SOURCE
        chunk("fcTL", control);

        std::vector<uint8_t> compressed = compress(canvas);
        if (frames == 0) {
            chunk("IDAT", compressed);
        }
        else {
            std::vector<uint8_t> frame;
            frame.reserve(compressed.size() + 4);
            append32(frame, sequence++);
            frame.insert(frame.end(), compressed.begin(), compressed.end());
            chunk("fdAT", frame);
        }
        ++frames;
    }

    void finish()
    {
        if (finished || !output) return;
        chunk("IEND", nullptr, 0);
        const std::streampos end = output.tellp();

        std::array<uint8_t, 8> animation{};
        animation[0] = (uint8_t)(frames >> 24);
        animation[1] = (uint8_t)(frames >> 16);
        animation[2] = (uint8_t)(frames >> 8);
        animation[3] = (uint8_t)frames;
        output.seekp(animation_data_position);
        output.write((const char*)animation.data(), animation.size());
        output.seekp(animation_crc_position);
        be32(crc("acTL", animation.data(), animation.size()));
        output.seekp(end);
        output.flush();
        output.close();
        finished = true;
    }

    uint32_t frame_count() const { return frames; }
};

class RleAviWriter
{
    struct IndexEntry
    {
        uint32_t offset;
        uint32_t size;
    };

    std::fstream output;
    uint32_t fps;
    uint32_t frames = 0;
    uint32_t largest_frame = 0;
    std::streampos riff_size_position{};
    std::streampos total_frames_position{};
    std::streampos stream_length_position{};
    std::streampos suggested_buffer_position{};
    std::streampos stream_buffer_position{};
    std::streampos movi_size_position{};
    std::streampos movi_fourcc_position{};
    std::vector<IndexEntry> index;
    bool finished = false;

    static constexpr uint32_t fourcc(char a, char b, char c, char d)
    {
        return (uint32_t)(uint8_t)a | (uint32_t)(uint8_t)b << 8
            | (uint32_t)(uint8_t)c << 16 | (uint32_t)(uint8_t)d << 24;
    }

    void u16(uint16_t value)
    {
        output.put((char)(value & 0xff));
        output.put((char)(value >> 8));
    }

    void u32(uint32_t value)
    {
        for (uint32_t byte = 0; byte < 4; ++byte) {
            output.put((char)(value >> (byte * 8)));
        }
    }

    void patch32(std::streampos position, uint32_t value)
    {
        const std::streampos current = output.tellp();
        output.seekp(position);
        u32(value);
        output.seekp(current);
    }

    static void literal(std::vector<uint8_t>& encoded,
        const uint8_t* values, size_t count)
    {
        if (count <= 2) {
            for (size_t index = 0; index < count; ++index) {
                encoded.push_back(1);
                encoded.push_back(values[index]);
            }
            return;
        }
        encoded.push_back(0);
        encoded.push_back((uint8_t)count);
        encoded.insert(encoded.end(), values, values + count);
        if (count & 1u) encoded.push_back(0);
    }

    static std::vector<uint8_t> encode(const Canvas& canvas)
    {
        std::vector<uint8_t> encoded;
        encoded.reserve(Canvas::WIDTH * Canvas::HEIGHT / 3);
        // Positive-height DIB scanlines are bottom-up.
        for (int y = Canvas::HEIGHT - 1; y >= 0; --y) {
            const uint8_t* row = canvas.pixels.data() + (size_t)y * Canvas::WIDTH;
            size_t x = 0;
            while (x < Canvas::WIDTH) {
                size_t run = 1;
                while (x + run < Canvas::WIDTH && run < 255
                    && row[x + run] == row[x]) ++run;
                if (run >= 3) {
                    encoded.push_back((uint8_t)run);
                    encoded.push_back(row[x]);
                    x += run;
                    continue;
                }
                const size_t start = x;
                x += run;
                while (x < Canvas::WIDTH && x - start < 255) {
                    size_t next_run = 1;
                    while (x + next_run < Canvas::WIDTH && next_run < 255
                        && row[x + next_run] == row[x]) ++next_run;
                    if (next_run >= 3) break;
                    if (x - start + next_run > 255) break;
                    x += next_run;
                }
                literal(encoded, row + start, x - start);
            }
            encoded.push_back(0);
            encoded.push_back(0); // end of line
        }
        encoded.push_back(0);
        encoded.push_back(1); // end of bitmap
        return encoded;
    }

public:
    RleAviWriter(const std::filesystem::path& path, uint32_t frame_rate)
        : fps(frame_rate)
    {
        std::filesystem::create_directories(path.parent_path());
        output.open(path, std::ios::binary | std::ios::in | std::ios::out
            | std::ios::trunc);
        if (!output) throw std::runtime_error("cannot create video " + path.string());

        u32(fourcc('R', 'I', 'F', 'F'));
        riff_size_position = output.tellp(); u32(0);
        u32(fourcc('A', 'V', 'I', ' '));

        u32(fourcc('L', 'I', 'S', 'T'));
        const std::streampos hdrl_size_position = output.tellp(); u32(0);
        const std::streampos hdrl_start = output.tellp();
        u32(fourcc('h', 'd', 'r', 'l'));

        u32(fourcc('a', 'v', 'i', 'h')); u32(56);
        u32(1000000u / fps);
        u32(Canvas::WIDTH * Canvas::HEIGHT * fps);
        u32(0); u32(0x10);
        total_frames_position = output.tellp(); u32(0);
        u32(0); u32(1);
        suggested_buffer_position = output.tellp(); u32(0);
        u32(Canvas::WIDTH); u32(Canvas::HEIGHT);
        for (int reserved = 0; reserved < 4; ++reserved) u32(0);

        u32(fourcc('L', 'I', 'S', 'T'));
        const std::streampos strl_size_position = output.tellp(); u32(0);
        const std::streampos strl_start = output.tellp();
        u32(fourcc('s', 't', 'r', 'l'));
        u32(fourcc('s', 't', 'r', 'h')); u32(56);
        u32(fourcc('v', 'i', 'd', 's')); u32(fourcc('m', 'r', 'l', 'e'));
        u32(0); u16(0); u16(0); u32(0); u32(1); u32(fps); u32(0);
        stream_length_position = output.tellp(); u32(0);
        stream_buffer_position = output.tellp(); u32(0);
        u32(0xffffffffu); u32(0);
        u16(0); u16(0); u16(Canvas::WIDTH); u16(Canvas::HEIGHT);

        u32(fourcc('s', 't', 'r', 'f')); u32(40 + 256 * 4);
        u32(40); u32(Canvas::WIDTH); u32(Canvas::HEIGHT);
        u16(1); u16(8); u32(1); // BI_RLE8
        u32(Canvas::WIDTH * Canvas::HEIGHT);
        u32(0); u32(0); u32(256); u32(256);
        for (uint32_t color = 0; color < 256; ++color) {
            const Canvas::Rgb rgb = Canvas::palette((uint8_t)color);
            output.put((char)rgb.blue);
            output.put((char)rgb.green);
            output.put((char)rgb.red);
            output.put(0);
        }
        const std::streampos after_strl = output.tellp();
        patch32(strl_size_position, (uint32_t)(after_strl - strl_start));
        patch32(hdrl_size_position, (uint32_t)(after_strl - hdrl_start));

        u32(fourcc('L', 'I', 'S', 'T'));
        movi_size_position = output.tellp(); u32(0);
        movi_fourcc_position = output.tellp();
        u32(fourcc('m', 'o', 'v', 'i'));
    }

    ~RleAviWriter()
    {
        try { finish(); } catch (...) {}
    }

    void write(const Canvas& canvas)
    {
        const std::vector<uint8_t> data = encode(canvas);
        const std::streampos chunk_position = output.tellp();
        u32(fourcc('0', '0', 'd', 'c'));
        u32((uint32_t)data.size());
        output.write((const char*)data.data(), (std::streamsize)data.size());
        if (data.size() & 1u) output.put(0);
        index.push_back({(uint32_t)(chunk_position - movi_fourcc_position),
            (uint32_t)data.size()});
        largest_frame = std::max(largest_frame, (uint32_t)data.size());
        ++frames;
    }

    void finish()
    {
        if (finished || !output) return;
        const std::streampos after_movi = output.tellp();
        patch32(movi_size_position,
            (uint32_t)(after_movi - movi_fourcc_position));
        u32(fourcc('i', 'd', 'x', '1'));
        u32((uint32_t)index.size() * 16u);
        for (const IndexEntry& entry : index) {
            u32(fourcc('0', '0', 'd', 'c'));
            u32(0x10); // independently decodable key frame
            u32(entry.offset);
            u32(entry.size);
        }
        const std::streampos end = output.tellp();
        if ((uint64_t)end > 0xffffffffull) {
            throw std::runtime_error("AVI exceeded the 4 GiB RIFF limit");
        }
        patch32(total_frames_position, frames);
        patch32(stream_length_position, frames);
        patch32(suggested_buffer_position, largest_frame);
        patch32(stream_buffer_position, largest_frame);
        patch32(riff_size_position, (uint32_t)end - 8u);
        output.flush();
        output.close();
        finished = true;
    }

    uint32_t frame_count() const { return frames; }
};

} // namespace smartnic_demo
