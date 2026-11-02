from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
teacher = ["道阻且长，行则将至；行而不辍，未来可期。", "别太焦虑，一步一个脚印，老班陪你们一起。"]
notice = ["实验楼南侧连廊正封闭施工，请注意安全绕行。", "本周五晚七点，中心操场将举行“秋日弦歌”草坪音乐节。"]
characters = sorted(set("".join(teacher + notice) + " 浩弟帅A0？"))
assert len(characters) == 80 and max(map(len, teacher + notice)) == 26
font = ImageFont.truetype("C:/Windows/Fonts/simsun.ttc", 16)
rows = [0] * 2048
for index, character in enumerate(characters):
    glyph = Image.new("1", (16, 16))
    ImageDraw.Draw(glyph).text((0, 0), character, font=font, fill=1)
    for y in range(16):
        rows[index * 16 + y] = sum(int(glyph.getpixel((x, y))) << (15-x) for x in range(16))
    rows[1280 + index] = ord(character)
(root / "src/app/photo_subtitle_font.dath").write_text("\n".join(f"{row:04x}" for row in rows) + "\n", encoding="ascii")
tf_root = root / "sim/tf_card"
for index, folder in enumerate(("card_a", "card_b")):
    target = tf_root / folder
    target.mkdir(exist_ok=True)
    for filename, content in (("NOTICE.TXT", notice[index]), ("TEACHER.TXT", teacher[index])):
        (target / filename).write_text(content + "\n", encoding="utf-8")
        if index == 0:
            (tf_root / filename).write_text(content + "\n", encoding="utf-8")
(tf_root / "CHARSET.TXT").write_text("".join(characters) + "\n", encoding="utf-8")
print(f"Internal ROM: {len(characters)} glyphs, 2048 x 16, one BRAM32K; TXT lengths {list(map(len, notice + teacher))}")
