import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tarfile
import tempfile

from check_artifact import DECODER_SOURCE as SOURCE, TARGETS, WINDOWS_RUNTIME_LICENSES, verify, verify_decoder_directory
from download import fetch


ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_archive(cache):
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / SOURCE["url"].rsplit("/", 1)[1]
    if archive.exists():
        if sha256(archive) != SOURCE["sha256"]:
            raise ValueError("Cached FFmpeg source checksum mismatch")
        return archive
    fetch(SOURCE["url"], archive, timeout=60)
    if sha256(archive) != SOURCE["sha256"]:
        archive.unlink(missing_ok=True)
        raise ValueError("Downloaded FFmpeg source checksum mismatch")
    return archive


def configure_options(target, prefix="", host_arch=None, linux_sysroot=None):
    if target not in TARGETS:
        raise ValueError("Only Windows/Linux x64 and ARM64 are supported")
    windows = target.startswith("windows-")
    arch = target.split("-")[1]
    host_arch = (host_arch or platform.machine()).lower()
    native_arch = {"x86_64": "x64", "amd64": "x64", "aarch64": "arm64", "arm64": "arm64"}.get(host_arch)
    if windows and not prefix:
        raise ValueError("Windows decoder builds require a native target LLVM-MinGW --toolchain-prefix")
    if windows and linux_sysroot:
        raise ValueError("A Linux sysroot cannot be used for Windows decoder builds")
    if not windows and bool(prefix) != bool(linux_sysroot):
        raise ValueError("Linux cross builds require both --toolchain-prefix and --linux-sysroot")
    if not windows and arch != native_arch and not linux_sysroot:
        raise ValueError("Linux cross builds require an explicit target toolchain and isolated TLS sysroot")
    options = [
        "--arch=" + ("x86_64" if arch == "x64" else "aarch64"),
        "--disable-autodetect", "--disable-everything", "--disable-doc",
        "--disable-debug", "--disable-asm", "--disable-shared", "--enable-static",
        "--disable-ffplay", "--enable-ffmpeg", "--enable-ffprobe", "--enable-network",
        "--enable-protocol=file,pipe,http,https,tcp,tls,udp",
        "--enable-demuxer=mov,mp3,flac,ogg,wav,aac,ape,asf,matroska",
        "--enable-decoder=mp3,mp3float,flac,aac,aac_fixed,alac,vorbis,opus,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f64le,pcm_u8,pcm_s8,ape,wmav1,wmav2,wmapro,wmalossless",
        "--enable-encoder=pcm_s16le", "--enable-muxer=pcm_s16le",
        "--enable-parser=mpegaudio,aac,flac,opus,vorbis",
        "--enable-filter=aresample,aformat,anull,atrim,atempo",
        "--enable-swresample", "--optflags=-O1",
    ]
    if windows:
        options += [
            "--enable-cross-compile", "--target-os=mingw32", "--enable-schannel",
            "--cross-prefix=" + prefix, "--cc=" + prefix + "clang",
            "--cxx=" + prefix + "clang++", "--extra-ldflags=-static",
        ]
    else:
        options += ["--enable-gnutls", "--enable-pthreads"]
        if linux_sysroot:
            triplet = "aarch64-linux-gnu" if arch == "arm64" else "x86_64-linux-gnu"
            options += [
                "--enable-cross-compile", "--target-os=linux",
                "--cross-prefix=" + prefix,
                "--sysroot=" + str(linux_sysroot),
                "--extra-ldflags=-Wl,-rpath-link=" + str(Path(linux_sysroot) / "usr/lib" / triplet),
                "--pkg-config=pkg-config",
            ]
    return options


def linux_cross_environment(target, sysroot):
    if target not in ("linux-x64", "linux-arm64"):
        raise ValueError("An isolated Linux sysroot requires a Linux target")
    root = Path(sysroot).resolve(strict=True)
    triplet = "aarch64-linux-gnu" if target.endswith("arm64") else "x86_64-linux-gnu"
    for relative in ("usr/include/gnutls/gnutls.h", f"usr/lib/{triplet}/libgnutls.so"):
        dependency = (root / relative).resolve(strict=True)
        if not dependency.is_relative_to(root):
            raise ValueError("TLS dependency escapes the target sysroot")
        if relative.endswith(".so"):
            verify(target, [dependency])
    environment = os.environ.copy()
    for name in ("CFLAGS", "CPPFLAGS", "CXXFLAGS", "LDFLAGS", "LIBRARY_PATH", "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR", "PKG_CONFIG_SYSROOT_DIR"):
        environment.pop(name, None)
    environment.update({
        "PKG_CONFIG_PATH": "",
        "PKG_CONFIG_LIBDIR": os.pathsep.join(str(root / relative) for relative in (f"usr/lib/{triplet}/pkgconfig", "usr/lib/pkgconfig", "usr/share/pkgconfig")),
        "PKG_CONFIG_SYSROOT_DIR": str(root),
    })
    return environment


def validate_linux_toolchain(target, prefix, sysroot, environment):
    expected = "aarch64-linux-gnu" if target.endswith("arm64") else "x86_64-linux-gnu"
    machine = subprocess.run([prefix + "gcc", "-dumpmachine"], capture_output=True, text=True, check=True).stdout.strip()
    if machine != expected:
        raise ValueError(f"Compiler target {machine} does not match {expected}")
    flags = shlex.split(subprocess.run(
        ["pkg-config", "--cflags", "--libs", "gnutls"],
        env=environment, capture_output=True, text=True, check=True,
    ).stdout)
    root = Path(sysroot).resolve(strict=True)
    for flag in flags:
        if flag.startswith(("-I", "-L")) and not Path(flag[2:]).resolve().is_relative_to(root):
            raise ValueError("pkg-config returned a dependency outside the target sysroot")
    with tempfile.TemporaryDirectory(prefix="nekoplayer-tls-probe-") as temporary:
        source = Path(temporary) / "probe.c"
        source.write_text("#include <gnutls/gnutls.h>\nint main(void) { return gnutls_global_init(); }\n")
        binary = Path(temporary) / "probe"
        run([prefix + "gcc", "--sysroot=" + str(root), source, "-o", binary,
             "-Wl,-rpath-link=" + str(root / "usr/lib" / expected), *flags], temporary, environment)
        verify(target, [binary])


def run(arguments, cwd, environment=None):
    print("+", " ".join(map(str, arguments)), flush=True)
    subprocess.run(list(map(str, arguments)), cwd=cwd, env=environment, check=True)


def windows_runtime_licenses(target, prefix):
    compiler = shutil.which(prefix + "clang")
    if compiler is None:
        raise ValueError("LLVM-MinGW compiler is unavailable")
    root = Path(compiler).resolve().parent.parent
    triplet = "aarch64-w64-mingw32" if target.endswith("arm64") else "x86_64-w64-mingw32"
    paths = {
        name: root / ("LICENSE.TXT" if name == "LLVM-LICENSE.TXT" else f"{triplet}/share/mingw32/{name}")
        for name in WINDOWS_RUNTIME_LICENSES
    }
    for path in paths.values():
        if not path.is_file():
            raise ValueError(f"Missing LLVM-MinGW runtime license: {path}")
    return paths


def build(target, work, prefix="", jobs=2, linux_sysroot=None):
    if platform.system() != "Linux":
        raise ValueError("Build decoders on Linux; Windows targets use LLVM-MinGW")
    if linux_sysroot:
        linux_sysroot = Path(linux_sysroot).resolve(strict=True)
    options = configure_options(target, prefix, linux_sysroot=linux_sysroot)
    runtime_licenses = windows_runtime_licenses(target, prefix) if target.startswith("windows-") else {}
    environment = None
    if linux_sysroot:
        environment = linux_cross_environment(target, linux_sysroot)
        validate_linux_toolchain(target, prefix, linux_sysroot, environment)
    archive = source_archive(work / "cache")
    source_id = hashlib.sha256(json.dumps(SOURCE, sort_keys=True).encode()).hexdigest()
    source = work / "source" / source_id
    if not (source / ".nekoplayer-prepared").is_file():
        if source.exists():
            shutil.rmtree(source)
        source.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive) as packed:
            roots = {Path(member.name).parts[0] for member in packed.getmembers() if member.name}
            if len(roots) != 1:
                raise ValueError("Unexpected FFmpeg source archive structure")
            packed.extractall(source, filter="data")
        extracted = source / roots.pop()
        for child in extracted.iterdir():
            child.rename(source / child.name)
        extracted.rmdir()
        for spec in SOURCE.get("patches", []):
            patch = ROOT / "native" / spec["file"]
            if sha256(patch) != spec["sha256"]:
                raise ValueError("FFmpeg source patch checksum mismatch")
            run(["patch", "--batch", "-p1", "-i", patch], source)
        (source / ".nekoplayer-prepared").touch()
    fingerprint = hashlib.sha256(json.dumps({"source": SOURCE, "configure": options}, sort_keys=True).encode()).hexdigest()[:16]
    build_dir = work / target / ("build-" + fingerprint)
    build_dir.mkdir(parents=True, exist_ok=True)
    configuration = build_dir / "nekoplayer-configuration.json"
    if configuration.exists() and json.loads(configuration.read_text()) != options:
        raise ValueError("Decoder configure options changed; use a fresh --work-directory instead of reusing incompatible objects")
    run([source / "configure", *options], build_dir, environment)
    configuration.write_text(json.dumps(options))
    suffix = ".exe" if target.startswith("windows-") else ""
    binaries = [build_dir / (name + suffix) for name in ("ffmpeg", "ffprobe")]
    run(["make", f"-j{jobs}", *(binary.name for binary in binaries)], build_dir, environment)
    verify(target, binaries)
    staging = work / target / "package"
    native = staging / "native"
    licenses = staging / "licenses/ffmpeg"
    native.mkdir(parents=True, exist_ok=True)
    licenses.mkdir(parents=True, exist_ok=True)
    for binary in binaries:
        shutil.copy2(binary, native / binary.name)
        (native / binary.name).chmod(0o755)
    for name in ("COPYING.LGPLv2.1", "COPYING.LGPLv3", "LICENSE.md"):
        shutil.copy2(source / name, licenses / name)
    for spec in SOURCE.get("patches", []):
        shutil.copy2(ROOT / "native" / spec["file"], licenses / spec["file"])
    shutil.copy2(archive, licenses / archive.name)
    if runtime_licenses:
        runtime_destination = staging / "licenses/llvm-mingw"
        runtime_destination.mkdir(parents=True, exist_ok=True)
        for name, license_file in runtime_licenses.items():
            shutil.copy2(license_file, runtime_destination / name)
    manifest = {
        "version": 1,
        "target": target,
        "source": SOURCE,
        "configure": options,
        "binaries": {binary.name: sha256(binary) for binary in binaries},
        **({"runtimeLicenses": {name: sha256(path) for name, path in runtime_licenses.items()}} if runtime_licenses else {}),
    }
    (licenses / "build-info.json").write_text(json.dumps(manifest, indent=2) + "\n")
    verify_decoder_directory(target, staging)
    print(f"Verified decoder package: {staging}\nNEKO_DECODER_DIR={staging}", flush=True)
    return staging


def main():
    parser = argparse.ArgumentParser(description="Build pinned FFmpeg and ffprobe for Flutter DSP (run through deploy/run-low-resource.sh)")
    parser.add_argument("target", choices=TARGETS)
    parser.add_argument("--toolchain-prefix", default="", help="Executable prefix: LLVM-MinGW for Windows, GNU target toolchain for Linux cross builds")
    parser.add_argument("--linux-sysroot", type=Path, help="Isolated target sysroot containing GnuTLS headers and libraries; requires --toolchain-prefix")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--work-directory", type=Path, default=ROOT / "build/decoder")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    try:
        build(args.target, args.work_directory.resolve(), args.toolchain_prefix, args.jobs,
              args.linux_sysroot.resolve() if args.linux_sysroot else None)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Decoder build failed: {error}\n")


if __name__ == "__main__":
    main()
