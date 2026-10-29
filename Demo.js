.pragma library

// Sample output for `"demo": true`: what each CLI would print on a made-up
// machine, so the panel renders real UI with no real addresses in it (the
// marketplace preview is taken this way). Demo mode runs no commands.

function ago(minutes) {
  return new Date(Date.now() - minutes * 60000).toISOString()
}

var tailscale = {
  status: function() {
    var peers = [
      ["nas", "100.71.20.5", "linux", true, 0, false],
      ["homelab", "100.88.3.17", "linux", true, 0, true],
      ["pixel-8", "100.102.44.9", "android", true, 0, false],
      ["raspberry-pi", "100.64.9.30", "linux", true, 0, false],
      ["work-mac", "100.95.61.2", "macOS", false, 140, false],
      ["build-box", "100.80.7.41", "linux", false, 4320, false],
      ["living-room-tv", "100.117.2.66", "tvOS", false, 17280, false]
    ]
    var map = {}
    for (var i = 0; i < peers.length; i++) {
      var p = peers[i]
      map["nodekey:" + i] = {
        ID: String(i + 2),
        HostName: p[0],
        DNSName: p[0] + ".tail1234.ts.net.",
        OS: p[2],
        TailscaleIPs: [p[1]],
        Online: p[3],
        LastSeen: p[3] ? "0001-01-01T00:00:00Z" : ago(p[4]),
        ExitNode: false,
        ExitNodeOption: p[5]
      }
    }
    return JSON.stringify({
      BackendState: "Running",
      Self: {
        HostName: "laptop",
        DNSName: "laptop.tail1234.ts.net.",
        TailscaleIPs: ["100.101.12.4", "fd7a:115c:a1e0::4"]
      },
      CurrentTailnet: { Name: "you@github", MagicDNSSuffix: "tail1234.ts.net" },
      Peer: map
    })
  },
  servers: function() {
    return JSON.stringify([
      { id: "a1b2", nickname: "personal", tailnet: "you@github", account: "you@github", selected: true },
      { id: "c3d4", nickname: "homelab", tailnet: "headscale.example.com", account: "you", selected: false }
    ]) + "\n---prefs---\n" + JSON.stringify({ ControlURL: "https://controlplane.tailscale.com" })
  }
}

var netbird = {
  status: function() {
    var peer = function(name, ip, status, type, latencyMs, minutes) {
      return {
        fqdn: name + ".netbird.cloud",
        netbirdIp: ip + "/16",
        status: status,
        connectionType: type,
        latency: latencyMs * 1000000,
        lastStatusUpdate: ago(minutes)
      }
    }
    return JSON.stringify({
      daemonStatus: "Connected",
      fqdn: "laptop.netbird.cloud",
      netbirdIp: "100.92.14.7/16",
      management: { url: "https://api.netbird.io:443", connected: true, error: "" },
      peers: {
        details: [
          peer("office-gateway", "100.92.0.1", "Connected", "P2P", 12, 1),
          peer("ci-runner", "100.92.3.40", "Connected", "Relayed", 48, 1),
          peer("staging-db", "100.92.8.12", "Connected", "P2P", 21, 1),
          peer("design-imac", "100.92.5.77", "Idle", "", 0, 95)
        ]
      }
    })
  },
  servers: function() {
    return "NAME     ACTIVE\ncloud    ✓\noffice\n\n---cache---\n"
      + JSON.stringify({ cloud: "https://api.netbird.io:443", office: "https://netbird.example.com:443" })
  }
}

var zerotier = {
  status: function() {
    return JSON.stringify({
      auth: "ok",
      status: { address: "a1b2c3d4e5", online: true, version: "1.16.2", planetWorldId: 149604618 },
      networks: [
        { id: "8056c2e21c000001", name: "home-lab", status: "OK", type: "PRIVATE", assignedAddresses: ["10.147.17.23/24"] },
        { id: "1c33c1ced0000002", name: "game-night", status: "ACCESS_DENIED", type: "PRIVATE", assignedAddresses: [] }
      ],
      peers: [
        { address: "8056c2e21c", role: "LEAF", latency: 18, version: "1.16.2", paths: [{ active: true }] },
        { address: "f1e2d3c4b5", role: "LEAF", latency: 64, version: "1.14.2", paths: [] },
        { address: "778cde7190", role: "PLANET", latency: 120, paths: [{ active: true }] }
      ],
      moons: []
    })
  }
}
