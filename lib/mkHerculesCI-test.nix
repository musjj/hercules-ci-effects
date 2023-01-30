args@
{ inputs ? hercules-ci-effects.inputs
, hercules-ci-effects ? if args?inputs then inputs.self else builtins.getFlake "git+file://${toString ./..}"
}:
rec {
  inherit (inputs) flake-parts;
  inherit (inputs.nixpkgs.lib) attrNames;

  # Approximates https://github.com/NixOS/nix/blob/7cd08ae379746749506f2e33c3baeb49b58299b8/src/libexpr/flake/call-flake.nix#L46
  # s/flake.outputs/args.outputs/
  callFlake = args@{ inputs, outputs, sourceInfo }:
    let
      outputs = args.outputs (inputs // { self = result; });
      result = outputs // sourceInfo // { inherit inputs outputs sourceInfo; _type = "flake"; };
    in
    result;

  callFlakeOutputs = outputs: callFlake {
    inherit outputs;
    inputs = inputs // {
      inherit hercules-ci-effects;
    };
    sourceInfo = { };
  };

  fakePkg = name: {
    inherit name;
    type = "derivation";
  };

  fakeRepo = {
    branch = "main";
    ref = "refs/heads/main";
    rev = "deadbeef";
    shortRev = "deadbe";
    tag = null;
    remoteHttpUrl = "https://git.forge/repo.git";
  };

  fakeHerculesCI = { primaryRepo = fakeRepo; inherit (fakeRepo) branch ref; };

  outputs1 = inputs@{ nixpkgs, ... }: {
    packages = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (system: {
      default = nixpkgs.legacyPackages.${system}.nix.doc;
    });

    herculesCI = inputs.hercules-ci-effects.lib.mkHerculesCI { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      hercules-ci.github-pages.branch = "main";
      perSystem = { config, self', inputs', system, ... }: {
        hercules-ci.github-pages.settings.contents = self'.packages.default + "/share/doc/nix/manual";
      };
    };
  };
  flake1 = callFlakeOutputs outputs1;
  ci1 = (flake1.herculesCI fakeHerculesCI).onPush.default.outputs;

  outputs1Expected = inputs@{ flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.hercules-ci-effects.flakeModule
    ];
    systems = [ "x86_64-linux" "aarch64-darwin" ];

    hercules-ci.github-pages.branch = "main";

    perSystem = { config, self', inputs', pkgs, system, ... }: {
      packages.default = pkgs.nix.doc;
      hercules-ci.github-pages.settings.contents = config.packages.default + "/share/doc/nix/manual";
    };
  };
  flake1Expected = callFlakeOutputs outputs1Expected;
  ci1Expected = (flake1Expected.herculesCI fakeHerculesCI).onPush.default.outputs;

  tests = ok:

    assert attrNames ci1.checks == attrNames ci1Expected.checks;

    assert attrNames ci1.effects == attrNames ci1Expected.effects;

    assert ci1.effects.gh-pages.drvPath == ci1Expected.effects.gh-pages.drvPath;

    assert ci1.checks.x86_64-linux.github-pages-effect-is-buildable.drvPath ==
      ci1Expected.checks.x86_64-linux.github-pages-effect-is-buildable.drvPath;

    ok;

}
