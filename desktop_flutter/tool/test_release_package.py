from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from package_release import release_version, stage_windows_runtime, windows_installer_script
from test_artifact import elf, pe


class ReleasePackageTests(unittest.TestCase):
    def test_android_and_desktop_versions_match(self):
        self.assertRegex(release_version(), r"^\d+\.\d+\.\d+(-pre)?$")

    def test_prerelease_uses_tilde_for_linux_packages(self):
        from package_release import package_version
        self.assertEqual(package_version("1.2.0-pre"), "1.2.0~pre")
        self.assertEqual(package_version("1.2.0"), "1.2.0")

    def test_windows_installers_have_separate_native_architectures(self):
        for target, arch in (("windows-x64", "x64compatible"), ("windows-arm64", "arm64")):
            with self.subTest(target=target), patch("package_release.release_version", return_value="1.1.0"):
                script = windows_installer_script(target, Path("payload"), Path("output"))
                self.assertIn(f"ArchitecturesAllowed={arch}\n", script)
                self.assertIn(f"OutputBaseFilename=NekoPlayer-v1.1.0-{target}-setup", script)
                self.assertIn("UninstallDisplayIcon={app}\\NekoPlayer.exe", script)
                self.assertNotIn("java", script.lower())

    def test_linux_packages_declare_either_libmpv_soname(self):
        source = Path(__file__).with_name("package_release.py").read_text(encoding="utf-8")
        self.assertIn("libmpv2 | libmpv1", source)
        self.assertIn("(mpv-libs or libmpv2)", source)

    def test_linux_staging_drops_the_jni_helper(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "bundle"
            (bundle / "lib").mkdir(parents=True)
            (bundle / "lib/libdartjni.so").write_bytes(elf(62))
            (bundle / "lib/libkeep.so").write_bytes(elf(62))
            staged = []
            with patch("package_release.verify_bundle", side_effect=lambda *a, **k: staged.append(k.get("packaged", False))), \
                    patch("package_release.release_version", return_value="1.1.0"):
                from package_release import stage_bundle
                payload = stage_bundle("linux-x64", bundle, Path(temporary) / "staging")
            self.assertFalse((payload / "lib/libdartjni.so").exists())
            self.assertTrue((payload / "lib/libkeep.so").is_file())
            self.assertEqual(staged, [False, True])

    def runtime_fixture(self, root, arch, machine):
        runtime = root / arch / "Microsoft.VC145.CRT"
        runtime.mkdir(parents=True)
        for name in ("msvcp140.dll", "vcruntime140.dll"):
            (runtime / name).write_bytes(pe(machine))
        payload = root / "payload"
        payload.mkdir()
        (payload / "NekoPlayer.exe").write_bytes(pe(machine))
        return runtime, payload

    def test_windows_runtime_only_stages_native_architecture_and_checks_imports(self):
        for arch, machine in (("x64", 0x8664), ("arm64", 0xAA64)):
            with self.subTest(arch=arch), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                runtime, payload = self.runtime_fixture(root, arch, machine)
                (runtime / "vcruntime140_1.dll").write_bytes(pe(0x8664))
                output = "    KERNEL32.dll\n    MSVCP140.dll\n    VCRUNTIME140.dll\n"
                with patch("package_release.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output)) as inspect:
                    stage_windows_runtime("windows-" + arch, root, payload)
                self.assertEqual((payload / "vcruntime140_1.dll").exists(), arch == "x64")
                self.assertEqual(inspect.call_count, len(list(payload.glob("*"))))
                self.assertTrue((payload / "msvcp140.dll").is_file())

    def test_windows_runtime_rejects_unfulfilled_native_imports(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, payload = self.runtime_fixture(root, "arm64", 0xAA64)
            (runtime / "vcruntime140_1.dll").write_bytes(pe(0x8664))
            with patch("package_release.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "    VCRUNTIME140_1.dll\n")):
                with self.assertRaisesRegex(ValueError, "requires missing.*vcruntime140_1.dll"):
                    stage_windows_runtime("windows-arm64", root, payload)

    def test_windows_runtime_rejects_wrong_architecture_core_libraries(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, payload = self.runtime_fixture(root, "arm64", 0xAA64)
            (runtime / "msvcp140.dll").write_bytes(pe(0x8664))
            with self.assertRaisesRegex(ValueError, "redistributables are missing"):
                stage_windows_runtime("windows-arm64", root, payload)


if __name__ == "__main__":
    unittest.main()
