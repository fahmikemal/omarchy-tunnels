import QtQuick
import Quickshell.Io

// One CLI call at a time. run(argv, done) calls done(exitCode, stdout, stderr)
// once the process has exited and both streams are drained, whichever of the
// three lands last.
Item {
  id: root
  visible: false

  readonly property bool running: process.running || drainTimer.running

  property var _done: null
  property bool _exited: false
  property bool _outDone: false
  property bool _errDone: false
  property int _exitCode: 0

  function run(argv, done) {
    if (running) return false
    _done = done || null
    _exited = false
    _outDone = false
    _errDone = false
    process.command = argv
    process.running = true
    return true
  }

  function stop() {
    if (process.running) process.running = false
  }

  function _finish() {
    if (!_exited || (!_outDone || !_errDone) && drainTimer.running) return
    drainTimer.stop()
    var done = _done
    _done = null
    _exited = false
    if (done) done(_exitCode, String(out.text || ""), String(err.text || ""))
  }

  // A stream that never reports its end must not strand the callback.
  Timer {
    id: drainTimer
    interval: 400
    onTriggered: root._finish()
  }

  Process {
    id: process
    stdout: StdioCollector {
      id: out
      waitForEnd: true
      onStreamFinished: { root._outDone = true; root._finish() }
    }
    stderr: StdioCollector {
      id: err
      waitForEnd: true
      onStreamFinished: { root._errDone = true; root._finish() }
    }
    onExited: function(exitCode) {
      root._exitCode = exitCode
      root._exited = true
      drainTimer.restart()
      root._finish()
    }
  }
}
