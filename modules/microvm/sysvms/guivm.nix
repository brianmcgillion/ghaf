# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let

  vmName = "gui-vm";
  #TODO do not import from a path like this
  inherit (import ../../../lib/launcher.nix { inherit pkgs lib; }) rmDesktopEntries;
  guivmBaseConfiguration = {
    imports = [
      inputs.self.nixosModules.profiles
      inputs.self.nixosModules.givc
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.vm-modules

      (
        { lib, pkgs, ... }:
        let
          # A list of applications from all AppVMs
          enabledVms = lib.filterAttrs (_: vm: vm.enable) config.ghaf.virtualization.microvm.appvm.vms;
          virtualApps = lib.lists.concatMap (
            vm: map (app: app // { vmName = "${vm.name}-vm"; }) vm.applications
          ) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);

          # Launchers for all virtualized applications that run in AppVMs
          virtualLaunchers = map (app: rec {
            inherit (app) name;
            inherit (app) description;
            #inherit (app) givcName;
            vm = app.vmName;
            path = "${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} start app --vm ${vm} ${app.givcName}";
            inherit (app) icon;
          }) virtualApps;

          # Launchers for all desktop, non-virtualized applications that run in the GUIVM
          guivmLaunchers = map (app: {
            inherit (app) name;
            inherit (app) description;
            path = app.command;
            inherit (app) icon;
          }) cfg.applications;
        in
        {
          imports = [
            #TODO: inception cross reference. FIX: this
            ../../reference/services
          ];

          ghaf = {
            # Profiles
            profiles = {
              debug.enable = lib.mkDefault config.ghaf.profiles.debug.enable;
              graphics.enable = true;
            };
            users.loginUser = {
              enable = true;
              fidoAuth = true;
            };
            development = {
              ssh.daemon.enable = lib.mkDefault config.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
              debug.tools.gui.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault config.ghaf.development.nix-setup.enable;
            };

            # System
            type = "system-vm";
            systemd = {
              enable = true;
              withName = "guivm-systemd";
              withHomed = true;
              withLocaled = true;
              withNss = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = config.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };

            givc.guivm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
              shared-folders = {
                enable = true;
                isGuiVm = true;
              };
            };

            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };

            # Create launchers for regular apps running in the GUIVM and virtualized ones if GIVC is enabled
            graphics = {
              launchers = guivmLaunchers ++ lib.optionals config.ghaf.givc.enable virtualLaunchers;
              labwc = {
                autolock.enable = lib.mkDefault config.ghaf.graphics.labwc.autolock.enable;
                autologinUser = lib.mkDefault config.ghaf.graphics.labwc.autologinUser;
                securityContext = map (vm: {
                  identifier = vm.name;
                  color = vm.borderColor;
                }) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);
              };
              cosmic = {
                securityContext.rules = map (vm: {
                  identifier = vm.name;
                  color = vm.borderColor;
                }) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);
              };
            };

            # Logging
            logging.client.enable = config.ghaf.logging.enable;

            # Services
            services = {
              github = {
                enable = true;
                token = "xxxxxxxxxxxxxxxxxxxx"; # Will be updated when the user login
                owner = "tiiuae";
                repo = "ghaf-bugreports";
              };

              acpid.enable = true;

              timezone.enable = true;

              disks = {
                enable = true;
                fileManager = lib.mkIf config.ghaf.graphics.labwc.enable "${pkgs.pcmanfm}/bin/pcmanfm";
              };
            };
            xdgitems.enable = true;
          };

          # Handle clamshell mode and lid switch events for laptops
          services = {
            logind = {
              lidSwitch = if config.ghaf.givc.enable then "ignore" else "suspend";
              killUserProcesses = true;
              extraConfig = ''
                IdleAction=lock
                UserStopDelaySec=0
              '';
            };

            # We dont enable services.blueman because it adds blueman desktop entry
            dbus.packages = [ pkgs.blueman ];
          };

          systemd = {
            packages = [ pkgs.blueman ];

            services."waypipe-ssh-keygen" =
              let
                uid = "${toString config.ghaf.users.loginUser.uid}";
                pubDir = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                keygenScript = pkgs.writeShellScriptBin "waypipe-ssh-keygen" ''
                  set -xeuo pipefail
                  mkdir -p /run/waypipe-ssh
                  echo -en "\n\n\n" | ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /run/waypipe-ssh/id_ed25519 -C ""
                  chown ${uid}:users /run/waypipe-ssh/*
                  cp /run/waypipe-ssh/id_ed25519.pub ${pubDir}/id_ed25519.pub
                  chown -R ${uid}:users ${pubDir}
                '';
              in
              {
                enable = true;
                description = "Generate SSH keys for Waypipe";
                path = [ keygenScript ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  StandardOutput = "journal";
                  StandardError = "journal";
                  ExecStart = "${keygenScript}/bin/waypipe-ssh-keygen";
                };
              };
          };

          environment = {
            systemPackages =
              (rmDesktopEntries [
                pkgs.waypipe
                pkgs.networkmanagerapplet
                pkgs.gnome-calculator
                pkgs.sticky-notes
              ])
              ++ [
                pkgs.bt-launcher
                pkgs.pamixer
                pkgs.eww
                pkgs.wlr-randr
              ]
              ++ [ pkgs.ctrl-panel ]
              # Packages for checking hardware acceleration
              ++ lib.optionals config.ghaf.profiles.debug.enable [
                pkgs.glxinfo
                pkgs.libva-utils
                pkgs.glib
              ];
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = config.nixpkgs.buildPlatform.system;
            hostPlatform.system = config.nixpkgs.hostPlatform.system;
          };

          microvm = {
            optimize.enable = false;
            vcpu = 2;
            mem = 12288;
            hypervisor = "qemu";
            shares = [
              {
                tag = "waypipe-ssh-public-key";
                source = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                mountPoint = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                proto = "virtiofs";
              }
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
              {
                tag = "ghaf-common";
                source = "/persist/common";
                mountPoint = "/etc/common";
                proto = "virtiofs";
              }
            ];
            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

            qemu = {
              extraArgs = [
                "-device"
                "qemu-xhci"
                "-device"
                "vhost-vsock-pci,guest-cid=${toString config.ghaf.networking.hosts.${vmName}.cid}"
              ];

              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${config.nixpkgs.hostPlatform.system};
            };
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.guivm;

  #TODO: fix the kernel includes and builders to be more modular and centrailized
  # Importing kernel builder function and building guest_graphics_hardened_kernel
  buildKernel = import ../../../packages/kernel { inherit config pkgs lib; };
  config_baseline = ../../hardware/x86_64-generic/kernel/configs/ghaf_host_hardened_baseline-x86;
  guest_graphics_hardened_kernel = buildKernel { inherit config_baseline; };

in
{
  options.ghaf.virtualization.microvm.guivm = {
    enable = lib.mkEnableOption "GUIVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        GUIVM's NixOS configuration.
      '';
      default = [ ];
    };
    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
    applications = lib.mkOption {
      description = ''
        Applications to include in the GUIVM
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "The name of the application";
            };
            description = lib.mkOption {
              type = lib.types.str;
              description = "A brief description of the application";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              description = "Application icon";
              default = null;
            };
            command = lib.mkOption {
              type = lib.types.str;
              description = "The command to run the application";
              default = null;
            };
          };
        }
      );
      default = [ ];
    };
  };
  config = lib.mkIf cfg.enable {
    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = !config.ghaf.microvm-boot.enable;
      inherit (inputs) nixpkgs;
      specialArgs = { inherit lib; };

      config = guivmBaseConfiguration // {
        boot.kernelPackages =
          if config.ghaf.guest.kernel.hardening.graphics.enable then
            pkgs.linuxPackagesFor guest_graphics_hardened_kernel
          else
            pkgs.linuxPackages_latest;

        # We need this patch to avoid reserving Intel graphics stolen memory for vm
        # https://gitlab.freedesktop.org/drm/i915/kernel/-/issues/12103
        boot.kernelPatches = [
          {
            name = "gpu-passthrough-fix";
            patch = ./0001-x86-gpu-Don-t-reserve-stolen-memory-for-GPU-passthro.patch;
          }
        ];

        imports = guivmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };

}
