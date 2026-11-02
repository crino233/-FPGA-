import argparse
import array
import shutil
import struct
import subprocess
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path)
args = parser.parse_args()
work = root / "sim/work"
work.mkdir(exist_ok=True)
samples = [(i * 73) % 60001 - 30000 for i in range(5000)]
pcm = struct.pack("<5000h", *samples)
chunks = b"JUNK" + struct.pack("<I", 3) + b"abc\0"
chunks += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, 48000, 96000, 2, 16)
chunks += b"data" + struct.pack("<I", len(pcm)) + pcm
fixture = b"RIFF" + struct.pack("<I", len(chunks) + 4) + b"WAVE" + chunks
(work / "wav_fixture.hex").write_text("\n".join(f"{b:02x}" for b in fixture) + "\n", encoding="ascii")
(work / "wav_expected.hex").write_text("\n".join(f"{v & 65535:04x}" for v in samples) + "\n", encoding="ascii")
print(f"Regression WAV: {len(fixture)} bytes, odd JUNK chunk, 5000 signed samples")
if args.source:
    raw = subprocess.check_output([shutil.which("ffmpeg"), "-v", "error", "-nostdin", "-i", str(args.source),
                                   "-vn", "-ac", "1", "-ar", "48000", "-f", "s16le", "pipe:1"])
    audio = array.array("h", raw)
    
    for i in range(min(240, len(audio) // 2)):
        audio[i] = audio[i] * i // 240
        audio[-1-i] = audio[-1-i] * i // 240
    destination = root / "sim/tf_card/BGM.WAV"
    with wave.open(str(destination), "wb") as output:
        output.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
        output.writeframes(audio.tobytes())
    print(f"{destination}: {len(audio)} samples, {len(audio)/48000:.6f} seconds")
