# claude-desktop-nix

A Nix flake that packages [Claude Desktop](https://claude.ai/download) —
Anthropic's official Linux desktop app — for NixOS.

It repackages the official `.deb` (a self-contained Electron app): extracts it,
patches the binaries against nixpkgs libraries (`autoPatchelfHook`), wires up the
`claude://` URL-scheme handler, desktop entry, and tray icons, and wraps the
Electron binary so GPU (incl. NVIDIA via `/run/opengl-driver/lib`), Vulkan, and
Wayland/X11 all work under GNOME.

The flake contains only packaging — no Anthropic code. The app itself is
proprietary (`license = unfree`).

## Sandbox

Relies on Chromium's unprivileged user-namespace sandbox, which NixOS enables by
default — so no setuid `chrome-sandbox` and no `--no-sandbox` is needed.

## Use it in your flake-based NixOS config

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    claude-desktop = {
      url = "github:GoByeBye/claude-desktop-nix";
      # Build against your own nixpkgs so libraries stay in sync:
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, claude-desktop, ... }@inputs: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.config.allowUnfree = true; # required (proprietary app)
          environment.systemPackages = [
            inputs.claude-desktop.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

Or via the overlay, so `pkgs.claude-desktop` works natively:

```nix
nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];
environment.systemPackages = [ pkgs.claude-desktop ];
```

## Try it directly

```sh
nix run github:GoByeBye/claude-desktop-nix
```

## Upgrading

### Scripted

Two scripts keep the pin current (both need `nix` and `curl`):

- [`./update.sh`](./update.sh) — bumps `version`/`url`/`hash` in `package.nix`
  in place, only when a newer release exists. Pure: no git, no build.
- [`./auto-update.sh`](./auto-update.sh) — runs `update.sh`, then (on a change)
  verifies `nix build` passes, commits, and pushes. `--no-push` stops before
  pushing; `--no-git` just bumps + builds.

> **Why not GitHub Actions?** Anthropic's release endpoint sits behind
> Cloudflare, which 403s datacenter IPs — so GitHub-hosted runners can't reach
> it. Run these from a machine on a normal (residential) IP instead.

Schedule `auto-update.sh` however you like. A weekly cron entry:

```cron
0 7 * * 1  cd /path/to/claude-desktop-nix && ./auto-update.sh >> /tmp/claude-update.log 2>&1
```

Or a NixOS systemd timer:

```nix
systemd.user.services.claude-desktop-update = {
  script = "${pkgs.git}/bin/git -C /path/to/claude-desktop-nix pull --ff-only && /path/to/claude-desktop-nix/auto-update.sh";
  path = with pkgs; [ nix git curl coreutils gnused ];
};
systemd.user.timers.claude-desktop-update = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "weekly"; Persistent = true; };
};
```

### Manual

The download URL is version-pinned. To bump by hand:

1. Resolve `https://claude.ai/api/desktop/linux/x64/deb/latest/redirect` (a `GET`
   with a browser `User-Agent`) to get the new versioned `.deb` URL.
2. Update `version` + `url` in [`package.nix`](./package.nix).
3. Update `hash` — a mismatch on build prints the correct value.
