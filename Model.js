.pragma library

// Every VPN is folded into one snapshot shape, so the panel never needs to
// know which CLI produced it:
//
//   state      on | off | connecting | needs-login | needs-approval |
//              needs-access | daemon-down | error
//   selfName   this machine's name on the network
//   network    the tailnet / management server / node it belongs to
//   addresses  [{ label, value }]               this machine's addresses
//   sections   [{ title, rows: [row] }]         peers, machines, networks
//   row        { key, name, detail, address, online, action }
//   adminUrl, authUrl, error

function emptySnapshot(state, error) {
  return {
    state: state,
    selfName: "",
    network: "",
    addresses: [],
    sections: [],
    adminUrl: "",
    authUrl: "",
    error: String(error || "")
  }
}

function stripMask(value) {
  return String(value || "").split("/")[0]
}

function firstIpv4(list) {
  var items = list || []
  for (var i = 0; i < items.length; i++) {
    var ip = stripMask(items[i])
    if (ip !== "" && ip.indexOf(":") < 0) return ip
  }
  return items.length > 0 ? stripMask(items[0]) : ""
}

function firstIpv6(list) {
  var items = list || []
  for (var i = 0; i < items.length; i++) {
    var ip = stripMask(items[i])
    if (ip.indexOf(":") >= 0) return ip
  }
  return ""
}

function shortName(dnsName, fallback) {
  var name = String(dnsName || "").replace(/\.$/, "")
  if (name === "") return String(fallback || "")
  return name.split(".")[0]
}

function isZeroTime(value) {
  var text = String(value || "")
  return text === "" || text.indexOf("0001-01-01") === 0
}

function ago(iso, nowMs) {
  if (isZeroTime(iso)) return ""
  var ms = new Date(String(iso)).getTime()
  if (!isFinite(ms)) return ""
  var minutes = Math.floor(Math.max(0, nowMs - ms) / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  return Math.floor(days / 30) + "mo ago"
}

function join(parts) {
  var out = []
  for (var i = 0; i < parts.length; i++)
    if (parts[i] !== undefined && parts[i] !== null && String(parts[i]) !== "") out.push(String(parts[i]))
  return out.join(" · ")
}

function byOnlineThenName(a, b) {
  if (a.online !== b.online) return a.online ? -1 : 1
  return a.name.localeCompare(b.name)
}

function hostOf(url) {
  var match = String(url || "").match(/^[a-z]+:\/\/([^/:]+)/i)
  return match ? match[1] : ""
}

function parseJson(text) {
  try {
    var value = JSON.parse(String(text || ""))
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

// ------------------------------------------------------------ tailscale

var tailscaleStates = {
  Running: "on",
  Stopped: "off",
  NeedsLogin: "needs-login",
  NeedsMachineAuth: "needs-approval",
  Starting: "connecting",
  NoState: "connecting"
}

function tailscaleSnapshot(text, nowMs) {
  var data = parseJson(text)
  if (!data) return emptySnapshot("error", "Unreadable tailscale status")

  var snapshot = emptySnapshot(tailscaleStates[String(data.BackendState || "")] || "error")
  var self = data.Self || {}
  var tailnet = data.CurrentTailnet || {}
  var suffix = String(tailnet.MagicDNSSuffix || data.MagicDNSSuffix || "")
  var selfIps = self.TailscaleIPs || data.TailscaleIPs || []

  snapshot.selfName = String(self.HostName || "")
  snapshot.network = String(tailnet.Name || "")
  snapshot.authUrl = String(data.AuthURL || "")
  // Only Tailscale's own control plane has an admin console to point at; a
  // self-hosted one (Headscale) has none, unless settings name one.
  snapshot.adminUrl = /\.ts\.net$/.test(suffix) ? "https://login.tailscale.com/admin/machines" : ""
  if (snapshot.state === "error") snapshot.error = "Tailscale reports " + String(data.BackendState || "an unknown state")

  if (snapshot.state === "on" || snapshot.state === "off") {
    var dnsName = String(self.DNSName || "").replace(/\.$/, "")
    if (firstIpv4(selfIps) !== "") snapshot.addresses.push({ label: "IPv4", value: firstIpv4(selfIps) })
    if (firstIpv6(selfIps) !== "") snapshot.addresses.push({ label: "IPv6", value: firstIpv6(selfIps) })
    if (dnsName !== "") snapshot.addresses.push({ label: "DNS", value: dnsName })
  }

  var rows = []
  var peers = data.Peer || {}
  for (var key in peers) {
    var peer = peers[key] || {}
    var peerDns = String(peer.DNSName || "")
    if (/\.mullvad\.ts\.net\.?$/.test(peerDns)) continue
    var online = peer.Online === true
    var address = firstIpv4(peer.TailscaleIPs)
    rows.push({
      key: String(peer.ID || key),
      name: String(peer.HostName || shortName(peerDns, address)),
      detail: online
        ? join([address, peer.OS, peer.ExitNode === true ? "exit node in use" : (peer.ExitNodeOption === true ? "exit node" : "")])
        : join([address, "offline", ago(peer.LastSeen, nowMs)]),
      address: address,
      online: online,
      action: null
    })
  }
  rows.sort(byOnlineThenName)
  if (snapshot.state === "on" || rows.length > 0) snapshot.sections.push({ title: "Machines", rows: rows })
  return snapshot
}

// -------------------------------------------------------------- netbird

var netbirdStates = {
  Connected: "on",
  Idle: "off",
  Connecting: "connecting",
  NeedsLogin: "needs-login",
  SessionExpired: "needs-login",
  LoginFailed: "needs-login"
}

function netbirdLatency(ns) {
  var ms = Number(ns || 0) / 1000000
  return ms > 0 ? Math.round(ms) + " ms" : ""
}

function netbirdSnapshot(text, nowMs) {
  var data = parseJson(text)
  if (!data) return emptySnapshot("error", "Unreadable netbird status")

  var status = String(data.daemonStatus || "")
  var snapshot = emptySnapshot(netbirdStates[status] || "error")
  var management = data.management || {}
  var managementHost = hostOf(management.url)
  var fqdn = String(data.fqdn || "")

  snapshot.selfName = shortName(fqdn, "")
  snapshot.network = managementHost
  snapshot.serverUrl = String(management.url || "")
  snapshot.adminUrl = managementHost === "" ? ""
    : (/(^|\.)netbird\.io$/.test(managementHost) ? "https://app.netbird.io/" : "https://" + managementHost + "/")
  if (snapshot.state === "error") snapshot.error = "NetBird reports " + (status || "an unknown state")
  if (snapshot.state === "needs-login" && management.error)
    snapshot.error = String(management.error).replace(/^rpc error: code = \w+ desc = /, "")

  var ip = stripMask(data.netbirdIp)
  if (ip !== "") snapshot.addresses.push({ label: "IPv4", value: ip })
  if (fqdn !== "") snapshot.addresses.push({ label: "DNS", value: fqdn })

  var rows = []
  var details = (data.peers && data.peers.details) || []
  for (var i = 0; i < details.length; i++) {
    var peer = details[i] || {}
    var online = String(peer.status || "") === "Connected"
    var address = stripMask(peer.netbirdIp)
    rows.push({
      key: String(peer.fqdn || address || peer.publicKey || i),
      name: shortName(peer.fqdn, address),
      detail: online
        ? join([address, String(peer.connectionType || "").toLowerCase(), netbirdLatency(peer.latency)])
        : join([address, String(peer.status || "offline").toLowerCase(), ago(peer.lastStatusUpdate, nowMs)]),
      address: address,
      online: online,
      action: null
    })
  }
  rows.sort(byOnlineThenName)
  if (snapshot.state === "on" || rows.length > 0) snapshot.sections.push({ title: "Peers", rows: rows })
  return snapshot
}

// ------------------------------------------------------------- zerotier

var zerotierNetworkStates = {
  OK: "connected",
  ACCESS_DENIED: "not authorized yet",
  REQUESTING_CONFIGURATION: "requesting config",
  NOT_FOUND: "network not found",
  PORT_ERROR: "port error",
  CLIENT_TOO_OLD: "client too old",
  AUTHENTICATION_REQUIRED: "authentication required"
}

function zerotierSnapshot(text) {
  var data = parseJson(text)
  if (!data) return emptySnapshot("error", "Unreadable ZeroTier status")

  var auth = String(data.auth || "")
  if (auth === "down") return emptySnapshot("daemon-down")
  if (auth === "missing") return emptySnapshot("needs-access")
  if (auth === "rejected") return emptySnapshot("needs-access", "The saved API token was rejected")
  if (auth !== "ok") return emptySnapshot("error", String(data.error || "ZeroTier did not answer"))

  var status = data.status || {}
  var networks = data.networks || []
  var connected = 0
  var networkRows = []
  var addresses = []
  for (var i = 0; i < networks.length; i++) {
    var net = networks[i] || {}
    var netStatus = String(net.status || "")
    var assigned = net.assignedAddresses || []
    var address = firstIpv4(assigned)
    if (netStatus === "OK") connected++
    for (var a = 0; a < assigned.length; a++)
      addresses.push({ label: String(net.name || net.id || "Network"), value: stripMask(assigned[a]) })
    networkRows.push({
      key: String(net.id || i),
      name: String(net.name || net.id || "Network"),
      detail: join([address, zerotierNetworkStates[netStatus] || netStatus.toLowerCase(), String(net.id || "")]),
      address: address !== "" ? address : String(net.id || ""),
      online: netStatus === "OK",
      action: { id: "leave", glyph: "󰩈", label: "Leave network" }
    })
  }

  var peerRows = []
  var peers = data.peers || []
  for (var p = 0; p < peers.length; p++) {
    var peer = peers[p] || {}
    if (String(peer.role || "") !== "LEAF") continue
    var paths = peer.paths || []
    var direct = false
    for (var q = 0; q < paths.length; q++) if (paths[q] && paths[q].active !== false && paths[q].expired !== true) direct = true
    var latency = Number(peer.latency)
    peerRows.push({
      key: String(peer.address || p),
      name: String(peer.address || ""),
      detail: join([latency >= 0 ? latency + " ms" : "", direct ? "direct" : "relayed", peer.version ? "v" + peer.version : ""]),
      address: String(peer.address || ""),
      online: latency >= 0,
      action: null
    })
  }
  peerRows.sort(byOnlineThenName)

  var snapshot = emptySnapshot(status.online !== true ? "connecting" : (connected > 0 ? "on" : "off"))
  snapshot.selfName = String(status.address || "")
  snapshot.network = networks.length === 0 ? "No network joined"
    : connected + " of " + networks.length + (networks.length === 1 ? " network" : " networks") + " connected"
  snapshot.adminUrl = "https://central.zerotier.com/"
  snapshot.addresses = addresses
  snapshot.sections.push({ title: "Networks", rows: networkRows })
  if (peerRows.length > 0) snapshot.sections.push({ title: "Peers", rows: peerRows })
  snapshot.servers = zerotierServers(status, data.moons || [])
  return snapshot
}

var zerotierOfficialPlanet = 149604618

// ZeroTier's "servers" are its roots: the planet every node knows, plus any
// moons (self-hosted roots) this node orbits. Self-hosted *controllers*
// (ZTNET, ztncui) need neither — their networks join by ID like any other.
function zerotierServers(status, moons) {
  var planet = Number(status.planetWorldId || 0)
  var official = planet === zerotierOfficialPlanet
  var rows = [{
    key: "planet",
    name: official ? "ZeroTier roots" : "Custom planet",
    detail: official ? "Official planet · world " + planet : "Private roots · world " + planet,
    address: String(planet),
    online: true,
    action: null
  }]
  for (var i = 0; i < moons.length; i++) {
    var moon = moons[i] || {}
    var roots = moon.roots || []
    var endpoints = []
    for (var r = 0; r < roots.length; r++) endpoints = endpoints.concat(roots[r].stableEndpoints || [])
    rows.push({
      key: String(moon.id || ""),
      name: "Moon " + String(moon.id || ""),
      detail: moon.waiting === true ? "Waiting for the seed to answer"
        : join([roots.length + (roots.length === 1 ? " root" : " roots"), endpoints.length > 0 ? endpoints[0] : ""]),
      address: String(moon.id || ""),
      online: moon.waiting !== true,
      action: { id: "remove", glyph: "󰩈", label: "Leave this moon" }
    })
  }
  return rows
}

// A ZeroTier node / moon id is 10 hex digits.
function isNodeId(text) {
  return /^[0-9a-f]{10}$/i.test(String(text || "").trim())
}

// A ZeroTier network id is 16 hex digits.
function isNetworkId(text) {
  return /^[0-9a-f]{16}$/i.test(String(text || "").trim())
}

// The first URL a login command prints is the one to open.
function firstUrl(text) {
  var match = String(text || "").match(/https?:\/\/[^\s"'<>]+/)
  return match ? match[0] : ""
}

// --------------------------------------------------------------- servers
//
// Tailscale accounts and NetBird profiles each pin a control server; both
// fold into server rows: { key, name, detail, address, online (= active),
// action }.

var removeAction = { id: "remove", glyph: "󰆴", label: "Remove" }

// "netbird.example.com" -> "https://netbird.example.com", keeping any port;
// `defaultPort` is appended when none is given (NetBird wants one).
function normalizeServerUrl(text, defaultPort) {
  var url = String(text || "").trim().replace(/\/+$/, "")
  if (url === "") return ""
  if (!/^[a-z]+:\/\//i.test(url)) url = "https://" + url
  if (!/^https?:\/\/[^\/\s]+$/i.test(url)) return ""
  if (defaultPort && !/:\d+$/.test(url.replace(/^[a-z]+:\/\//i, "")))
    url += ":" + (/^http:/i.test(url) ? 80 : defaultPort)
  return url
}

function serverLabel(url, officialPattern, officialName) {
  var host = hostOf(url)
  if (host === "") return ""
  return officialPattern.test(host) ? officialName : host
}

var tailscaleOfficialUrl = "https://controlplane.tailscale.com"

function tailscaleServers(text) {
  var parts = String(text || "").split("\n---prefs---\n")
  var list = parseJson(parts[0]) || []
  var prefs = parseJson(parts[1]) || {}
  var currentUrl = String(prefs.ControlURL || "")
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var account = list[i] || {}
    var active = account.selected === true
    var tailnet = String(account.tailnet || "")
    var server = active ? serverLabel(currentUrl, /(^|\.)tailscale\.com$/, "Tailscale") : ""
    rows.push({
      key: String(account.id || ""),
      name: String(account.nickname || account.account || tailnet || account.id),
      detail: join([server, tailnet !== server ? tailnet : "",
                    account.account !== account.nickname && account.account !== tailnet ? account.account : ""]),
      address: active ? currentUrl : tailnet,
      online: active,
      action: active ? null : removeAction
    })
  }
  return rows
}

var netbirdOfficialUrl = "https://api.netbird.io:443"

// `netbird profile list` prints a NAME / ACTIVE table; the management URL
// of each profile comes from the panel's own cache (the daemon keeps profile
// files root-only), refreshed from status whenever a profile is active.
function netbirdProfiles(text) {
  var parts = String(text || "").split("\n---cache---\n")
  var cache = parseJson(parts[1]) || {}
  var profiles = []
  var lines = String(parts[0] || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" || /^NAME\s+ACTIVE$/i.test(line)) continue
    var active = /✓\s*$/.test(line)
    profiles.push({ name: line.replace(/✓\s*$/, "").trim(), active: active })
  }
  return { profiles: profiles, cache: cache }
}

function netbirdServers(parsed, activeUrl) {
  var rows = []
  for (var i = 0; i < parsed.profiles.length; i++) {
    var profile = parsed.profiles[i]
    var url = profile.active && activeUrl !== "" ? activeUrl : String(parsed.cache[profile.name] || "")
    rows.push({
      key: profile.name,
      name: profile.name,
      detail: url !== "" ? serverLabel(url, /(^|\.)netbird\.io$/, "NetBird Cloud") : "Server shows once selected",
      address: url,
      online: profile.active,
      action: profile.active ? null : removeAction
    })
  }
  return rows
}

// The dashboard lives on the management host, except on NetBird Cloud.
function netbirdAdminUrl(managementUrl) {
  var host = hostOf(managementUrl)
  if (host === "") return ""
  if (/(^|\.)netbird\.io$/.test(host)) return "https://app.netbird.io:443"
  return managementUrl.replace(/^(https?:\/\/[^\/:]+).*$/i, "$1")
}
