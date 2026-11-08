import copy
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from build_decoder import build, configure_options, linux_cross_environment, source_archive, validate_linux_toolchain, windows_runtime_licenses
from check_artifact import WINDOWS_RUNTIME_LICENSES, verify_bundle, verify_decoder_directory
from test_artifact import elf, pe, prepare_fonts


class DecoderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="neko-decoder-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source_bytes = b"pinned source fixture"
        self.source = {
            "url": "https://example.test/ffmpeg.tar.xz",
            "sha256": hashlib.sha256(self.source_bytes).hexdigest(),
            "patches": [{"file": "tls.patch", "sha256": hashlib.sha256(b"TLS patch fixture").hexdigest()}],
        }
        source_patch = patch("check_artifact.DECODER_SOURCE", self.source)
        source_patch.start()
        self.addCleanup(source_patch.stop)

    def package(self, target="linux-x64"):
        directory = self.root / "package" / target
        native = directory / "native"
        licenses = directory / "licenses/ffmpeg"
        native.mkdir(parents=True, exist_ok=True)
        licenses.mkdir(parents=True, exist_ok=True)
        windows = target.startswith("windows-")
        payload = {
            "linux-x64": elf(62), "linux-arm64": elf(183),
            "windows-x64": pe(0x8664), "windows-arm64": pe(0xAA64),
        }[target]
        names = [name + (".exe" if windows else "") for name in ("ffmpeg", "ffprobe")]
        for name in names:
            (native / name).write_bytes(payload)
        for name in ("COPYING.LGPLv2.1", "COPYING.LGPLv3", "LICENSE.md"):
            (licenses / name).write_text("license fixture")
        (licenses / "ffmpeg.tar.xz").write_bytes(self.source_bytes)
        (licenses / "tls.patch").write_bytes(b"TLS patch fixture")
        manifest = {
            "version": 1, "target": target, "source": self.source,
            "configure": configure_options(target, "/compiler/target-" if windows else "", "aarch64" if target.endswith("arm64") else "x86_64"),
            "binaries": {name: hashlib.sha256(payload).hexdigest() for name in names},
        }
        if windows:
            runtime = directory / "licenses/llvm-mingw"
            runtime.mkdir(parents=True, exist_ok=True)
            for name in WINDOWS_RUNTIME_LICENSES:
                (runtime / name).write_bytes(b"runtime license fixture")
            manifest["runtimeLicenses"] = {name: hashlib.sha256(b"runtime license fixture").hexdigest() for name in WINDOWS_RUNTIME_LICENSES}
        (licenses / "build-info.json").write_text(json.dumps(manifest))
        return directory

    def test_all_four_targets_include_network_probe_tempo_and_native_tls(self):
        for target in ("linux-x64", "linux-arm64", "windows-x64", "windows-arm64"):
            with self.subTest(target=target):
                options = configure_options(target, "/compiler/target-" if target.startswith("windows-") else "", "aarch64" if target.endswith("arm64") else "x86_64")
                for option in ("--enable-ffprobe", "--enable-ffmpeg", "--enable-network", "--enable-filter=aresample,aformat,anull,atrim,atempo", "--enable-protocol=file,pipe,http,https,tcp,tls,udp"):
                    self.assertIn(option, options)
                self.assertNotIn("--enable-nonfree", options)
                self.assertNotIn("--enable-gpl", options)
                self.assertEqual(len(verify_decoder_directory(target, self.package(target))), 2)

    def test_unusable_toolchain_and_cross_linked_linux_tls_are_rejected(self):
        for target, prefix, host in [
            ("linux-x86", "", "x86_64"),
            ("linux-arm64", "", "x86_64"),
            ("linux-x64", "", "aarch64"),
            ("windows-x64", "", "x86_64"),
            ("windows-arm64", "", "x86_64"),
        ]:
            with self.subTest(target=target):
                with self.assertRaises(ValueError):
                    configure_options(target, prefix, host)

    def cross_sysroot(self, machine=183):
        root = self.root / "sysroot"
        header = root / "usr/include/gnutls/gnutls.h"
        library = root / "usr/lib/aarch64-linux-gnu/libgnutls.so"
        header.parent.mkdir(parents=True, exist_ok=True)
        library.parent.mkdir(parents=True, exist_ok=True)
        header.write_text("target GnuTLS header")
        library.write_bytes(elf(machine))
        return root

    def test_explicit_linux_cross_options_keep_tls_enabled_and_select_target_tools(self):
        options = configure_options("linux-arm64", "/tools/aarch64-linux-gnu-", "x86_64", "/target")
        for option in ("--enable-gnutls", "--enable-cross-compile", "--target-os=linux", "--sysroot=/target", "--cross-prefix=/tools/aarch64-linux-gnu-", "--pkg-config=pkg-config"):
            self.assertIn(option, options)
        for target, prefix, root in (
            ("linux-arm64", "", "/target"),
            ("linux-arm64", "/tools/target-", None),
            ("linux-x64", "/tools/target-", None),
            ("windows-arm64", "/tools/target-", "/target"),
        ):
            with self.subTest(target=target, prefix=prefix, root=root):
                with self.assertRaises(ValueError):
                    configure_options(target, prefix, "x86_64", root)

    def test_linux_cross_tls_rejects_host_architecture_and_escaping_links(self):
        root = self.cross_sysroot(machine=62)
        with self.assertRaisesRegex(ValueError, "architecture"):
            linux_cross_environment("linux-arm64", root)
        library = root / "usr/lib/aarch64-linux-gnu/libgnutls.so"
        library.unlink()
        outside = self.root / "host-gnutls.so"
        outside.write_bytes(elf(183))
        library.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "escapes"):
            linux_cross_environment("linux-arm64", root)
        with self.assertRaises(ValueError):
            linux_cross_environment("windows-arm64", root)

    def test_linux_cross_pkg_config_and_compiler_environment_are_isolated(self):
        root = self.cross_sysroot()
        with patch.dict(os.environ, {"PKG_CONFIG_PATH": "/host/pkgconfig", "CFLAGS": "-I/host/include", "LDFLAGS": "-L/host/lib", "CPATH": "/host/include", "LIBRARY_PATH": "/host/lib"}):
            environment = linux_cross_environment("linux-arm64", root)
            self.assertEqual(os.environ["CPATH"], "/host/include")
        self.assertEqual(environment["PKG_CONFIG_PATH"], "")
        self.assertEqual(environment["PKG_CONFIG_SYSROOT_DIR"], str(root))
        directories = environment["PKG_CONFIG_LIBDIR"].split(os.pathsep)
        self.assertEqual(len(directories), 3)
        self.assertTrue(all(Path(directory).is_relative_to(root) for directory in directories))
        for variable in ("CFLAGS", "LDFLAGS", "CPATH", "LIBRARY_PATH"):
            self.assertNotIn(variable, environment)

    def test_linux_cross_preflight_rejects_mismatched_compiler_and_host_search_paths(self):
        root = self.cross_sysroot()
        environment = linux_cross_environment("linux-arm64", root)
        with patch("build_decoder.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "x86_64-linux-gnu\n")):
            with self.assertRaisesRegex(ValueError, "Compiler target"):
                validate_linux_toolchain("linux-arm64", "/tools/aarch64-linux-gnu-", root, environment)
        for flag in ("-I/usr/include", "-L/usr/lib", f"-I{root}/../host"):
            with self.subTest(flag=flag), patch("build_decoder.subprocess.run", side_effect=[
                subprocess.CompletedProcess([], 0, "aarch64-linux-gnu\n"),
                subprocess.CompletedProcess([], 0, flag),
            ]), patch("build_decoder.run") as compile_probe:
                with self.assertRaisesRegex(ValueError, "outside"):
                    validate_linux_toolchain("linux-arm64", "/tools/aarch64-linux-gnu-", root, environment)
                compile_probe.assert_not_called()

    def test_linux_cross_preflight_links_gnutls_and_checks_the_actual_probe_architecture(self):
        root = self.cross_sysroot()
        environment = linux_cross_environment("linux-arm64", root)
        def compile_probe(arguments, directory, actual_environment):
            self.assertIs(actual_environment, environment)
            self.assertIn("--sysroot=" + str(root), arguments)
            self.assertIn("-lgnutls", arguments)
            self.assertIn("gnutls_global_init", (Path(directory) / "probe.c").read_text())
            (Path(directory) / "probe").write_bytes(elf(machine))
        for machine in (183, 62):
            with self.subTest(machine=machine), patch("build_decoder.subprocess.run", side_effect=[
                subprocess.CompletedProcess([], 0, "aarch64-linux-gnu\n"),
                subprocess.CompletedProcess([], 0, shlex.quote("-I" + (root / "usr/include").as_posix()) + " -lgnutls"),
            ]), patch("build_decoder.run", side_effect=compile_probe):
                if machine == 183:
                    validate_linux_toolchain("linux-arm64", "/tools/aarch64-linux-gnu-", root, environment)
                else:
                    with self.assertRaisesRegex(ValueError, "architecture"):
                        validate_linux_toolchain("linux-arm64", "/tools/aarch64-linux-gnu-", root, environment)

    def test_source_download_is_checked_and_corrupt_cache_never_reused(self):
        cache = self.root / "cache"
        with patch("build_decoder.SOURCE", self.source):
            with patch("download.urllib.request.urlopen", return_value=io.BytesIO(self.source_bytes)) as download:
                archive = source_archive(cache)
                self.assertEqual(archive.read_bytes(), self.source_bytes)
                self.assertEqual(source_archive(cache), archive)
                download.assert_called_once()
            archive.write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "Cached.*checksum"):
                source_archive(cache)
            archive.unlink()
            with patch("download.urllib.request.urlopen", return_value=io.BytesIO(b"wrong download")):
                with self.assertRaisesRegex(ValueError, "Downloaded.*checksum"):
                    source_archive(cache)
            self.assertFalse(archive.exists())
            self.assertFalse(list(cache.glob("*.part")))

    def test_builder_uses_actual_platform_make_targets(self):
        work = self.root / "work"
        identity = hashlib.sha256(json.dumps(self.source, sort_keys=True).encode()).hexdigest()
        source = work / "source" / identity
        source.mkdir(parents=True)
        (source / ".nekoplayer-prepared").touch()
        calls = []
        def record(arguments, directory, environment=None):
            calls.append(arguments)
            if arguments[0] == "make":
                raise RuntimeError("stop after make command")
        for target in ("linux-x64", "windows-x64", "windows-arm64"):
            with self.subTest(target=target), patch("build_decoder.SOURCE", self.source), patch("build_decoder.platform.system", return_value="Linux"), patch("build_decoder.platform.machine", return_value="x86_64"), patch("build_decoder.source_archive", return_value=self.root / "archive.tar.xz"), patch("build_decoder.windows_runtime_licenses", return_value={}), patch("build_decoder.run", side_effect=record):
                with self.assertRaisesRegex(RuntimeError, "stop after make"):
                    build(target, work, "/tools/target-" if target.startswith("windows-") else "")
                suffix = ".exe" if target.startswith("windows-") else ""
                self.assertEqual(calls[-1], ["make", "-j2", "ffmpeg" + suffix, "ffprobe" + suffix])

    def test_windows_runtime_licenses_are_selected_per_architecture_and_required(self):
        root = self.root / "llvm"
        compiler = root / "bin/clang"
        compiler.parent.mkdir(parents=True)
        compiler.touch()
        (root / "LICENSE.TXT").write_text("LLVM license")
        for triplet in ("x86_64-w64-mingw32", "aarch64-w64-mingw32"):
            runtime = root / triplet / "share/mingw32"
            runtime.mkdir(parents=True)
            for name in WINDOWS_RUNTIME_LICENSES[1:]:
                (runtime / name).write_text(triplet)
        with patch("build_decoder.shutil.which", return_value=str(compiler)):
            for target, triplet in (("windows-x64", "x86_64-w64-mingw32"), ("windows-arm64", "aarch64-w64-mingw32")):
                paths = windows_runtime_licenses(target, "/llvm/bin/target-")
                self.assertEqual(set(paths), set(WINDOWS_RUNTIME_LICENSES))
                self.assertIn(triplet, str(paths["COPYING"]))
            (root / "LICENSE.TXT").unlink()
            with self.assertRaisesRegex(ValueError, "Missing.*runtime license"):
                windows_runtime_licenses("windows-x64", "/llvm/bin/target-")

    def test_windows_decoder_packages_require_untampered_runtime_licenses(self):
        for mutation in ("missing-manifest", "missing-file", "modified"):
            with self.subTest(mutation=mutation):
                directory = self.package("windows-arm64")
                manifest_path = directory / "licenses/ffmpeg/build-info.json"
                license_file = directory / "licenses/llvm-mingw/LLVM-LICENSE.TXT"
                if mutation == "missing-manifest":
                    manifest = json.loads(manifest_path.read_text())
                    manifest.pop("runtimeLicenses")
                    manifest_path.write_text(json.dumps(manifest))
                elif mutation == "missing-file":
                    license_file.unlink()
                else:
                    license_file.write_text("tampered runtime license")
                with self.assertRaises((ValueError, OSError)):
                    verify_decoder_directory("windows-arm64", directory)

    def test_missing_probe_wrong_architecture_and_tampered_content_are_rejected(self):
        for mutation in ("missing", "wrong-arch", "checksum", "source", "license", "patch"):
            with self.subTest(mutation=mutation):
                directory = self.package()
                if mutation == "missing":
                    (directory / "native/ffprobe").unlink()
                elif mutation == "wrong-arch":
                    (directory / "native/ffprobe").write_bytes(elf(183))
                elif mutation == "checksum":
                    with (directory / "native/ffmpeg").open("ab") as binary:
                        binary.write(b"modified")
                elif mutation == "source":
                    (directory / "licenses/ffmpeg/ffmpeg.tar.xz").write_bytes(b"modified")
                elif mutation == "license":
                    (directory / "licenses/ffmpeg/LICENSE.md").unlink()
                else:
                    (directory / "licenses/ffmpeg/tls.patch").write_bytes(b"tampered")
                with self.assertRaises((ValueError, OSError)):
                    verify_decoder_directory("linux-x64", directory)

    def test_manifest_cannot_claim_other_source_or_omit_decoder_capabilities(self):
        directory = self.package()
        manifest_path = directory / "licenses/ffmpeg/build-info.json"
        original = json.loads(manifest_path.read_text())
        for key, value in [
            ("target", "windows-x64"), ("source", {}), ("version", 0),
            ("configure", None), ("binaries", []),
            ("configure", [option for option in original["configure"] if option != "--enable-ffprobe"]),
            ("configure", [option for option in original["configure"] if option != "--enable-gnutls"]),
            ("configure", [*original["configure"], "--disable-network"]),
        ]:
            with self.subTest(key=key, value=value):
                manifest = copy.deepcopy(original)
                manifest[key] = value
                manifest_path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    verify_decoder_directory("linux-x64", directory)
        manifest_path.write_text("[]")
        with self.assertRaises(ValueError):
            verify_decoder_directory("linux-x64", directory)

    def test_complete_bundle_can_require_decoder_package(self):
        directory = self.package()
        prepare_fonts(directory)
        for name in ("nekoplayer", "lib/libflutter_linux_gtk.so", "lib/libnekoplayer_dsp.so", "lib/libnekoplayer_plugins.so", "lib/libapp.so", "data/icudtl.dat", "data/flutter_assets/AssetManifest.bin"):
            destination = directory / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(elf(62))
        self.assertEqual(len(verify_bundle("linux-x64", directory, require_decoders=True)), 7)
        (directory / "native/ffprobe").unlink()
        with self.assertRaises(OSError):
            verify_bundle("linux-x64", directory, require_decoders=True)

    @unittest.skipUnless(shutil.which("cmake"), "CMake is required")
    def test_cmake_checks_and_installs_decoder_resources_with_permissions(self):
        directory = self.package()
        for binary in (directory / "native").iterdir():
            binary.chmod(0o755)
        project = self.root / "project"
        (project / "native").mkdir(parents=True)
        (project / "tool").mkdir()
        original = Path(__file__).resolve().parents[1]
        shutil.copy2(original / "native/decoder.cmake", project / "native/decoder.cmake")
        shutil.copy2(original / "tool/check_artifact.py", project / "tool/check_artifact.py")
        (project / "native/decoder.json").write_text(json.dumps(self.source))
        (project / "CMakeLists.txt").write_text('cmake_minimum_required(VERSION 3.14)\nproject(test NONE)\ninclude(native/decoder.cmake)\n')
        build = self.root / "build"
        install = self.root / "install"
        result = subprocess.run([
            "cmake", "-S", str(project), "-B", str(build),
            "-DFLUTTER_TARGET_PLATFORM=linux-x64", f"-DNEKO_DECODER_DIR={directory}",
            f"-DCMAKE_INSTALL_PREFIX={install}", "-DNEKO_REQUIRE_DECODERS=ON",
        ], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        subprocess.run(["cmake", "--install", str(build)], capture_output=True, check=True, timeout=15)
        verify_decoder_directory("linux-x64", install)
        if os.name != "nt":
            self.assertTrue((install / "native/ffprobe").stat().st_mode & 0o111)
        for target in ("linux-arm64", "windows-x64"):
            result = subprocess.run(["cmake", "-S", str(project), "-B", str(build), f"-DFLUTTER_TARGET_PLATFORM={target}"], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Invalid decoder package", result.stderr)
        result = subprocess.run(["cmake", "-S", str(project), "-B", str(build), "-DNEKO_DECODER_DIR="], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires NEKO_DECODER_DIR", result.stderr)
        result = subprocess.run(["cmake", "-S", str(project), "-B", str(build), f"-DNEKO_DECODER_DIR={build}"], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the generated platform build", result.stderr)


if __name__ == "__main__":
    unittest.main()
