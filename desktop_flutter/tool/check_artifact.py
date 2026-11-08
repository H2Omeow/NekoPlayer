import argparse
import hashlib
import json
from pathlib import Path
import struct


TARGETS = {
    "windows-x64": ("pe", 0x8664),
    "windows-arm64": ("pe", 0xAA64),
    "linux-x64": ("elf", 62),
    "linux-arm64": ("elf", 183),
}
DECODER_SOURCE = json.loads((Path(__file__).resolve().parents[1] / "native/decoder.json").read_text())
WINDOWS_RUNTIME_LICENSES = (
    "LLVM-LICENSE.TXT", "COPYING", "COPYING.MinGW-w64.txt",
    "COPYING.MinGW-w64-runtime.txt", "COPYING.winpthreads.txt",
    "COPYING.winstorecompat.txt",
)


LINUX_SYSTEM_LIBRARIES = frozenset((
    "libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "librt.so.1",
    "ld-linux-x86-64.so.2", "ld-linux-aarch64.so.1", "libstdc++.so.6", "libgcc_s.so.1",
    "libz.so.1", "libglib-2.0.so.0", "libgobject-2.0.so.0", "libgio-2.0.so.0",
    "libgtk-3.so.0", "libgdk-3.so.0", "libgdk_pixbuf-2.0.so.0", "libatk-1.0.so.0",
    "libpango-1.0.so.0", "libpangocairo-1.0.so.0", "libcairo.so.2", "libcairo-gobject.so.2",
    "libharfbuzz.so.0", "libepoxy.so.0", "libfontconfig.so.1", "libfreetype.so.6", "libsecret-1.so.0",
    "libgnutls.so.30",
))
# libmpv, WebKitGTK and the app indicator are resolved with dlopen at runtime so that
# one bundle works across distribution sonames; a hard link would pin one of them.
LINUX_FORBIDDEN_PREFIXES = ("libmpv", "libjvm", "libdartjni", "libwebkit", "libjavascriptcore", "libayatana", "libappindicator")
# Android-only JNI helper that the build may still emit; it needs a JVM and is dropped when packaging.
DESKTOP_EXCLUDED_LIBRARIES = ("libdartjni.so",)


def architecture(path):
    with Path(path).open("rb") as binary:
        header = binary.read(64)
        if len(header) < 64:
            raise ValueError("Truncated executable header")
        if header[:4] == b"\x7fELF":
            if header[4:6] != b"\x02\x01":
                raise ValueError("Only 64-bit little-endian ELF is supported")
            return "elf", struct.unpack_from("<H", header, 18)[0]
        if header[:2] == b"MZ":
            offset = struct.unpack_from("<I", header, 60)[0]
            if not 64 <= offset <= 16 * 1024 * 1024:
                raise ValueError("Invalid PE header offset")
            binary.seek(offset)
            signature = binary.read(26)
            if len(signature) != 26 or signature[:4] != b"PE\x00\x00":
                raise ValueError("Invalid PE signature")
            if struct.unpack_from("<H", signature, 24)[0] != 0x20B:
                raise ValueError("Only PE32+ (64-bit) is supported")
            return "pe", struct.unpack_from("<H", signature, 4)[0]
        raise ValueError("Expected a native ELF or PE executable, not an archive")


def elf_needed(path):
    """Return the DT_NEEDED sonames of a 64-bit little-endian ELF (empty without a dynamic section)."""
    data = Path(path).read_bytes()
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4:6] != b"\x02\x01":
        raise ValueError(f"{path}: not a 64-bit little-endian ELF")
    phoff, = struct.unpack_from("<Q", data, 32)
    phentsize, phnum = struct.unpack_from("<HH", data, 54)
    headers = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        if phentsize < 56 or offset + 56 > len(data):
            raise ValueError(f"{path}: truncated ELF program headers")
        kind, _, file_offset, vaddr, _, filesz, _, _ = struct.unpack_from("<IIQQQQQQ", data, offset)
        headers.append((kind, file_offset, vaddr, filesz))
    dynamic = [header for header in headers if header[0] == 2]
    if not dynamic:
        return []
    _, dynamic_offset, _, dynamic_size = dynamic[0]
    needed, string_table = [], None
    for offset in range(dynamic_offset, min(dynamic_offset + dynamic_size, len(data)) - 15, 16):
        tag, value = struct.unpack_from("<qQ", data, offset)
        if tag == 0:
            break
        if tag == 1:
            needed.append(value)
        elif tag == 5:
            string_table = value
    if not needed:
        return []
    for kind, file_offset, vaddr, filesz in headers:
        if kind == 1 and string_table is not None and vaddr <= string_table < vaddr + filesz:
            base = file_offset + string_table - vaddr
            break
    else:
        raise ValueError(f"{path}: dynamic string table not found")
    names = []
    for value in needed:
        end = data.find(b"\0", base + value)
        if end < 0:
            raise ValueError(f"{path}: unterminated dynamic string")
        names.append(data[base + value:end].decode("ascii", "replace"))
    return names


def verify_linux_dependencies(directory, binaries):
    """Reject hard dependencies that would stop one bundle from running across distributions."""
    directory = Path(directory)
    bundled = {path.name for path in directory.rglob("*") if path.is_file()}
    for binary in binaries:
        for name in elf_needed(binary):
            if name.startswith(LINUX_FORBIDDEN_PREFIXES):
                raise ValueError(f"{binary.name} hard-links {name}; load it with dlopen instead")
            if name not in bundled and name not in LINUX_SYSTEM_LIBRARIES:
                raise ValueError(f"{binary.name} depends on {name}, which is neither bundled nor an allowed system library")


def verify(target, paths):
    expected = TARGETS[target]
    for path in paths:
        actual = architecture(path)
        if actual != expected:
            raise ValueError(f"{path}: architecture {actual} does not match {target}")


def verify_decoder_directory(target, directory):
    directory = Path(directory)
    suffix = ".exe" if target.startswith("windows-") else ""
    binaries = [directory / "native" / (name + suffix) for name in ("ffmpeg", "ffprobe")]
    verify(target, binaries)
    licenses = directory / "licenses/ffmpeg"
    manifest = json.loads((licenses / "build-info.json").read_text())
    source = DECODER_SOURCE
    if not isinstance(manifest, dict):
        raise ValueError("Invalid decoder build manifest")
    if manifest.get("version") != 1 or manifest.get("target") != target or manifest.get("source") != source:
        raise ValueError("Decoder provenance does not match target and pinned source")
    options = manifest.get("configure")
    if not isinstance(options, list) or not all(isinstance(option, str) for option in options):
        raise ValueError("Decoder build configuration is missing")
    for required in ("--enable-ffmpeg", "--enable-ffprobe", "--enable-network", "--enable-filter=aresample,aformat,anull,atrim,atempo"):
        if required not in options:
            raise ValueError(f"Decoder configuration lacks required capability: {required}")
    tls_backend = "--enable-schannel" if target.startswith("windows-") else "--enable-gnutls"
    if tls_backend not in options:
        raise ValueError("Decoder TLS backend does not match platform")
    if "--enable-protocol=file,pipe,http,https,tcp,tls,udp" not in options:
        raise ValueError("Decoder configuration lacks required HTTP/TLS protocols")
    if any(option in options for option in ("--disable-network", "--disable-ffprobe", "--enable-nonfree", "--enable-gpl")):
        raise ValueError("Incompatible decoder build configuration")
    checksums = manifest.get("binaries")
    if not isinstance(checksums, dict):
        raise ValueError("Decoder binary checksums are missing")
    for binary in binaries:
        with binary.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if checksums.get(binary.name) != digest:
            raise ValueError(f"Decoder binary checksum mismatch: {binary}")
    if target.startswith("windows-"):
        runtime = manifest.get("runtimeLicenses")
        if not isinstance(runtime, dict) or set(runtime) != set(WINDOWS_RUNTIME_LICENSES):
            raise ValueError("Windows decoder runtime license checksums are missing")
        for name in WINDOWS_RUNTIME_LICENSES:
            with (directory / "licenses/llvm-mingw" / name).open("rb") as stream:
                if runtime[name] != hashlib.file_digest(stream, "sha256").hexdigest():
                    raise ValueError(f"Windows decoder runtime license checksum mismatch: {name}")
    for name in ("COPYING.LGPLv2.1", "COPYING.LGPLv3", "LICENSE.md"):
        if not (licenses / name).is_file():
            raise ValueError(f"Missing FFmpeg license: {name}")
    archive = licenses / source["url"].rsplit("/", 1)[1]
    with archive.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != source["sha256"]:
            raise ValueError("Bundled FFmpeg source checksum mismatch")
    for spec in source.get("patches", []):
        with (licenses / spec["file"]).open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != spec["sha256"]:
                raise ValueError("Bundled FFmpeg source patch checksum mismatch")
    return binaries


def font_source():
    return json.loads((Path(__file__).resolve().parents[1] / "assets/fonts/source.json").read_text())


def verify_font_bundle(directory):
    source = font_source()
    assets = Path(directory) / "data/flutter_assets"
    for kind in ("font", "license"):
        specification = source[kind]
        asset = assets / specification["asset"]
        if not asset.is_file():
            raise ValueError(f"Missing bundled {kind}: {asset}")
        with asset.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != specification["sha256"]:
                raise ValueError(f"Bundled {kind} checksum mismatch: {asset}")
    manifest = json.loads((assets / "FontManifest.json").read_text())
    if not isinstance(manifest, list) or not any(
        isinstance(entry, dict) and entry.get("family") == source["family"]
        and isinstance(entry.get("fonts"), list) and any(
            isinstance(font, dict) and font.get("asset") == source["font"]["asset"]
            for font in entry["fonts"]
        ) for entry in manifest
    ):
        raise ValueError("Bundled CJK font is not registered in FontManifest.json")


def verify_bundle(target, directory, require_decoders=False, packaged=False):
    directory = Path(directory)
    windows = target.startswith("windows-")
    aot_library = directory / ("data/app.so" if windows else "lib/libapp.so")
    required = [
        "NekoPlayer.exe" if windows else "nekoplayer",
        "flutter_windows.dll" if windows else "lib/libflutter_linux_gtk.so",
        "nekoplayer_dsp.dll" if windows else "lib/libnekoplayer_dsp.so",
        "nekoplayer_plugins.dll" if windows else "lib/libnekoplayer_plugins.so",
        "data/app.so" if windows else "lib/libapp.so",
        "data/icudtl.dat",
        "data/flutter_assets/AssetManifest.bin",
    ]
    for name in required:
        if not (directory / name).is_file():
            raise ValueError(f"Missing bundle component: {directory / name}")
    excluded = [] if windows else [path for path in directory.rglob("*") if path.name in DESKTOP_EXCLUDED_LIBRARIES]
    if packaged and excluded:
        raise ValueError(f"Unsupported desktop library in package: {excluded[0]}")
    binaries = [directory / required[0]]
    binaries.extend(
        path for path in directory.rglob("*")
        if path.is_file() and path not in excluded and (
            path.suffix.lower() in (".dll", ".exe") if windows
            else path.name.endswith(".so") or ".so." in path.name
        ) and path not in (binaries[0], aot_library)
    )
    for name in ("ffmpeg", "ffprobe"):
        decoder = directory / "native" / (name + (".exe" if windows else ""))
        if decoder.is_file() and decoder not in binaries:
            binaries.append(decoder)
    verify(target, binaries)
    verify(target.replace("windows-", "linux-"), [aot_library])
    if not windows:
        verify_linux_dependencies(directory, binaries)
    binaries.append(aot_library)
    verify_font_bundle(directory)
    if require_decoders:
        verify_decoder_directory(target, directory)
    return binaries


def main():
    parser = argparse.ArgumentParser(description="Verify NekoPlayer executable and bundled native library architectures")
    parser.add_argument("target", choices=TARGETS)
    parser.add_argument("files", type=Path, nargs="*")
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--decoder-directory", type=Path)
    parser.add_argument("--require-decoders", action="store_true")
    arguments = parser.parse_args()
    if sum(map(bool, (arguments.files, arguments.bundle, arguments.decoder_directory))) != 1:
        parser.error("Provide native files, --bundle DIRECTORY or --decoder-directory DIRECTORY")
    if arguments.require_decoders and not arguments.bundle:
        parser.error("--require-decoders requires --bundle")
    try:
        if arguments.bundle:
            paths = verify_bundle(arguments.target, arguments.bundle, arguments.require_decoders)
        elif arguments.decoder_directory:
            paths = verify_decoder_directory(arguments.target, arguments.decoder_directory)
        else:
            paths = arguments.files
            verify(arguments.target, paths)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Artifact validation failed: {error}\n")
    print(f"Verified {len(paths)} native file(s) for {arguments.target}")


if __name__ == "__main__":
    main()
