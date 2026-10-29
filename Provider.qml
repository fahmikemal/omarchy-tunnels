import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One VPN, whichever CLI is behind it. A provider finds its binary on PATH
// (no binary, no tab), polls a status snapshot in the shape Model.js
// documents, and runs the actions the panel asks for. Subtypes supply
// statusArgv(), parseStatus(), and turnOn() / turnOff(); everything the panel
// reads lives here.
Item {
  id: root
  visible: false

  property var settings: ({})
  // Demo mode: { status(), servers() } returning sample CLI output. While
  // set, the provider runs nothing and changes nothing.
  property var fixture: null
  property string providerId: ""
  property string name: ""
  property string binary: ""
  property string serviceUnit: ""
  // True while the panel is open on this provider's tab: poll fast then.
  property bool watching: false

  property bool installed: false
  property bool detected: false
  property var snapshot: Model.emptySnapshot("checking")
  property double nowMs: Date.now()

  // The switch shows intent the moment it is thrown, then hands back to the
  // reported state once a refresh confirms it (or the action fails).
  property int desired: -1
  property bool joinable: false
  property string message: ""
  property bool messageIsError: false
  property string loginUrl: ""
  property string loginDoneText: ""
  property string loginLastLine: ""

  // The control servers this VPN can use — Tailscale accounts, NetBird
  // profiles, ZeroTier roots — as rows (online = active), and the form that
  // adds one: { title, presets: [{ label, url }], firstLabel, firstRequired,
  // secondLabel, submitLabel }. A preset with an empty url asks for one.
  property var servers: []
  property var serverForm: null
  property string serversLabel: "Server"

  // Item already owns `state`, hence the prefix.
  readonly property string vpnState: snapshot.state
  readonly property bool connected: vpnState === "on"
  // What the switch shows once no action is pending; ZeroTier's switch is
  // its service, so it overrides this.
  property bool reportedOn: vpnState === "on" || vpnState === "connecting"
  readonly property bool switchOn: desired === -1 ? reportedOn : desired === 1
  // Set when the VPN needs a one-time grant before the bar can drive it.
  property string setupText: ""
  property string setupLabel: ""
  readonly property bool busy: actionCommand.running || loginProcess.running
  readonly property bool loginActive: loginProcess.running
  readonly property string adminUrl: String(setting("adminConsoleUrl", "")) || snapshot.adminUrl
  readonly property bool attention: vpnState === "needs-login" || vpnState === "needs-approval"
    || vpnState === "needs-access" || vpnState === "error" || setupText !== ""
  readonly property int intervalSec: Math.max(5, Number(setting("refreshIntervalSec", 20)) || 20)

  function setting(key, fallback) {
    var value = settings ? settings[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // --------------------------------------------------------- overridables

  function statusArgv() { return [] }
  function parseStatus(code, out, err) { return Model.emptySnapshot("error", err) }
  function turnOn() {}
  function turnOff() {}
  function setup() {}
  function rowAction(row, actionId) {}
  function join(networkId) {}
  function serversArgv() { return [] }
  function parseServers(code, out, err) { return servers }
  function switchServer(row) {}
  function removeServer(row) {}
  // Returns "" once the add is under way, or why it could not start.
  function addServer(first, second) { return "Not supported" }

  function statusLine() { return commonStatusLine() }

  function commonStatusLine() {
    var network = snapshot.network
    switch (vpnState) {
    case "checking": return "Checking…"
    case "on": return network !== "" ? "Connected · " + network : "Connected"
    case "off": return "Disconnected"
    case "connecting": return "Connecting…"
    case "needs-login": return loginActive ? "Waiting for browser sign-in…" : "Signed out"
    case "needs-approval": return "Waiting for approval"
    case "needs-access": return "Needs access"
    case "daemon-down": return "Service stopped"
    }
    return "Needs attention"
  }

  // ------------------------------------------------------------ lifecycle

  function detect() {
    if (fixture) {
      installed = true
      detected = true
      return refresh()
    }
    if (binary === "") return
    detectCommand.run(["sh", "-c", "command -v \"$1\"", "sh", binary], function(code) {
      var was = root.installed
      root.installed = code === 0
      root.detected = true
      if (root.installed && !was) root.refresh()
    })
  }

  function refresh() {
    if (!installed) return
    if (fixture) {
      snapshot = parseStatus(0, fixture.status(), "")
      if (fixture.servers) servers = parseServers(0, fixture.servers(), "")
      desired = -1
      return
    }
    statusCommand.run(statusArgv(), function(code, out, err) {
      root.nowMs = Date.now()
      var next = root.parseStatus(code, out, err)
      // An unchanged poll must not rebuild the list under the pointer.
      if (JSON.stringify(next) !== JSON.stringify(root.snapshot)) root.snapshot = next
      root.desired = -1
    })
    refreshServers()
  }

  function refreshServers() {
    var argv = serversArgv()
    if (!installed || argv.length === 0) return
    serversCommand.run(argv, function(code, out, err) {
      var next = root.parseServers(code, out, err)
      if (JSON.stringify(next) !== JSON.stringify(root.servers)) root.servers = next
    })
  }

  function toggle() {
    if (!installed || busy) return
    if (vpnState === "daemon-down") return startService()
    if (vpnState === "needs-login") return login()
    if (vpnState === "needs-access") return setup()
    if (switchOn) {
      desired = 0
      turnOff()
    } else {
      desired = 1
      turnOn()
    }
  }

  function startService() {
    if (serviceUnit === "") return
    // systemd asks polkit itself, so the shell's agent prompts for the password.
    run(["systemctl", "start", serviceUnit], "Starting " + name + "…", name + " service started")
  }

  function login() {
    if (snapshot.authUrl !== "") return openUrl(snapshot.authUrl)
    startLogin(loginArgv(), "Starting " + name + " sign-in…", name + " is signed in")
  }

  // Anything that may end in a browser sign-in — logging in, adding a server,
  // switching to a profile whose session lapsed — runs through here, so the
  // URL it prints is opened however it got there.
  function startLogin(argv, pending, done) {
    if (fixture) return demoOnly()
    if (!argv || argv.length === 0 || loginProcess.running || actionCommand.running) return false
    loginUrl = ""
    loginLastLine = ""
    loginDoneText = done || ""
    flash(pending, false)
    loginProcess.command = argv
    loginProcess.running = true
    loginTimeout.restart()
    return true
  }

  function loginArgv() { return [] }

  function cancelLogin() {
    if (loginProcess.running) loginProcess.running = false
    loginUrl = ""
  }

  // ------------------------------------------------------------- helpers

  // Run an action; refresh after it either way, since the CLI's exit code is
  // not the whole story (a half-applied change still shows in the status).
  function run(argv, pending, done, onExit) {
    if (fixture) return demoOnly()
    if (actionCommand.running) return false
    if (pending) flash(pending, false)
    return actionCommand.run(argv, function(code, out, err) {
      if (onExit) onExit(code, out, err)
      if (code === 0) {
        if (done) flash(done, false)
        else clearMessage()
      } else {
        root.desired = -1
        flash(firstLine(err) || firstLine(out) || (root.name + " command failed"), true)
      }
      root.refresh()
    })
  }

  function demoOnly() {
    flash("Demo mode: nothing was changed", false)
    return false
  }

  function firstLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line !== "") return line.length > 160 ? line.substring(0, 157) + "…" : line
    }
    return ""
  }

  function flash(text, isError) {
    message = String(text || "")
    messageIsError = !!isError
    messageTimer.interval = isError ? 9000 : 4000
    messageTimer.restart()
  }

  function clearMessage() {
    message = ""
    messageIsError = false
  }

  function openUrl(url) {
    if (String(url || "") !== "") Quickshell.execDetached(["omarchy-launch-browser", String(url)])
  }

  // -------------------------------------------------------------- plumbing

  Command { id: detectCommand }
  Command { id: statusCommand }
  Command { id: actionCommand }
  Command { id: serversCommand }

  // Login commands keep running until the browser round-trip completes, so
  // their output is read line by line for the URL to open.
  Process {
    id: loginProcess
    stdout: SplitParser { onRead: function(line) { root.handleLoginLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.handleLoginLine(line) } }
    onExited: function(exitCode) {
      loginTimeout.stop()
      if (exitCode === 0) {
        if (root.loginDoneText !== "") root.flash(root.loginDoneText, false)
        else root.clearMessage()
      } else if (root.loginUrl === "") {
        root.desired = -1
        root.flash(root.loginLastLine || root.name + " sign-in did not start", true)
      }
      root.loginUrl = ""
      root.refresh()
    }
  }

  function handleLoginLine(line) {
    var url = Model.firstUrl(line)
    if (url === "" && String(line).trim() !== "") loginLastLine = firstLine(line)
    if (url === "" || loginUrl !== "") return
    loginUrl = url
    flash("Finish signing in to " + name + " in your browser", false)
    openUrl(url)
  }

  Timer {
    id: loginTimeout
    interval: 5 * 60 * 1000
    onTriggered: root.cancelLogin()
  }

  Timer {
    id: messageTimer
    onTriggered: root.clearMessage()
  }

  Timer {
    interval: (root.watching ? 4 : root.intervalSec) * 1000
    running: root.installed
    repeat: true
    onTriggered: root.refresh()
  }

  // A VPN installed (or removed) while the shell runs gains (or loses) its
  // tab without a restart.
  Timer {
    interval: 120 * 1000
    running: root.detected
    repeat: true
    onTriggered: root.detect()
  }

  onWatchingChanged: if (watching) refresh()
  onFixtureChanged: {
    snapshot = Model.emptySnapshot("checking")
    detect()
  }
  Component.onCompleted: detect()
}
