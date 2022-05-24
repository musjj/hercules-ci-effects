{ effectVMTest, effects, hello, lib, mkEffect, runCommand, writeText }:

let
  inherit (lib) mapAttrsToList concatStringsSep concatMapStringsSep;

in
effectVMTest {
  name = "ssh";
  nodes = {
    ns = { nodes, ... }: {
      networking.firewall.allowedUDPPorts = [ 53 ];
      services.bind.enable = true;
      services.bind.extraOptions = "empty-zones-enable no;";
      services.bind.zones = [{
        name = ".";
        master = true;
        file = writeText "root.zone" ''
          $TTL 3600
          . IN SOA ns. ns. ( 1 8 2 4 1 )
          . IN NS ns.
          ${concatMapStringsSep
            "\n"
            (node: "${node.config.networking.hostName}. IN A ${node.config.networking.primaryIPAddress}")
            (builtins.attrValues nodes)
          }
        '';
      }];
    };
    agent = { nodes, ... }: {
      networking.dhcpcd.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver ${nodes.ns.config.networking.primaryIPAddress}
      '';
    };
    target = { ... }: {
      environment.etc."unsafe-ssh/host" = {
        source = ./test/host;
        mode = "0400";
        user = "openssh";
      };
      services.openssh = {
        enable = true;
        openFirewall = true;
        hostKeys = [
          {
            type = "rsa";
            path = "/etc/unsafe-ssh/host";
          }
        ];
      };
      users.users.root.openssh.authorizedKeys.keyFiles = [ ./test/id.pub ];
    };
  };
  effects.ssh1 = mkEffect {
    name = "ssh1";
    effectScript = ''
      writeSSHKey
      echo 'target ${builtins.readFile ./test/host.pub}' >>~/.ssh/known_hosts
      echo about to ssh
      ${effects.ssh { destination = "target"; } ''
        echo -n 'it worked' >~/it-worked
        echo >&2 plain ssh part is done
      ''}
      ${effects.ssh { destination = "target"; } ''
        ${hello}/bin/hello >~/greeting
        echo >&2 closure ssh part is done
      ''}
    '';
    secretsMap.ssh = "deploykey";
  };
  secrets.deploykey.data = {
    publicKey = builtins.readFile ./test/id.pub;
    privateKey = builtins.readFile ./test/id;
  };
  testScript = { nodes, ... }: ''
    start_all()
    ns.wait_for_unit("bind.service")
    ns.wait_for_open_port(53)
    agent.wait_for_unit("multi-user.target")
    target.wait_for_unit("sshd.service")
    target.wait_for_open_port(22)

    agent.succeed("cat /etc/hosts >/dev/console")
    agent.succeed("cat /etc/resolv.conf >/dev/console")
    agent.succeed("host target ${nodes.ns.config.networking.primaryIPAddress}")
    agent.succeed("host target")
    agent.succeed("effect-ssh1")
    target.succeed("""[[ "$(cat ~/it-worked)" == it\ worked ]]""")
    target.succeed("grep Hello <~/greeting")
  '';
}