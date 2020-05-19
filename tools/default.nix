{ pkgs ? import <nixpkgs> {
    overlays = [
      (import ../overlay.nix)
    ];
  }
}:
let
  inherit (pkgs) lib;

  srcPath = builtins.toString ../.;
in
{

  release =
    let
      pythonEnv = pkgs.python3.withPackages (
        ps: [
          ps.pythonix
        ]
      );
    in
    pkgs.writeScriptBin "poetry2nix-release" ''
      #!${pythonEnv.interpreter}
      import subprocess
      import argparse
      import nix
      import sys

      if __name__ == '__main__':
          tag_latest = subprocess.run(['git', 'describe', '--abbrev=0'], stdout=subprocess.PIPE, check=True).stdout.decode().strip()
          version_latest = nix.eval('(import ${srcPath} {}).version')

          if tag_latest == version_latest:
            sys.stderr.write('Version number not bumped in default.nix\n')
            sys.stderr.flush()
            exit(1)

          p = subprocess.run(['git', 'status', '--short'], stdout=subprocess.PIPE)
          if p.stdout.decode().strip() != "":
            sys.stderr.write('Git tree is dirty\n')
            sys.stderr.flush()
            exit(1)

          subprocess.run(['nix-build', '--no-out-link', '${srcPath + "/tests"}'], check=True)
          subprocess.run(['${srcPath + "/check-fmt"}'], check=True)

          p = subprocess.run(['git', 'tag', '-a', version_latest])
          exit(p.returncode)
    '';

  flamegraph =
    let
      runtimeDeps = lib.makeBinPath [
        pkgs.flamegraph
        pkgs.python3
        pkgs.nix
      ];
      nixSrc = pkgs.runCommandNoCC "${pkgs.nix.name}-sources"
        { } ''
        mkdir $out
        tar -x --strip=1 -f ${pkgs.nix.src} -C $out
      '';
    in
    pkgs.writeScriptBin "poetry2nix-flamegraph" ''
      #!${pkgs.runtimeShell}
      export PATH=${runtimeDeps}:$PATH

      workdir=$(mktemp -d)
      function cleanup {
        rm -rf "$workdir"
      }
      trap cleanup EXIT

      # Run once to warm up
      nix-instantiate --expr '(import <nixpkgs> { overlays = [ (import ${srcPath + "/overlay.nix"}) ]; })' -A poetry
      nix-instantiate --trace-function-calls --expr '(import <nixpkgs> { overlays = [ (import ${srcPath + "/overlay.nix"}) ]; })' -A poetry 2> $workdir/traceFile
      python3 ${nixSrc}/contrib/stack-collapse.py $workdir/traceFile > $workdir/traceFile.folded
      flamegraph.pl $workdir/traceFile.folded > poetry2nix-flamegraph.svg
    '';

}
