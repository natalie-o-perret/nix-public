import base64
import hashlib
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import tempfile
import time
import zlib


def png(path, width, height):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    pixels = (b"\0" + b"\xe9\x1e\x63" * width) * height
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(pixels))
        + chunk(b"IEND", b"")
    )


package, quickshell = Path(sys.argv[1]), sys.argv[2]
app = package / "bin/dimages"
desktop = (package / "share/applications/local.dux.images.desktop").read_text()
assert "\nName=Images\n" in desktop
mime_types = next(line.removeprefix("MimeType=") for line in desktop.splitlines() if line.startswith("MimeType=")).split(";")
assert {"image/x-xbitmap", "image/x-xpixmap"} <= set(mime_types)
with tempfile.TemporaryDirectory(prefix="dux-images-check-", dir=os.environ.get("TMPDIR")) as temporary:
    root = Path(temporary)
    images = root / "images #%? \u00fc"
    images.mkdir()
    first = images / "01 <b> space #% \u00fc.png"
    second = images / "02 next.PNG"
    png(first, 1600, 900)
    png(second, 200, 100)
    (images / "ignored.txt").write_text("not an image")
    empty = root / "empty folder"
    empty.mkdir()
    (empty / "ignored.txt").write_text("not an image")
    (empty / "nested").mkdir()
    png(empty / "nested/ignored.png", 10, 10)
    single = root / "single image"
    single.mkdir()
    single_image = single / "only.png"
    png(single_image, 120, 80)
    many = root / "many images"
    many.mkdir()
    for index in range(24):
        png(many / f"{index:02}.png", 30, 20)
    pictures = root / "Pictures"
    pictures.mkdir()
    png(pictures / "default.png", 60, 40)
    broken = root / "broken.png"
    broken.write_text("not a PNG")
    vector = root / "vector.svg"
    vector.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="480"><rect width="640" height="480" fill="#e91e63"/></svg>')
    retina = root / "retina@2x.png"
    png(retina, 400, 200)
    oriented = root / "oriented.jpg"
    jpeg = base64.b64decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAACAAQDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCYAFuf/9k=')
    exif = b'Exif\0\0II*\0' + struct.pack('<IH', 8, 1) + struct.pack('<HHIHHI', 0x112, 3, 1, 6, 0, 0)
    oriented.write_bytes(jpeg[:2] + b'\xff\xe1' + struct.pack('>H', len(exif) + 2) + exif + jpeg[2:])
    pixmap = root / "icon.xpm"
    pixmap.write_text('/* XPM */\nstatic char *icon[] = {\n"2 2 1 1",\n"x c #e91e63",\n"xx",\n"xx"};\n')
    bitmap = root / "icon.xbm"
    bitmap.write_text('#define icon_width 8\n#define icon_height 2\nstatic unsigned char icon_bits[] = {0x55, 0xaa};\n')
    original = {p: hashlib.sha256(p.read_bytes()).digest() for p in root.rglob("*") if p.is_file()}

    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    env = {
        **os.environ,
        "HOME": str(root),
        "XDG_CACHE_HOME": str(root / "cache"),
        "XDG_CONFIG_HOME": str(root / "config"),
        "XDG_RUNTIME_DIR": str(runtime),
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software",
        "QT_LOGGING_RULES": "qml.debug=true;qml.info=true",
        "QS_DISABLE_CRASH_HANDLER": "1",
        "TEST_FIRST": str(first),
        "TEST_SECOND": str(second),
        "TEST_BROKEN": str(broken),
        "TEST_VECTOR": str(vector),
        "TEST_RETINA": str(retina),
        "TEST_ORIENTED": str(oriented),
        "TEST_XPM": str(pixmap),
        "TEST_XBM": str(bitmap),
        "TEST_FOLDER": str(images),
        "TEST_EMPTY_FOLDER": str(empty),
        "TEST_SINGLE": str(single_image),
        "TEST_MANY": str(many),
    }
    for arguments, expected in [(["--help"], 0), (["--unknown"], 2), ([str(root / "absent")], 1), ([str(first), str(second)], 2)]:
        result = subprocess.run([str(app), *arguments], env=env, capture_output=True, text=True, timeout=5)
        assert result.returncode == expected, (arguments, result.stdout, result.stderr)

    def write_theme():
        files = {
            root / "cache/dms/dms-colors.json": {"mode": "dark", "colors": {"dark": {"primary": "#e91e63", "on_primary": "#000000", "surface": "#191112", "on_surface": "#f0dee0"}}},
            root / "cache/dms/dms-typography.json": {"fontFamily": "Google Sans Flex", "fontScale": 1},
            root / "config/dms/settings.json": {"radiusStrength": 50},
        }
        for path, value in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value))

    for scale in ("1", "1.5"):
        write_theme()
        result = subprocess.run(
            [quickshell, "--no-color", "-p", str(package / "share/dux-images/tests.qml")],
            env={**env, "QT_SCALE_FACTOR": scale}, capture_output=True, text=True, timeout=25,
        )
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "DUX_IMAGES_TEST_PASS" in output and "DUX_IMAGES_TEST_FAIL" not in output, output
        assert not any(error in output for error in ("TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Cannot assign")), output
        print(f"QML integration checks passed at {scale}x display scaling")

    write_theme()
    for target, variable in ((first, "DIMAGES_FILE"), (images, "DIMAGES_FOLDER"), (empty, "DIMAGES_FOLDER"), (None, "DIMAGES_FILE")):
        arguments = [str(app)] + ([str(target)] if target is not None else [])
        process = subprocess.Popen(arguments, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        logs = ""
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and process.poll() is None:
                environment = (Path("/proc") / str(process.pid) / "environ").read_bytes().split(b"\0")
                value = str(target.resolve()) if target is not None else ""
                if os.fsencode(variable + "=" + value) in environment:
                    break
                time.sleep(0.02)
            else:
                raise AssertionError(f"Launcher did not preserve {target}")
            while time.monotonic() < deadline and "Configuration Loaded" not in logs:
                if not select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))[0]:
                    break
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                logs += chunk.decode(errors="replace")
            assert "Configuration Loaded" in logs, logs
            assert not any(error in logs for error in ("TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Cannot assign")), logs
        finally:
            process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()

    for path, digest in original.items():
        assert hashlib.sha256(path.read_bytes()).digest() == digest, f"Image modified: {path}"
    print("CLI validation, filename handling and read-only checks passed")
