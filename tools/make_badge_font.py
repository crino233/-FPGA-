from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
characters = " 设置音量亮度护眼间隔闪速关闭暖色夜标准快秒考试模式备进行中暂停结束应急演练请沿箭头疏散0123456789%:/转场淡入出左右擦除字幕开启透明静自动K选时继续重始手上一项下减少增加×"
assert len(characters) == 92 and len(set(characters)) == 92
font = ImageFont.truetype("C:/Windows/Fonts/simsun.ttc", 16)
digits = [
    [14,17,19,21,25,17,14], [4,12,4,4,4,4,14],
    [14,17,1,6,8,16,31], [30,1,1,14,1,1,30],
    [2,6,10,18,31,2,2], [31,16,16,30,1,1,30],
    [14,16,16,30,17,17,14], [31,1,2,4,8,8,8],
    [14,17,17,14,17,17,14], [14,17,17,15,1,1,14],
]
rows = []
atlas = Image.new("RGB", (16 * 48, 6 * 64), "white")
atlas_draw = ImageDraw.Draw(atlas)
for index, character in enumerate(characters):
    glyph = Image.new("1", (16, 16))
    draw = ImageDraw.Draw(glyph)
    if character in "0123456789K":
        pattern = [17, 18, 20, 24, 20, 18, 17] if character == "K" else digits[int(character)]
        for y, value in enumerate(pattern):
            for x in range(5):
                if value & (1 << (4 - x)):
                    draw.rectangle((3+x*2, 1+y*2, 4+x*2, 2+y*2), fill=1)
    elif character != " ":
        draw.text((0 if not character.isascii() else 4, 0), character, font=font, fill=1)
    for y in range(16):
        rows.append(sum(int(glyph.getpixel((x, y))) << (15-x) for x in range(16)))
    atlas.paste(glyph.resize((32, 32)).convert("RGB"), ((index % 16)*48, (index // 16)*64))
    atlas_draw.text(((index % 16)*48, (index // 16)*64+34), str(index), fill="black")
rows += [0] * (2048-len(rows))
words = ["设置", "音量", "亮度", "护眼", "间隔", "闪速", "关闭", "暖色", "夜间",
         "标准", "快速", "考试模式", "准备", "进行中", "暂停", "结束", "应急模式", "请沿箭头疏散",
         "转场", "淡入淡出", "左右擦除", "字幕", "开启", "字速", "透明",
         "静音", "自动", "K2开始", "K3选时", "K4重置", "K2暂停", "K2继续", "手动"]
map_base = len(characters) * 16
for word_index, word in enumerate(words):
    for pair_index in range(4):
        pair = word[pair_index*2:pair_index*2+2]
        rows[map_base+word_index*4+pair_index] = sum(characters.index(ch) << (7*i) for i, ch in enumerate(pair))
(root / "src/app/photo_font.dath").write_text(
    "\n".join(f"{value:04x}" for value in rows) + "\n", encoding="ascii")
(root / "sim/work").mkdir(exist_ok=True)
atlas.save(root / "sim/work/badge_font_atlas.png")
print(f"{len(characters)} fixed glyphs, 4 BRAM9K target")
