import QtQuick
import "Model.js" as Model

// ZeroTier has no tunnel to bring up or down: the service is the switch, and
// networks are joined and left one by one.
Provider {
  id: root
  providerId: "zerotier"
  name: "ZeroTier"
  binary: "zerotier-cli"
  serviceUnit: "zerotier-one.service"
  joinable: vpnState !== "daemon-down" && vpnState !== "needs-access" && vpnState !== "checking"
  reportedOn: vpnState === "on" || vpnState === "off" || vpnState === "connecting"
  setupText: vpnState === "needs-access"
    ? (snapshot.error !== "" ? snapshot.error + ". " : "") + "Let the bar read ZeroTier's local API token (asks for your password once)."
    : ""
  setupLabel: vpnState === "needs-access" ? "Grant access" : ""
  serversLabel: "Roots"
  servers: snapshot.servers || []
  serverForm: ({
    title: "Orbit a moon (self-hosted roots)",
    presets: [],
    firstLabel: "Moon ID, 10 hex characters",
    firstRequired: true,
    secondLabel: "Seed node ID (blank = same as the moon)",
    secondRequired: false,
    submitLabel: "Orbit"
  })

  readonly property string api: {
    var path = String(Qt.resolvedUrl("bin/zt-api"))
    if (path.indexOf("file://") === 0) path = path.substring(7)
    return decodeURIComponent(path)
  }

  function statusArgv() { return ["bash", api, "snapshot"] }
  function parseStatus(code, out, err) { return Model.zerotierSnapshot(out) }

  function statusLine() {
    if (vpnState === "on" || vpnState === "off") return "Online · " + snapshot.network
    if (vpnState === "connecting") return "Service starting…"
    return commonStatusLine()
  }

  function turnOn() { startService() }
  function turnOff() { run(["systemctl", "stop", serviceUnit], "Stopping ZeroTier…", "ZeroTier service stopped") }
  function setup() { run(["bash", api, "grant"], "Waiting for authorization…", "ZeroTier access granted") }

  function rowAction(row, actionId) {
    if (actionId === "leave" && row) run(["bash", api, "leave", row.key], "Leaving " + row.name + "…", "Left " + row.name)
  }

  // The planet is not optional; moons can be left.
  function removeServer(row) {
    if (row.key === "planet") return
    run(["bash", api, "deorbit", row.key], "Leaving moon " + row.key + "…", "Left moon " + row.key)
  }

  function addServer(first, second) {
    var moon = String(first || "").trim().toLowerCase()
    var seed = String(second || "").trim().toLowerCase() || moon
    if (!Model.isNodeId(moon)) return "A moon ID is 10 hex characters"
    if (!Model.isNodeId(seed)) return "A seed node ID is 10 hex characters"
    return run(["bash", api, "orbit", moon, seed], "Orbiting " + moon + "…", "Orbiting moon " + moon) ? "" : "Busy, try again in a moment"
  }

  function join(networkId) {
    var id = String(networkId || "").trim().toLowerCase()
    if (!Model.isNetworkId(id)) return flash("A network ID is 16 hex characters", true)
    run(["bash", api, "join", id], "Joining " + id + "…",
        "Joined " + id + " — authorize this device in ZeroTier Central if the network is private")
  }
}
