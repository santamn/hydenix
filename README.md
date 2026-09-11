
<img align="right" width="75px" alt="NixOS" src="https://github.com/HyDE-Project/HyDE/blob/master/Source/assets/nixos.png?raw=true"/>

# hydenix

[![NixOS Unstable](https://img.shields.io/badge/NixOS-unstable-ebbcba.svg?style=flat-square&logo=NixOS&logoColor=white)](https://nixos.org)
[![Github Pages](https://img.shields.io/github/actions/workflow/status/santamn/hydenix/pages.yml?style=flat-square&color=c79bf0&label=docs&logo=mdbook&logoColor=white)](https://github.com/santamn/hydenix/actions/workflows/pages.yml)
[![Last Commit](https://img.shields.io/github/last-commit/santamn/hydenix/main?style=flat-square&color=ebbcba)](https://github.com/santamn/hydenix/commits/main)
[![Nix Flake Check](https://img.shields.io/github/actions/workflow/status/santamn/hydenix/flake-check.yml?style=flat-square&color=c79bf0&label=flake%20check)](https://github.com/santamn/hydenix/actions/workflows/flake-check.yml)

**hydenix** is a **NixOS + Home Manager configuration** for [HyDE](https://github.com/HyDE-Project/HyDE).

It brings the HyDE desktop experience to NixOS while taking advantage of
the Nix module system and reproducible configuration management.

> [!NOTE]
> This repository continues a lineage whose earlier links have stopped.
>
> ```text
> richen604/hydenix             in maintenance mode: no further nixpkgs or HyDE updates
>   └─ florianvazelle/hydenix   archived: read-only
>        └─ santamn/hydenix     <-- this repository
> ```

## ✨ Features

- Declarative configuration via `hydenix` and `hydenix.hm` options
- Built on the **NixOS module system** (easily extend, override, or disable modules)
- Close feature parity with the upstream [HyDE](https://github.com/HyDE-Project/HyDE)
- Support for all community themes from [hyde-gallery](https://github.com/HyDE-Project/hyde-gallery)
- Fully reproducible desktop environments
- Easy system rollbacks
- Version-controlled desktop configuration

> [!IMPORTANT]
> Some familiarity with **functional programming concepts** is recommended.  
> If you are new to Nix, check the [Nix resources](https://santamn.github.io/hydenix/faq.html#how-do-i-learn-more-about-nix) or ask questions in **Issues** or **Discord**.

## 🚀 Getting Started

To use **hydenix** you simply add the repository as a flake input and
import the provided NixOS / Home‑Manager modules in your own
`flake.nix`.

You can bootstrap a new project using the **hydenix template**:

```bash
nix flake new -t github:santamn/hydenix my-hydenix-config
cd my-hydenix-config
```

This creates a pre-configured flake with hydenix already integrated, allowing you to start customizing immediately.

## 📚 Documentation

- [Installation](https://santamn.github.io/hydenix/installation.html)
- [Upgrading](https://santamn.github.io/hydenix/upgrading.html)
- [Module Options](https://santamn.github.io/hydenix/options.html)
- [FAQ](https://santamn.github.io/hydenix/faq.html)
- [Troubleshooting & Issues](https://santamn.github.io/hydenix/troubleshooting.html)
- [Contributing](https://santamn.github.io/hydenix/contributing.html)
- [Community Configurations](https://santamn.github.io/hydenix/community.html)
<!-- - [Roadmap / Upcoming Features](./TODO.md) -->

## 🖥️ hydenix VM

If your system supports virtualization, you can try **hydenix in a NixOS VM** without installing it on your machine.

If you encounter issues running Hyprland inside the VM, see the [VirtIO guide](https://santamn.github.io/hydenix/faq.html#how-do-i-run-hyprland-in-a-vm).

```bash
# run the flake remotely
nix run github:santamn/hydenix
```

> [!NOTE]
> Any configuration changes require rebuilding the VM.
> To reset it, delete the disk image:
>
> ```text
> rm hydenix.qcow2
> ```
