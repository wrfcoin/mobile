"""Static check: no APK this repo ships is debuggable (audit 2026-11-16 B2).

Flutter's Gradle plugin builds "profile" with initWith(debug), so profile is
debuggable unless android/app/build.gradle.kts turns it off. A debuggable
wallet APK lets `adb run-as` read the app's private files.
"""

import pathlib
import re
import unittest

GRADLE = pathlib.Path(__file__).resolve().parents[2] / "android" / "app" / "build.gradle.kts"


def build_type_block(text: str, opener: str) -> str:
    start = text.find(opener)
    if start < 0:
        return ""
    depth = 0
    for i in range(text.index("{", start), len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return ""


class AndroidBuildTypesTest(unittest.TestCase):
    def setUp(self):
        text = GRADLE.read_text()
        self.build_types = build_type_block(text, "buildTypes {")
        self.assertTrue(self.build_types, "buildTypes block not found")

    def assert_not_debuggable(self, opener: str):
        block = build_type_block(self.build_types, opener)
        self.assertTrue(block, f"{opener!r} not found in buildTypes")
        self.assertRegex(block, r"\bisDebuggable\s*=\s*false\b")
        self.assertNotRegex(block, r"\bisDebuggable\s*=\s*true\b")

    def test_release_is_not_debuggable(self):
        self.assert_not_debuggable("release {")

    def test_profile_is_not_debuggable(self):
        self.assert_not_debuggable('maybeCreate("profile")')

    def test_nothing_turns_debuggable_on_outside_debug(self):
        self.assertIsNone(re.search(r"isDebuggable\s*=\s*true", self.build_types))


if __name__ == "__main__":
    unittest.main()
