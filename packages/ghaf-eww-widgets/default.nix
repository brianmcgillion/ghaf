# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ stdenv}:

# install the eww based widget configurations.

stdenv.mkDerivation {
  pname = "ghaf-eww-widgets";
  version = "0.1.0";
  src = ./.;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/config/eww
    cp -r $src/eww $out/config/eww
  '';
}
