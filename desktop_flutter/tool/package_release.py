import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

from check_artifact import DESKTOP_EXCLUDED_LIBRARIES, TARGETS, architecture, verify_bundle


ROOT = Path(__file__).resolve().parents[1]
HOMEPAGE = "https://github.com/H2Omeow/NekoPlayer"


def release_version():
    match = re.search(r"^version: (\d+\.\d+\.\d+(?:-pre(?:\.\d+)?)?)\+(\d+)$", (ROOT / "pubspec.yaml").read_text(), re.MULTILINE)
    if not match:
        raise ValueError("A stable or prerelease Flutter version and build number are required")
    version, build = match.groups()
    android = dict(line.split("=", 1) for line in (ROOT.parent / "app/version.properties").read_text().splitlines() if "=" in line)
    if android.get("versionName") != version or android.get("versionCode") != build:
        raise ValueError("Android and Flutter release versions must match")
    return version


def package_version(version):
    # DEB / RPM reject "-" in versions; "~" also sorts 1.2.0~pre before 1.2.0.
    return version.replace("-", "~")


def run(arguments):
    subprocess.run(list(map(str, arguments)), check=True)


def stage_bundle(target, bundle, staging):
    verify_bundle(target, bundle, require_decoders=True)
    shutil.copytree(bundle, staging, symlinks=True, ignore=shutil.ignore_patterns(*DESKTOP_EXCLUDED_LIBRARIES))
    verify_bundle(target, staging, require_decoders=True, packaged=True)
    (staging / "release-info.json").write_text(json.dumps({
        "version": release_version(), "target": target,
        "commit": os.environ.get("GITHUB_SHA", subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()),
        "desktop": "Flutter",
    }, indent=2) + "\n")
    license_file = ROOT.parent / "LICENSE"
    if license_file.is_file():
        shutil.copy2(license_file, staging / "LICENSE")
    return staging


def linux_packages(target, bundle, output):
    version = release_version()
    arm64 = target.endswith("arm64")
    deb_arch, rpm_arch = ("arm64", "aarch64") if arm64 else ("amd64", "x86_64")
    basename = f"NekoPlayer-v{version}-{target}"
    with tempfile.TemporaryDirectory(prefix="nekoplayer-package-") as temporary:
        work = Path(temporary)
        payload = stage_bundle(target, bundle, work / "NekoPlayer")
        (payload / "NekoPlayer").write_text('#!/bin/sh\ncd -- "$(dirname -- "$(readlink -f -- "$0")")" || exit 1\nexec ./nekoplayer "$@"\n')
        (payload / "NekoPlayer").chmod(0o755)
        with tarfile.open(output / (basename + ".tar.gz"), "w:gz") as archive:
            archive.add(payload, arcname="NekoPlayer")
        package = work / "package"
        library = package / "usr/lib/nekoplayer"
        library.parent.mkdir(parents=True)
        shutil.copytree(payload, library, symlinks=True)
        launcher = package / "usr/bin/nekoplayer"
        launcher.parent.mkdir(parents=True)
        launcher.write_text('#!/bin/sh\nexec /usr/lib/nekoplayer/nekoplayer "$@"\n')
        launcher.chmod(0o755)
        desktop = package / "usr/share/applications/top.nekoh2o.nekoplayer_desktop.desktop"
        desktop.parent.mkdir(parents=True)
        desktop.write_text("[Desktop Entry]\nType=Application\nName=NekoPlayer\nComment=Music player\nExec=nekoplayer %U\nIcon=nekoplayer\nTerminal=false\nCategories=AudioVideo;Audio;Player;\nStartupWMClass=top.nekoh2o.nekoplayer_desktop\nMimeType=x-scheme-handler/nekoplayer;\n")
        icon = package / "usr/share/icons/hicolor/192x192/apps/nekoplayer.png"
        icon.parent.mkdir(parents=True)
        shutil.copy2(ROOT.parent / "app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", icon)
        control = package / "DEBIAN/control"
        control.parent.mkdir()
        control.write_text(
            f"Package: nekoplayer\nVersion: {package_version(version)}\nArchitecture: {deb_arch}\n"
            "Maintainer: H2Omeow\nSection: sound\nPriority: optional\n"
            "Depends: libgtk-3-0, libmpv2 | libmpv1, libsecret-1-0, libepoxy0, libegl1, libgles2, libgnutls30, libgtk-layer-shell0\n"
            "Recommends: libwebkit2gtk-4.1-0\n"
            f"Homepage: {HOMEPAGE}\nDescription: NekoPlayer Flutter music player\n"
        )
        postinst = package / "DEBIAN/postinst"
        postinst.write_text(
            "#!/bin/sh\n"
            "if command -v update-desktop-database >/dev/null 2>&1; then "
            "update-desktop-database -q /usr/share/applications || true; fi\n"
            "if command -v xdg-mime >/dev/null 2>&1; then "
            "xdg-mime default top.nekoh2o.nekoplayer_desktop.desktop x-scheme-handler/nekoplayer || true; fi\n"
            "exit 0\n"
        )
        postinst.chmod(0o755)
        run(["dpkg-deb", "--root-owner-group", "--build", package, output / (basename + ".deb")])
        shutil.rmtree(package / "DEBIAN")
        rpmbuild = work / "rpm"
        for directory in ("BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"):
            (rpmbuild / directory).mkdir(parents=True)
        spec = rpmbuild / "SPECS/nekoplayer.spec"
        spec.write_text(
            f"Name: nekoplayer\nVersion: {package_version(version)}\nRelease: 1\nSummary: NekoPlayer Flutter music player\n"
            f"License: LicenseRef-NekoPlayer\nURL: {HOMEPAGE}\nBuildArch: {rpm_arch}\nAutoReqProv: no\n"
            "Requires: gtk3, (mpv-libs or libmpv2), libsecret, libepoxy, libglvnd-egl, libglvnd-gles, gnutls, gtk-layer-shell\n"
            "Recommends: webkit2gtk4.1\n"
            "%description\nNekoPlayer Flutter music player.\n"
            f'%install\nmkdir -p "%{{buildroot}}"\ncp -a "{package}/usr" "%{{buildroot}}/"\n'
            "%post\n"
            "if command -v update-desktop-database >/dev/null 2>&1; then "
            "update-desktop-database -q /usr/share/applications || :; fi\n"
            "if command -v xdg-mime >/dev/null 2>&1; then "
            "xdg-mime default top.nekoh2o.nekoplayer_desktop.desktop x-scheme-handler/nekoplayer || :; fi\n"
            "%files\n/usr/bin/nekoplayer\n/usr/lib/nekoplayer\n/usr/share/applications/top.nekoh2o.nekoplayer_desktop.desktop\n/usr/share/icons/hicolor/192x192/apps/nekoplayer.png\n"
        )
        run(["rpmbuild", "--define", f"_topdir {rpmbuild}", "--define", "__os_install_post %{nil}", "--define", "_build_id_links none", "--target", rpm_arch, "-bb", spec])
        packages = list((rpmbuild / "RPMS").rglob("*.rpm"))
        if len(packages) != 1:
            raise ValueError("Expected exactly one RPM")
        shutil.copy2(packages[0], output / (basename + ".rpm"))


def windows_installer_script(target, payload, output):
    version = release_version()
    arch = "arm64" if target.endswith("arm64") else "x64compatible"
    return rf'''[Setup]
AppId=NekoPlayer
AppName=NekoPlayer
AppVersion={version}
AppPublisher=H2Omeow
AppPublisherURL={HOMEPAGE}
DefaultDirName={{localappdata}}\Programs\NekoPlayer
DefaultGroupName=NekoPlayer
PrivilegesRequired=lowest
ArchitecturesAllowed={arch}
ArchitecturesInstallIn64BitMode={arch}
OutputDir={output}
OutputBaseFilename=NekoPlayer-v{version}-{target}-setup
SetupIconFile={ROOT / "windows/runner/resources/app_icon.ico"}
UninstallDisplayIcon={{app}}\NekoPlayer.exe
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{payload}\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{{group}}\NekoPlayer"; Filename: "{{app}}\NekoPlayer.exe"
Name: "{{autodesktop}}\NekoPlayer"; Filename: "{{app}}\NekoPlayer.exe"; Tasks: desktopicon
[Registry]
Root: HKCU; Subkey: "Software\Classes\nekoplayer"; ValueType: string; ValueName: ""; ValueData: "URL:NekoPlayer protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\nekoplayer"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\nekoplayer\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{{app}}\NekoPlayer.exe,0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\nekoplayer\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{{app}}\NekoPlayer.exe"" ""%1"""; Flags: uninsdeletekey
[Run]
Filename: "{{app}}\NekoPlayer.exe"; Description: "Launch NekoPlayer"; Flags: nowait postinstall skipifsilent
'''


def stage_windows_runtime(target, redist, payload):
    arch = "arm64" if target.endswith("arm64") else "x64"
    libraries = {
        library.name.lower(): library
        for library in sorted((redist / arch).glob("Microsoft.VC*.CRT/*.dll"))
        if architecture(library) == TARGETS[target]
    }
    required = {"msvcp140.dll", "vcruntime140.dll"}
    if not required <= libraries.keys():
        raise ValueError(f"Native Visual C++ runtime redistributables are missing: {required - libraries.keys()}")
    for library in libraries.values():
        shutil.copy2(library, payload / library.name)
    for binary in payload.rglob("*"):
        if binary.suffix.lower() not in (".dll", ".exe"):
            continue
        output = subprocess.run(["dumpbin.exe", "/nologo", "/dependents", str(binary)],
                                check=True, capture_output=True, text=True, errors="replace").stdout
        dependencies = set(re.findall(r"^\s+((?:vcruntime|msvcp|concrt|vccorlib)[\w.-]*\.dll)\s*$",
                                      output.lower(), re.MULTILINE))
        missing = dependencies - libraries.keys()
        if missing:
            raise ValueError(f"{binary.name} requires missing native Visual C++ runtime libraries: {sorted(missing)}")


def windows_package(target, bundle, output):
    with tempfile.TemporaryDirectory(prefix="nekoplayer-package-") as temporary:
        work = Path(temporary)
        payload = stage_bundle(target, bundle, work / "NekoPlayer")
        redist = Path(os.environ["VCToolsRedistDir"])
        stage_windows_runtime(target, redist, payload)
        verify_bundle(target, payload, require_decoders=True)
        source = work / "setup.iss"
        source.write_text(windows_installer_script(target, payload, output), encoding="utf-8-sig")
        run([os.environ["NEKO_ISCC"], source])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=TARGETS)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "build/dist")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.target.startswith("linux-"):
        linux_packages(args.target, args.bundle.resolve(), output)
    else:
        windows_package(args.target, args.bundle.resolve(), output)


if __name__ == "__main__":
    main()
