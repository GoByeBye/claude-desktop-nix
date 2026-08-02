# Claude Desktop — Anthropic's official Linux app, packaged from the official
# .deb (a self-contained Electron 42 app).
#
# The download URL is version-pinned; the `latest/redirect` endpoint at
# https://claude.ai/api/desktop/linux/x64/deb/latest/redirect resolves to it.
# To upgrade: resolve that redirect for the new versioned URL, then bump
# `version` + `url` and update `hash` (a mismatch prints the correct one).
#
# Sandbox: relies on Chromium's unprivileged user-namespace sandbox, which
# NixOS enables by default — so no setuid chrome-sandbox and no --no-sandbox
# needed. The bundled 4755 chrome-sandbox is only a fallback for systems
# without userns.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  # buildInputs — NEEDED libs + standard Chromium runtime set
  glib,
  nss,
  nspr,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  pango,
  gdk-pixbuf,
  gtk3,
  cups,
  dbus,
  expat,
  libxkbcommon,
  libgbm,
  libdrm,
  alsa-lib,
  systemd,
  libsecret,
  libpulseaudio,
  libnotify,
  libseccomp,
  libcap_ng,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxi,
  libxcursor,
  libxrender,
  libxtst,
  libxscrnsaver,
  # runtime (dlopen'd) — GPU / Vulkan / VA-API / Wayland
  libglvnd,
  vulkan-loader,
  libva,
  pciutils,
  wayland,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-desktop";
  version = "1.24012.9";

  src = fetchurl {
    url = "https://downloads.claude.ai/releases/linux/x64/${finalAttrs.version}/Claude-03c61d06f8e01a4db2273b9514e225f21d2ba62e.deb";
    hash = "sha256-MC5tII3YyOnlIGfaoo7zsRcaFhNYb9DhC+3GQiJbbuE=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  # Shared libraries the Electron binaries link against (NEEDED) plus the
  # standard Chromium runtime set. autoPatchelfHook rewrites RPATHs against
  # these; the app's own bundled .so's resolve via their $ORIGIN rpath.
  buildInputs = [
    stdenv.cc.cc.lib
    glib
    nss
    nspr
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    pango
    gdk-pixbuf
    gtk3
    cups
    dbus
    expat
    libxkbcommon
    libgbm
    libdrm
    alsa-lib
    systemd # libudev
    libsecret # Electron safeStorage keyring
    libpulseaudio
    libnotify
    libseccomp # virtiofsd (cowork VM helper)
    libcap_ng # virtiofsd (cowork VM helper)
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxi
    libxcursor
    libxrender
    libxtst
    libxscrnsaver
  ];

  # dlopen'd at runtime (not in NEEDED) — baked into RPATH so GPU, Vulkan,
  # Wayland and GPU-probing work from the app and its helper processes.
  runtimeDependencies = [
    (lib.getLib libglvnd)
    vulkan-loader
    libgbm
    wayland
    libva
    pciutils
  ];

  # `dpkg-deb -x` preserves the setuid bit on the bundled chrome-sandbox
  # (shipped 4755), which the build sandbox can't set. Pipe the data tar and
  # extract without preserving perms — the setuid fallback is unused anyway.
  unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner";

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/claude-desktop
    cp -r usr/lib/claude-desktop/. $out/lib/claude-desktop/

    # Desktop entry, icons and MIME (claude:// scheme handler).
    mkdir -p $out/share
    cp -r usr/share/applications $out/share/applications
    cp -r usr/share/icons $out/share/icons

    runHook postInstall
  '';

  # Wrap the real Electron binary. --ozone-platform-hint=auto picks Wayland
  # under a Wayland session and X11 otherwise, so it works under GNOME either
  # way. My flags go FIRST so an empty gappsWrapperArgs array can't swallow the
  # --prefix that follows. gappsWrapperArgs (GSettings schemas, GDK pixbuf
  # loaders) are appended by wrapGAppsHook via dontWrapGApps below.
  dontWrapGApps = true;
  postFixup = ''
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          libglvnd # libEGL.so.1 / libGLESv2.so.2 / libGLX
          vulkan-loader
          libva
        ]
      }:/run/opengl-driver/lib" \
      --add-flags "--ozone-platform-hint=auto" \
      "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "Anthropic's official desktop application for Claude";
    homepage = "https://claude.ai/download";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
})
