#!/usr/bin/env bash
# Installs the open-source Swift toolchain on Linux so the platform-agnostic
# ChronosCore package can be built and tested locally:
#
#   ./scripts/setup-swift.sh
#   swift test
#
# NOTE: This only builds the Foundation-only logic. The full app depends on
# SwiftUI/EventKit, which are macOS/iOS-only — build the app with Xcode on a
# Mac (or rely on the macOS jobs in .github/workflows/ci.yml).
set -euo pipefail

if command -v swift >/dev/null 2>&1; then
  echo "Swift already installed: $(swift --version | head -1)"
  exit 0
fi

if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release; then
  echo "Installing Swift via swiftly (Swift's official toolchain manager)…"
  curl -fsSL https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz \
    | tar -xz -C "$HOME/.local/bin" swiftly 2>/dev/null || {
      echo "Falling back to swiftly install script."
      curl -fsSL https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
    }
  "$HOME/.local/bin/swiftly" install latest || swiftly install latest
  echo "Done. Restart your shell, then run: swift test"
else
  echo "Unsupported OS. See https://www.swift.org/install/ for your platform."
  exit 1
fi
