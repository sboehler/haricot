{ nixpkgs ? import <nixpkgs> {}, compiler ? "default" }:

let

  pkgs = nixpkgs.pkgs;

  haskellPackages = if compiler == "default"
                       then pkgs.haskellPackages
                       else pkgs.haskell.packages.${compiler};

  drv = haskellPackages.callPackage (import ./default.nix) {};

in

  if pkgs.lib.inNixShell then drv.env else drv