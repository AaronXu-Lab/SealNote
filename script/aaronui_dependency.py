#!/usr/bin/env python3
"""Switch Seal Note's shared AaronUI package between a local checkout and GitHub."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "SealNote.xcodeproj/project.pbxproj"
REFERENCE = "B886DBD3306938A000C092B6"
URL = "https://github.com/AaronXu-Lab/AaronUI-SwiftUI.git"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", choices=["local", "github"])
    parser.add_argument("--path", default="../AaronUI-SwiftUI", help="Local package path relative to SealNote's root")
    parser.add_argument("--version", default="0.4.2", help="Minimum GitHub version (original requirement: 0.4.2)")
    args = parser.parse_args()
    if args.source == "local":
        package = (ROOT / args.path).resolve()
        if not (package / "Package.swift").is_file():
            parser.error(f"No Package.swift found at {package}")
        # Xcode's quoted pbxproj values use backslash escapes.
        path = args.path.replace("\\", "\\\\").replace('"', '\\"')
        if "\n" in path or "\r" in path:
            parser.error("Package path must not contain newlines")
        kind = "XCLocalSwiftPackageReference"
        body = f'\t\t\tisa = {kind};\n\t\t\trelativePath = "{path}";\n'
    else:
        if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
            parser.error("Version must use X.Y.Z format")
        kind = "XCRemoteSwiftPackageReference"
        body = (f'\t\t\tisa = {kind};\n\t\t\trepositoryURL = "{URL}";\n'
                '\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n'
                f'\t\t\t\tminimumVersion = {args.version};\n\t\t\t}};\n')

    source = PROJECT.read_text()
    pattern = rf'\t\t{REFERENCE} /\* XC(?:Remote|Local)SwiftPackageReference "AaronUI-SwiftUI" \*/ = \{{\n.*?\n\t\t\}};\n'
    source, count = re.subn(pattern, "", source, flags=re.S)
    if count != 1:
        parser.error(f"Expected one AaronUI package declaration; found {count}. Project left unchanged.")
    source = re.sub(rf'({REFERENCE} /\* )XC(?:Remote|Local)SwiftPackageReference', rf'\g<1>{kind}', source)
    declaration = f'\t\t{REFERENCE} /* {kind} "AaronUI-SwiftUI" */ = {{\n{body}\t\t}};\n'
    end = f"/* End {kind} section */"
    if end in source:
        source = source.replace(end, declaration + end, 1)
    else:
        marker = "/* Begin XCRemoteSwiftPackageReference section */"
        if marker not in source:
            parser.error("Cannot find the package section. Project left unchanged.")
        source = source.replace(marker, f"/* Begin {kind} section */\n{declaration}{end}\n\n{marker}", 1)
    source = re.sub(r'/\* Begin XCLocalSwiftPackageReference section \*/\n/\* End XCLocalSwiftPackageReference section \*/\n\n', '', source)
    PROJECT.write_text(source)
    print(f"AaronUI source: {args.source} ({args.path if args.source == 'local' else args.version + ' ..< ' + str(int(args.version.split('.')[0]) + 1) + '.0.0'})")
    print("Build SealNote or SealNoteMac to resolve packages and refresh Package.resolved.")


if __name__ == "__main__":
    main()
