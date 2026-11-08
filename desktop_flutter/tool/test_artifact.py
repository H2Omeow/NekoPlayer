from pathlib import Path
import json
import shutil
import struct
import tempfile
import unittest

from check_artifact import architecture, elf_needed, font_source, verify, verify_bundle, verify_font_bundle

FONT_SOURCE = font_source()


def prepare_fonts(directory):
    assets = Path(directory) / "data/flutter_assets"
    project = Path(__file__).resolve().parents[1]
    for kind in ("font", "license"):
        name = FONT_SOURCE[kind]["asset"]
        destination = assets / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / name, destination)
    (assets / "FontManifest.json").write_text(json.dumps([
        {"family": FONT_SOURCE["family"], "fonts": [{"asset": FONT_SOURCE["font"]["asset"]}]},
    ]))


def elf(machine, bits=2):
    header = bytearray(64)
    header[:6] = b"\x7fELF" + bytes([bits, 1])
    struct.pack_into("<H", header, 18, machine)
    return header


def elf_with_needed(machine, names):
    """Minimal ELF64 with PT_LOAD + PT_DYNAMIC listing the given DT_NEEDED entries."""
    strings = b"\0" + b"".join(name.encode() + b"\0" for name in names)
    offsets, position = [], 1
    for name in names:
        offsets.append(position)
        position += len(name) + 1
    dynamic = b"".join(struct.pack("<qQ", 1, offset) for offset in offsets)
    strtab_at = 64 + 56 * 2
    dynamic_at = strtab_at + len(strings)
    dynamic += struct.pack("<qQ", 5, strtab_at) + struct.pack("<qQ", 0, 0)
    data = bytearray(elf(machine))
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HHH", data, 54, 56, 2, 0)
    data += struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, dynamic_at + len(dynamic), dynamic_at + len(dynamic), 0x1000)
    data += struct.pack("<IIQQQQQQ", 2, 6, dynamic_at, dynamic_at, dynamic_at, len(dynamic), len(dynamic), 8)
    return bytes(data + strings + dynamic)


def pe(machine, magic=0x20B):
    header = bytearray(154)
    header[:2] = b"MZ"
    struct.pack_into("<I", header, 60, 128)
    header[128:132] = b"PE\x00\x00"
    struct.pack_into("<H", header, 132, machine)
    struct.pack_into("<H", header, 152, magic)
    return header


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.binary = Path(self.directory.name) / "player"

    def test_all_four_64_bit_targets(self):
        for target, data in {
            "linux-x64": elf(62),
            "linux-arm64": elf(183),
            "windows-x64": pe(0x8664),
            "windows-arm64": pe(0xAA64),
        }.items():
            with self.subTest(target=target):
                self.binary.write_bytes(data)
                verify(target, [self.binary])

    def test_mislabeled_architecture_is_rejected(self):
        self.binary.write_bytes(elf(62))
        with self.assertRaises(ValueError):
            verify("linux-arm64", [self.binary])

    def test_32_bit_binaries_are_rejected(self):
        for data in [elf(3, 1), pe(0x14C, 0x10B), pe(0x1C4, 0x10B)]:
            self.binary.write_bytes(data)
            with self.assertRaises(ValueError):
                architecture(self.binary)

    def test_broken_headers_are_rejected(self):
        for data in [b"", b"PK" + bytes(64), b"MZ" + bytes(62)]:
            self.binary.write_bytes(data)
            with self.assertRaises(ValueError):
                architecture(self.binary)

    def test_native_libraries_are_also_checked(self):
        library = self.binary.with_suffix(".so")
        self.binary.write_bytes(elf(183))
        library.write_bytes(elf(62))
        with self.assertRaises(ValueError):
            verify("linux-arm64", [self.binary, library])

    def prepare_bundle(self, target):
        root = Path(self.directory.name) / target
        windows = target.startswith("windows-")
        arm64 = target.endswith("arm64")
        payload = pe(0xAA64 if arm64 else 0x8664) if windows else elf(183 if arm64 else 62)
        for name in [
            "NekoPlayer.exe" if windows else "nekoplayer",
            "flutter_windows.dll" if windows else "lib/libflutter_linux_gtk.so",
            "nekoplayer_dsp.dll" if windows else "lib/libnekoplayer_dsp.so",
            "nekoplayer_plugins.dll" if windows else "lib/libnekoplayer_plugins.so",
            "data/app.so" if windows else "lib/libapp.so",
            "data/icudtl.dat",
            "data/flutter_assets/AssetManifest.bin",
        ]:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(elf(183 if arm64 else 62) if name == "data/app.so" else payload)
        prepare_fonts(root)
        return root

    def test_font_and_license_are_required_and_verified(self):
        for kind in ("font", "license"):
            with self.subTest(kind=kind):
                root = self.prepare_bundle("linux-arm64")
                asset = root / "data/flutter_assets" / FONT_SOURCE[kind]["asset"]
                asset.unlink()
                with self.assertRaisesRegex(ValueError, "Missing bundled"):
                    verify_bundle("linux-arm64", root)
                asset.write_bytes(b"corrupt")
                with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                    verify_font_bundle(root)

    def test_font_must_be_registered_with_the_correct_family_and_asset(self):
        root = self.prepare_bundle("windows-arm64")
        manifest = root / "data/flutter_assets/FontManifest.json"
        for data in [[], {}, [{"family": "Neko CJK", "fonts": []}],
                     [{"family": "wrong", "fonts": [{"asset": FONT_SOURCE["font"]["asset"]}]}]]:
            with self.subTest(data=data):
                manifest.write_text(json.dumps(data))
                with self.assertRaisesRegex(ValueError, "not registered"):
                    verify_bundle("windows-arm64", root)

    def test_complete_bundles_and_missing_components(self):
        for target in ("linux-arm64", "windows-arm64"):
            with self.subTest(target=target):
                root = self.prepare_bundle(target)
                self.assertEqual(len(verify_bundle(target, root)), 5)
                (root / "data/icudtl.dat").unlink()
                with self.assertRaisesRegex(ValueError, "Missing bundle"):
                    verify_bundle(target, root)

    def test_missing_aot_library_is_rejected(self):
        for target, name in [
            ("linux-arm64", "lib/libapp.so"),
            ("windows-arm64", "data/app.so"),
        ]:
            with self.subTest(target=target):
                root = self.prepare_bundle(target)
                (root / name).unlink()
                with self.assertRaisesRegex(ValueError, "Missing bundle"):
                    verify_bundle(target, root)

    def test_windows_aot_is_elf_not_pe(self):
        for target in ("windows-x64", "windows-arm64"):
            with self.subTest(target=target):
                root = self.prepare_bundle(target)
                self.assertEqual(len(verify_bundle(target, root)), 5)
                (root / "data/app.so").write_bytes(pe(0xAA64 if target.endswith("arm64") else 0x8664))
                with self.assertRaisesRegex(ValueError, "does not match"):
                    verify_bundle(target, root)

    def test_bundle_detects_mixed_architecture_nested_native_files(self):
        for target, name, payload in [
            ("linux-arm64", "lib/libmpv.so.2", elf(62)),
            ("windows-arm64", "nested/libEGL.dll", pe(0x8664)),
            ("linux-arm64", "native/ffprobe", elf(62)),
            ("windows-arm64", "native/ffmpeg.exe", pe(0x8664)),
            ("linux-arm64", "lib/libapp.so", elf(62)),
            ("windows-arm64", "data/app.so", pe(0x8664)),
        ]:
            with self.subTest(target=target, name=name):
                root = self.prepare_bundle(target)
                extra = root / name
                extra.parent.mkdir(parents=True, exist_ok=True)
                extra.write_bytes(payload)
                with self.assertRaisesRegex(ValueError, "does not match"):
                    verify_bundle(target, root)
                extra.unlink()

    def test_linux_dependencies_are_read_from_the_dynamic_section(self):
        self.binary.write_bytes(elf_with_needed(62, ["libc.so.6", "libgtk-3.so.0"]))
        self.assertEqual(elf_needed(self.binary), ["libc.so.6", "libgtk-3.so.0"])
        self.binary.write_bytes(elf(62))
        self.assertEqual(elf_needed(self.binary), [])

    def test_linux_bundle_accepts_bundled_and_allowlisted_dependencies(self):
        root = self.prepare_bundle("linux-x64")
        plugin = root / "lib/libmedia_kit_video_plugin.so"
        plugin.write_bytes(elf_with_needed(62, ["libflutter_linux_gtk.so", "libgtk-3.so.0", "libepoxy.so.0", "libc.so.6"]))
        self.assertEqual(len(verify_bundle("linux-x64", root)), 6)

    def test_linux_bundle_rejects_hard_linked_runtime_libraries(self):
        for name in ("libmpv.so.1", "libmpv.so.2", "libjvm.so", "libwebkit2gtk-4.1.so.0", "libayatana-appindicator3.so.1"):
            with self.subTest(name=name):
                root = self.prepare_bundle("linux-x64")
                (root / "lib/libmedia_kit_video_plugin.so").write_bytes(elf_with_needed(62, ["libc.so.6", name]))
                with self.assertRaisesRegex(ValueError, "dlopen"):
                    verify_bundle("linux-x64", root)

    def test_linux_bundle_rejects_unknown_system_libraries(self):
        root = self.prepare_bundle("linux-x64")
        (root / "lib/libnekoplayer_dsp.so").write_bytes(elf_with_needed(62, ["libsurprise.so.7"]))
        with self.assertRaisesRegex(ValueError, "libsurprise.so.7"):
            verify_bundle("linux-x64", root)

    def test_executable_may_depend_on_bundled_plugins(self):
        root = self.prepare_bundle("linux-x64")
        (root / "lib/libfoo_plugin.so").write_bytes(elf(62))
        (root / "nekoplayer").write_bytes(elf_with_needed(62, ["libfoo_plugin.so", "libm.so.6"]))
        verify_bundle("linux-x64", root)

    def test_jni_helper_is_tolerated_in_build_output_but_rejected_in_packages(self):
        root = self.prepare_bundle("linux-x64")
        (root / "lib/libdartjni.so").write_bytes(elf_with_needed(62, ["libjvm.so"]))
        verify_bundle("linux-x64", root)
        with self.assertRaisesRegex(ValueError, "libdartjni.so"):
            verify_bundle("linux-x64", root, packaged=True)


if __name__ == "__main__":
    unittest.main()
