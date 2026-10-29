import QtQuick
import Quickshell
import "Model.js" as Model

Provider {
  id: root
  providerId: "tailscale"
  name: "Tailscale"
  binary: "tailscale"
  serviceUnit: "tailscaled.service"
  serversLabel: "Control server"
  serverForm: ({
    title: "Add a control server",
    presets: [{ label: "Tailscale", url: Model.tailscaleOfficialUrl }, { label: "Self-hosted", url: "" }],
    firstLabel: "Nickname (optional)",
    firstRequired: false,
    secondLabel: "Server URL, e.g. https://headscale.example.com",
    secondRequired: true,
    submitLabel: "Add & sign in"
  })

  function statusArgv() { return ["timeout", "-k", "2", "8", "tailscale", "status", "--json"] }

  function parseStatus(code, out, err) {
    // A stopped or signed-out tailscaled still prints its state as JSON.
    if (out.trim().charAt(0) === "{") return Model.tailscaleSnapshot(out, Date.now())
    if (code === 124 || /tailscaled|failed to connect|connection refused/i.test(err))
      return Model.emptySnapshot("daemon-down")
    return Model.emptySnapshot("error", firstLine(err) || "tailscale status failed")
  }

  function turnOn() {
    run(["tailscale", "up"], "Connecting…", "", function(code, out, err) {
      if (code !== 0 && /operator|access denied|permission/i.test(err)) {
        root.setupText = "Your user isn't allowed to control Tailscale yet."
        root.setupLabel = "Allow"
      }
    })
  }

  function turnOff() {
    run(["tailscale", "down"], "Disconnecting…", "", function(code, out, err) {
      if (code !== 0 && /operator|access denied|permission/i.test(err)) {
        root.setupText = "Your user isn't allowed to control Tailscale yet."
        root.setupLabel = "Allow"
      }
    })
  }

  function loginArgv() { return ["tailscale", "up"] }

  // Every account Tailscale is signed into keeps its own control server, so
  // the accounts are the server list.
  function serversArgv() {
    return ["sh", "-c", "tailscale switch --list --json; printf '\\n---prefs---\\n'; tailscale debug prefs"]
  }
  function parseServers(code, out, err) { return Model.tailscaleServers(out) }

  function switchServer(row) {
    run(["tailscale", "switch", row.key], "Switching to " + row.name + "…", "Switched to " + row.name)
  }

  function removeServer(row) {
    run(["tailscale", "switch", "remove", row.key], "Removing " + row.name + "…", "Removed " + row.name)
  }

  // `tailscale login` adds an account on that server and signs it in.
  function addServer(first, second) {
    var url = Model.normalizeServerUrl(second, 0)
    if (url === "") return "Enter the server's URL"
    var argv = ["tailscale", "login", "--login-server=" + url]
    var nickname = String(first || "").trim()
    if (nickname !== "") argv.push("--nickname=" + nickname)
    var host = Model.hostOf(url)
    return startLogin(argv, "Adding " + host + "…", "Signed in to " + host) ? "" : "Busy, try again in a moment"
  }

  // Makes this user Tailscale's operator, once, behind a polkit prompt.
  function setup() {
    var user = Quickshell.env("USER") || ""
    if (user === "") return
    run(["pkexec", "tailscale", "set", "--operator=" + user], "Waiting for authorization…",
        "You can now control Tailscale from the bar", function(code) {
      if (code === 0) {
        root.setupText = ""
        root.setupLabel = ""
      }
    })
  }
}
