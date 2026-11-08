import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile

from check_artifact import verify


ROOT = Path(__file__).resolve().parents[1]
PINS = json.loads((ROOT / "native/windows_dependencies.json").read_text())


def download(name, directory):
    specification = PINS[name]
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / specification["url"].rsplit("/", 1)[1]
    if not destination.exists():
        temporary = destination.with_suffix(".part")
        try:
            with urllib.request.urlopen(specification["url"], timeout=90) as incoming, temporary.open("wb") as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    with destination.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != specification["sha256"]:
            raise ValueError(f"Dependency checksum mismatch: {name}")
    return destination


def prepare_toolchain(directory):
    archive = download("llvm_mingw", directory)
    root = directory / archive.name.removesuffix(".tar.xz")
    if not (root / "bin/x86_64-w64-mingw32-clang").is_file():
        with tarfile.open(archive) as packed:
            packed.extractall(directory, filter="data")
    return root / "bin"


def forwarder_definitions(exports):
    egl = {"egl" + name[4:]: name for name in exports if re.fullmatch(r"EGL_[A-Za-z0-9_]+", name)}
    gles = {name: name for name in exports if re.fullmatch(r"gl[A-Z][A-Za-z0-9_]*", name)}
    if not {"eglInitialize", "eglGetProcAddress", "eglChooseConfig"} <= egl.keys() or "glFinish" not in gles:
        raise ValueError("ANGLE exports do not provide the required EGL/GLES interface")
    return {
        library: f"LIBRARY {library}.dll\nEXPORTS\n" + "".join(
            f"  {public}=av_libglesv2.{native}\n" for public, native in sorted(symbols.items())
        ) for library, symbols in (("libEGL", egl), ("libGLESv2", gles))
    }


def prepare_angle(target, directory):
    arch = target.split("-")[1]
    build = ROOT / "build/windows" / arch
    build.mkdir(parents=True, exist_ok=True)
    headers = download("angle_headers", directory)
    shutil.copy2(headers, build / "ANGLE.7z")
    angle = directory / ("angle-" + arch)
    angle.mkdir(parents=True, exist_ok=True)
    subprocess.run(["7z", "x", "-y", str(headers), "include/*", "-o" + str(angle)], check=True)
    package = download("angle_runtime", directory)
    runtime = angle / "av_libglesv2.dll"
    with zipfile.ZipFile(package) as packed:
        runtime.write_bytes(packed.read(f"runtimes/win-{arch}/native/av_libglesv2.dll"))
        (angle / "LICENSE").write_bytes(packed.read("LICENSE"))
    verify(target, [runtime])
    output = subprocess.run(["dumpbin.exe", "/nologo", "/exports", str(runtime)], check=True, capture_output=True, text=True).stdout
    exports = re.findall(r"^\s*\d+\s+[\dA-Fa-f]+\s+[\dA-Fa-f]+\s+(\w+)", output, re.MULTILINE)
    (angle / "lib").mkdir(exist_ok=True)
    machine = "ARM64" if arch == "arm64" else "X64"
    for library, definition in forwarder_definitions(exports).items():
        source = angle / (library + ".def")
        source.write_text(definition)
        subprocess.run(["link.exe", "/nologo", "/dll", "/noentry", "/nodefaultlib", "/machine:" + machine,
                        "/def:" + str(source), "/out:" + str(angle / (library + ".dll")),
                        "/implib:" + str(angle / "lib" / (library + ".dll.lib"))], check=True)
    verify(target, list(angle.glob("*.dll")))
    with os.add_dll_directory(str(angle)):
        egl = ctypes.WinDLL(str(angle / "libEGL.dll"))
        egl.eglGetProcAddress.argtypes = [ctypes.c_char_p]
        egl.eglGetProcAddress.restype = ctypes.c_void_p
        if not egl.eglGetProcAddress(b"glFinish"):
            raise ValueError("ANGLE EGL procedure lookup failed")
    return angle


def prepare_mpv(target, directory):
    arch = target.split("-")[1]
    build = ROOT / "build/windows" / arch
    archive = download("mpv_" + arch, directory)
    shutil.copy2(archive, build / archive.name)
    mpv = build / "libmpv"
    subprocess.run(["7z", "x", "-y", str(archive), "-o" + str(mpv)], check=True)
    nested = mpv / "include/mpv"
    if nested.is_dir():
        for header in nested.iterdir():
            shutil.copy2(header, mpv / "include" / header.name)
    verify(target, [mpv / "libmpv-2.dll"])


def prepare_webview2(target, directory):
    arch = target.split("-")[1]
    package = download("webview2", directory)
    webview2 = directory / ("webview2-" + arch)
    shutil.rmtree(webview2, ignore_errors=True)
    (webview2 / "include").mkdir(parents=True)
    (webview2 / "lib").mkdir()
    with zipfile.ZipFile(package) as packed:
        for header in ("WebView2.h", "WebView2EnvironmentOptions.h"):
            (webview2 / "include" / header).write_bytes(packed.read("build/native/include/" + header))
        library = packed.read(f"build/native/{arch}/WebView2LoaderStatic.lib")
        if not library.startswith(b"!<arch>\n"):
            raise ValueError("WebView2 static loader is not a COFF archive")
        (webview2 / "lib/WebView2LoaderStatic.lib").write_bytes(library)
        (webview2 / "LICENSE.txt").write_bytes(packed.read("LICENSE.txt"))
    return webview2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("component", choices=("toolchain", "runtime", "installer"))
    parser.add_argument("--target", choices=("windows-x64", "windows-arm64"), default="windows-x64")
    parser.add_argument("--directory", type=Path, default=ROOT / "build/windows-dependencies")
    args = parser.parse_args()
    directory = args.directory.resolve()
    extra = {}
    if args.component == "toolchain":
        result = prepare_toolchain(directory)
        key = "PATH"
    elif args.component == "runtime":
        result = prepare_angle(args.target, directory)
        prepare_mpv(args.target, directory)
        webview2 = prepare_webview2(args.target, directory)
        extra = {"NEKO_WINDOWS_WEBVIEW2_DIR": webview2, "NEKO_REQUIRE_WEBVIEW2": "ON"}
        key = "NEKO_WINDOWS_ANGLE_DIR"
    else:
        installer = download("inno_setup", directory)
        result = directory / "inno-setup"
        subprocess.run([str(installer), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=" + str(result)], check=True)
        key = "NEKO_ISCC"
        result /= "ISCC.exe"
    destination = os.environ.get("GITHUB_PATH" if key == "PATH" else "GITHUB_ENV")
    if destination:
        with open(destination, "a", encoding="utf-8") as stream:
            stream.write((str(result) if key == "PATH" else f"{key}={result}") + "\n")
            for name, value in extra.items():
                stream.write(f"{name}={value}\n")
    print(f"{key}={result}")
    for name, value in extra.items():
        print(f"{name}={value}")


if __name__ == "__main__":
    main()
