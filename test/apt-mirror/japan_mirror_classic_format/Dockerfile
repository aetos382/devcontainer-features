FROM mcr.microsoft.com/devcontainers/base:3-ubuntu24.04

# Ubuntu 24.04+ ships its sources in deb822 format, so this scenario converts them back to the
# classic one-line format that older releases and hand-edited images still use. signed-by is spelled
# out because the deb822 file named the keyring itself, and trusted.gpg.d may not carry it.
RUN . '/etc/os-release' \
    && rm -f '/etc/apt/sources.list.d/ubuntu.sources' \
    && { \
        echo "deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://archive.ubuntu.com/ubuntu/ ${VERSION_CODENAME} main restricted universe multiverse"; \
        echo "deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://archive.ubuntu.com/ubuntu/ ${VERSION_CODENAME}-updates main restricted universe multiverse"; \
        echo "deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://archive.ubuntu.com/ubuntu/ ${VERSION_CODENAME}-backports main restricted universe multiverse"; \
        echo "deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://security.ubuntu.com/ubuntu/ ${VERSION_CODENAME}-security main restricted universe multiverse"; \
    } > '/etc/apt/sources.list'
