{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkDefault;
  cfg = config.openstack;
  metadataFetcher = import ./openstack-metadata-fetcher.nix {
    targetRoot = "/";
    wgetExtraOptions = "--retry-connrefused";
  };
in
{
  imports = [
    ../profiles/qemu-guest.nix

    # Note: While we do use the headless profile, we also explicitly
    # turn on the serial console on ttyS0 below.
    ../profiles/headless.nix

    # The Openstack Metadata service exposes data on an EC2 API also.
    ./ec2-data.nix
    ./amazon-init.nix
  ];

  config = {
    fileSystems."/" = mkIf (!cfg.zfs.enable) {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      autoResize = true;
    };

    fileSystems."/boot" = mkIf (cfg.efi || cfg.zfs.enable) {
      # The ZFS image uses a partition labeled ESP whether or not we're
      # booting with EFI.
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
    };

    boot.growPartition = true;
    boot.kernelParams = [ "console=ttyS0" ];
    boot.loader.grub.device = if (!cfg.efi) then "/dev/vda" else "nodev";
    boot.loader.grub.efiSupport = cfg.efi;
    boot.loader.grub.efiInstallAsRemovable = cfg.efi;
    boot.loader.timeout = 1;
    boot.loader.grub.extraConfig = ''
      serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
      terminal_output console serial
      terminal_input console serial
    '';

    services.zfs.expandOnBoot = mkIf cfg.zfs.enable "all";
    boot.zfs.devNodes = mkIf cfg.zfs.enable "/dev/";

    # Allow root logins
    services.openssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
      passwordAuthentication = mkDefault false;
    };

    users.users.root.initialPassword = "foobar";

    # Enable the serial console on ttyS0
    systemd.services."serial-getty@ttyS0".enable = true;

    # Force getting the hostname from Openstack metadata.
    networking.hostName = mkDefault "";

    systemd.services.openstack-init = {
      path = [ pkgs.wget ];
      description = "Fetch Metadata on startup";
      wantedBy = [ "multi-user.target" ];
      before = [ "apply-ec2-data.service" "amazon-init.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      script = metadataFetcher;
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
