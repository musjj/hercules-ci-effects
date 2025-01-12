{ lib
, modularEffect
, pkgs
}:

let
  inherit (builtins) concatStringsSep;
  inherit (lib) attrNames forEach length mapAttrsToList optionals optionalAttrs optionalString;

  genTitle = flakes:
    let
      names = attrNames flakes;
      showName = name: if name == "." then "`flake.lock`" else "`${name}/flake.lock`";
      allNames = concatStringsSep ", " (map showName names);
      sensibleNames = if length names > 3 then "`flake.lock`" else allNames;
    in
      "${sensibleNames}: Update";
in

passedArgs@
{ gitRemote
, tokenSecret ? { type = "GitToken"; }
, user ? "git"
, updateBranch ? "flake-update"
, forgeType ? "github"
, createPullRequest ? true
, autoMergeMethod ? null
  # NB: Default also specified in ./flake-module.nix
, pullRequestTitle ? genTitle flakes
, pullRequestBody ? null
, flakes ? { "." = { inherit inputs commitSummary; }; }
, inputs ? [ ]
, commitSummary ? ""
, module ? { }
}:
assert createPullRequest -> forgeType == "github";
assert (autoMergeMethod != null) -> forgeType == "github";

# Do not specify inputs when `flakes` is used
assert passedArgs?flakes -> inputs == [ ];

# Do not specify commitSummary when `flakes` is used
assert passedArgs?flakes -> commitSummary == "";

# If you don't specify any flakes, probably that's a mistake, or don't create the effect.
assert flakes != { };

modularEffect {
  imports = [
    ../modules/git-update.nix
    module
  ];

  git.checkout.remote.url = gitRemote;
  git.checkout.forgeType = forgeType;
  git.checkout.user = user;

  git.update.branch = updateBranch;
  git.update.pullRequest.enable = createPullRequest;
  git.update.pullRequest.title = pullRequestTitle;
  git.update.pullRequest.body = pullRequestBody;
  git.update.pullRequest.autoMergeMethod = autoMergeMethod;

  secretsMap.token = tokenSecret;

  name = "flake-update";
  inputs = [
    pkgs.nix
  ];

  git.update.script =
    let
      script = concatStringsSep "\n" (mapAttrsToList toScript flakes);
      toScript = relPath: flakeCfg@{inputs ? [], commitSummary ? ""}:
        let
          hasSummary = commitSummary != "";
          extraArgs = concatStringsSep " " (forEach inputs (i: "--update-input ${i}"));
          command = if inputs != [ ] then "flake lock" else "flake update";
        in
        ''
          echo 1>&2 'Running nix ${command}...'
          nix ${command} ${extraArgs} \
            --commit-lock-file \
            ${optionalString hasSummary "--commit-lockfile-summary \"${commitSummary}\""} \
            --extra-experimental-features 'nix-command flakes' \
            ${lib.escapeShellArg ("./" + relPath)}
        '';
    in
    script;

}
