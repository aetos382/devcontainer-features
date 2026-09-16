#!/usr/bin/env bash
# ShellCheck 本体を GitHub Releases から取得して /usr/local/bin に配置する。
# ベースイメージには curl と tar (xz 対応) が入っているため、apt-get の実行は不要。
set -euo pipefail

# TODO: バージョンを上げても気づく手段がない。Dependabot は対応できないので、
# 追従させるなら Renovate の custom regex manager を導入する。
SHELLCHECK_VERSION='v0.11.0'

# GitHub のリリース API が算出した sha256 ダイジェスト。ダウンロードの破損を検出するために使う。
case "$(uname -m)" in
  x86_64) ARCH='x86_64'; SHA256='8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198' ;;
  aarch64) ARCH='aarch64'; SHA256='12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588' ;;
  *)
    echo "install-shellcheck: unsupported architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac

ARCHIVE="shellcheck-${SHELLCHECK_VERSION}.linux.${ARCH}.tar.xz"
URL="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${ARCHIVE}"
INSTALL_PATH='/usr/local/bin/shellcheck'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL --retry 3 -o "$TMP_DIR/$ARCHIVE" "$URL"
echo "$SHA256  $TMP_DIR/$ARCHIVE" | sha256sum -c -

tar -xJf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR" "shellcheck-${SHELLCHECK_VERSION}/shellcheck"

if [ -w "$(dirname "$INSTALL_PATH")" ]; then
  install -m 755 "$TMP_DIR/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "$INSTALL_PATH"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo -n install -m 755 "$TMP_DIR/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "$INSTALL_PATH"
else
  echo "install-shellcheck: cannot write to $(dirname "$INSTALL_PATH") and passwordless sudo is unavailable." >&2
  exit 1
fi

"$INSTALL_PATH" --version
