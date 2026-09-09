# syntax=docker/dockerfile:1

# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#######################################################
# NoVNC Builder Container
#######################################################
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/base as novnc-builder

ARG NOVNC_BRANCH=v1.5.0
ARG WEBSOCKIFY_BRANCH=v0.12.0

WORKDIR /out

RUN git clone --quiet --depth 1 --branch $NOVNC_BRANCH https://github.com/novnc/noVNC.git && \
  cd noVNC/utils && \
  git clone  --quiet --depth 1 --branch $WEBSOCKIFY_BRANCH https://github.com/novnc/websockify.git

#######################################################
# End NoVNC Builder Container
#######################################################

# Main container build
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/base

# Install and configure systemd. Alternatively, you can omit this command and
# instead source from the image built using ../../systemd/Dockerfile
RUN apt-get update && apt-get install -y \
  systemd && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* &&\
  ln -s /dev/null /etc/systemd/system/apache2.service && \
  ln -s /dev/null /etc/systemd/system/getty@tty1.service && \
  ln -s /dev/null /etc/systemd/system/ldconfig.service && \
  /sbin/ldconfig -Xv && \
  ln -s /dev/null /etc/systemd/system/systemd-modules-load.service && \
  ln -s /dev/null /etc/systemd/system/ssh.socket && \
  ln -s /dev/null /etc/systemd/system/ssh.service && \
  echo "d /run/sshd 0755 root root" > /usr/lib/tmpfiles.d/sshd.conf && \
  echo -e "x /run/docker.socket - - - - -\nx /var/run/docker.socket - - - - -" > /usr/lib/tmpfiles.d/docker.conf

# Install GNOME
RUN apt-get update && apt-get install -y \
    gnome-software \
    gnome-software-common \
    gnome-software-plugin-snap \
    libappstream-glib8 \
    libgd3 \
    colord \
    gnome-control-center \
    gvfs-backends \
    hplip \
    libgphoto2-6 \
    libsane1 \
    sane-utils \
    ubuntu-desktop-minimal && \
  apt-get remove -y gnome-initial-setup && \
  apt-get remove -y --purge cloud-init && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  chmod -x /usr/lib/ubuntu-release-upgrader/check-new-release-gtk

# Install TigerVNC and noVNC
COPY --from=novnc-builder /out/noVNC /opt/noVNC
RUN apt-get update && apt-get install -y \
    dbus-x11 \
    tigervnc-common \
    tigervnc-scraping-server \
    tigervnc-standalone-server \
    tigervnc-xorg-extension \
    python3-numpy  && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Merge assets into the container.
COPY assets/. /

# Run TigerVNC and noVNC as services.
RUN ln -s /etc/systemd/system/tigervnc.service /etc/systemd/system/multi-user.target.wants/ && \
  ln -s /etc/systemd/system/novnc.service /etc/systemd/system/multi-user.target.wants/ && \
  systemctl enable tigervnc && \
  systemctl enable novnc

# ---------------------------------------------------------
# Antigravity 2.0 Setup
# ---------------------------------------------------------
ARG ANTIGRAVITY_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.12.2-6298742303883264/linux-x64/Antigravity.tar.gz"
ARG ANTIGRAVITY_SHA256="fc2e2af49a45aefee9558bce56aaa4bbde00d560d354357af1b834a9dd43cd33"

# Install Electron / Chromium runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libnss3 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libasound2t64 \
    libxss1 \
    libgbm1 \
    libdrm2 \
    libxkbfile1 \
    libsecret-1-0 \
    xdg-utils && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Download, verify SHA256 checksum, and extract Antigravity 2.0 to /opt
RUN mkdir -p /opt && \
  curl -fsSL "${ANTIGRAVITY_URL}" -o /tmp/Antigravity.tar.gz && \
  echo "${ANTIGRAVITY_SHA256}  /tmp/Antigravity.tar.gz" | sha256sum -c - && \
  tar -xz -C /opt -f /tmp/Antigravity.tar.gz && \
  rm -f /tmp/Antigravity.tar.gz

# Create a launcher script in /usr/local/bin
RUN printf '#!/bin/bash\nexec /opt/Antigravity-x64/antigravity --no-sandbox "$@"\n' > /usr/local/bin/antigravity && \
  chmod +x /usr/local/bin/antigravity

# Create Desktop entry for application menu
RUN mkdir -p /usr/share/applications && \
  printf '[Desktop Entry]\nName=Antigravity\nComment=Antigravity 2.0 Agent Platform\nExec=/usr/local/bin/antigravity\nIcon=applications-development\nTerminal=false\nType=Application\nCategories=Development;IDE;\n' > /usr/share/applications/antigravity.desktop

# Configure GNOME Autostart to launch AGY 2.0 automatically on desktop login
RUN mkdir -p /etc/xdg/autostart && \
  printf '[Desktop Entry]\nType=Application\nExec=/usr/local/bin/antigravity\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true\nName=Antigravity\nComment=Launch Antigravity 2.0 on startup\n' > /etc/xdg/autostart/antigravity.desktop

# Disable GNOME screensaver and lock screen to keep the browser session always responsive
RUN gsettings set org.gnome.desktop.screensaver lock-enabled false || true && \
  gsettings set org.gnome.desktop.session idle-delay 0 || true

# ---------------------------------------------------------
# Google Chrome Setup (for AGY OAuth Authentication)
# ---------------------------------------------------------
RUN curl -fsSL -o /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
  apt-get update && \
  apt-get install -y --no-install-recommends /tmp/google-chrome.deb && \
  rm -f /tmp/google-chrome.deb && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Wrap google-chrome so it runs reliably inside containers with --no-sandbox
RUN if [ -f /usr/bin/google-chrome-stable ]; then \
      mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable-bin && \
      printf '#!/bin/bash\nexec /usr/bin/google-chrome-stable-bin --no-sandbox --test-type --disable-dev-shm-usage "$@"\n' > /usr/bin/google-chrome-stable && \
      chmod +x /usr/bin/google-chrome-stable; \
    fi

# Set Google Chrome as default web browser for system and xdg-open
RUN update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/google-chrome-stable 200 && \
  update-alternatives --set x-www-browser /usr/bin/google-chrome-stable && \
  mkdir -p /etc/xdg && \
  printf '[Default Applications]\ntext/html=google-chrome.desktop\nx-scheme-handler/http=google-chrome.desktop\nx-scheme-handler/https=google-chrome.desktop\nx-scheme-handler/about=google-chrome.desktop\nx-scheme-handler/unknown=google-chrome.desktop\n' >> /etc/xdg/mimeapps.list

# This is implicit when extending workstations predefined images, however we are
# including it in the sample to explicitly call-out we are overriding the
# default entrypoint when merging assets.
ENTRYPOINT ["/google/scripts/entrypoint.sh"]
