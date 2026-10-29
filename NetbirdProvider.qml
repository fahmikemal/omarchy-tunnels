import QtQuick
import Quickshell
import "Model.js" as Model

Provider {
  id: root
  providerId: "netbird"
  name: "NetBird"
  binary: "netbird"
  serviceUnit: "netbird.service"
  serversLabel: "Management server"
  serverForm: ({
    title: "Add a management server",
    presets: [{ label: "NetBird Cloud", url: Model.netbirdOfficialUrl }, { label: "Self-hosted", url: "" }],
    firstLabel: "Profile name, e.g. office",
    firstRequired: true,
    secondLabel: "Management URL, e.g. https://netbird.example.com",
    secondRequired: true,
    submitLabel: "Add & sign in"
  })

  // Profile files are root-only, so which server each profile uses is
  // remembered here, learned whenever that profile is the active one.
  property var serverCache: ({})
  readonly property string cachePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy-tunnels/netbird-servers.json"

  function statusArgv() { return ["timeout", "-k", "2", "8", "netbird", "status", "--json"] }

  function parseStatus(code, out, err) {
    if (out.trim().charAt(0) === "{") return Model.netbirdSnapshot(out, Date.now())
    // The CLI retries a dead daemon socket forever; our timeout ends it.
    if (code === 124 || /daemon|socket|dial|connection refused/i.test(err))
      return Model.emptySnapshot("daemon-down")
    return Model.emptySnapshot("error", firstLine(err) || "netbird status failed")
  }

  function turnOn() { run(["timeout", "-k", "2", "60", "netbird", "up"], "Connecting…") }
  function turnOff() { run(["timeout", "-k", "2", "30", "netbird", "down"], "Disconnecting…") }

  // --no-browser: the URL is opened with Omarchy's browser, not xdg-open.
  function loginArgv() { return ["netbird", "up", "--no-browser"] }

  // Each NetBird profile signs into its own management server.
  function serversArgv() {
    return ["sh", "-c", "netbird profile list; printf '\\n---cache---\\n'; cat \"$1\" 2>/dev/null", "sh", cachePath]
  }

  function parseServers(code, out, err) {
    var parsed = Model.netbirdProfiles(out)
    serverCache = parsed.cache
    var activeUrl = String(snapshot.serverUrl || "")
    for (var i = 0; i < parsed.profiles.length; i++) {
      var profile = parsed.profiles[i]
      if (profile.active && activeUrl !== "" && !fixture && serverCache[profile.name] !== activeUrl) rememberServer(profile.name, activeUrl)
    }
    return Model.netbirdServers(parsed, activeUrl)
  }

  function rememberServer(profile, url) {
    var next = JSON.parse(JSON.stringify(serverCache))
    if (url === "") delete next[profile]
    else next[profile] = url
    serverCache = next
    cacheWriter.run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\"",
                     "sh", cachePath, JSON.stringify(next)])
  }

  // Switching profiles means a fresh connection; a lapsed session on the
  // target profile turns into a browser sign-in.
  function switchServer(row) {
    startLogin(["sh", "-c", "netbird down >/dev/null 2>&1; netbird profile select \"$1\" && exec netbird up --no-browser", "sh", row.key],
               "Switching to " + row.name + "…", "Connected with " + row.name)
  }

  function removeServer(row) {
    run(["netbird", "profile", "remove", row.key], "Removing " + row.name + "…", "Removed " + row.name, function(code) {
      if (code === 0) root.rememberServer(row.key, "")
    })
  }

  function addServer(first, second) {
    var profile = String(first || "").trim()
    if (profile === "") return "Name the profile"
    if (!/^[A-Za-z0-9._-]+$/.test(profile)) return "Profile names take letters, digits, dot, dash, underscore"
    for (var i = 0; i < servers.length; i++)
      if (servers[i].key === profile) return "A profile named " + profile + " already exists"
    var management = Model.normalizeServerUrl(second, 443)
    if (management === "") return "Enter the management URL"
    rememberServer(profile, management)
    var started = startLogin(["sh", "-c",
      "netbird profile add \"$1\" && { netbird down >/dev/null 2>&1; netbird profile select \"$1\"; } "
        + "&& exec netbird up --no-browser --management-url \"$2\" --admin-url \"$3\"",
      "sh", profile, management, Model.netbirdAdminUrl(management)],
      "Adding " + profile + "…", "Connected with " + profile)
    return started ? "" : "Busy, try again in a moment"
  }

  Command { id: cacheWriter }
}
