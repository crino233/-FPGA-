import argparse
import binascii
import struct
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def build(output, font_path):
    font = ImageFont.truetype(str(font_path), 16)
    characters = set(chr(value) for value in range(32, 127))
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                characters.add(bytes((high, low)).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    characters.update("浩弟帅就一个字，跟我辈子")
    header = bytearray(510)
    header[:8] = b"F16U\x02\x10\x10\x40"
    struct.pack_into(">H", header, 8, len(characters))
    ordered = sorted(characters)
    glyph_ids = {ord(character): index for index, character in enumerate(ordered)}
    index_records = []
    for code in range(65536):
        pair = struct.pack(">HH", code, glyph_ids.get(code, 0xFFFF))
        index_records.append(pair[2:] + struct.pack(">H", binascii.crc_hqx(pair, 0xFFFF)))
    records = [bytes(header) + struct.pack(">H", binascii.crc_hqx(header, 0xFFFF))]
    for character in ordered:
        image = Image.new("1", (16, 16))
        ImageDraw.Draw(image).text((0, 0), character, font=font, fill=1)
        record = bytearray(62)
        struct.pack_into(">H", record, 0, ord(character))
        for row in range(16):
            value = sum(int(image.getpixel((col, row))) << (15-col) for col in range(16))
            struct.pack_into(">H", record, 2+row*2, value)
        records.append(bytes(record) + struct.pack(">H", binascii.crc_hqx(record, 0xFFFF)))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(records[0] + b"".join(index_records) + b"".join(records[1:]))
    assert all(binascii.crc_hqx(record, 0xFFFF) == 0 for record in records)
    assert all(binascii.crc_hqx(struct.pack(">H", code) + record, 0xFFFF) == 0
               for code, record in enumerate(index_records))
    prepare_fixtures(output)
    print(f"{len(characters)} glyphs, {output.stat().st_size} bytes: {output}")


def prepare_fixtures(output):
    
    root = Path(__file__).resolve().parents[1]
    data = output.read_bytes()
    count = struct.unpack_from(">H", data, 8)[0]
    assert data[:8] == b"F16U\x02\x10\x10\x40" and len(data) == 262656 + count * 64
    codes = [struct.unpack_from(">H", data, 262656 + index * 64)[0] for index in range(count)]
    initial_rows = [int(value, 16) for value in (root / "src/app/photo_subtitle_font.dath").read_text().split()]
    cold_codes = [code for code in codes if code >= 0x4E00 and code not in initial_rows[1280:1360]][:416]
    assert len(cold_codes) == 416
    (root / "sim/work").mkdir(exist_ok=True)
    (root / "sim/work/font_codes.hex").write_text("\n".join(f"{code:04x}" for code in cold_codes) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1]/"sim/tf_card/FONT16.BIN")
    parser.add_argument("--font", type=Path, default=Path("C:/Windows/Fonts/simsun.ttc"))
    parser.add_argument("--fixtures-only", action="store_true", help="Read an existing font and prepare simulation inputs")
    args = parser.parse_args()
    if args.fixtures_only:
        prepare_fixtures(args.output)
    else:
        build(args.output, args.font)
