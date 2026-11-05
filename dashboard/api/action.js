const crypto = require('crypto')
const { requireUser, sameOrigin, send, dispatch, putFile } = require('../lib/common')

const MANAGE_KEYS = new Set([
  'action', 'modpack_name', 'jar_url', 'is_zip', 'mrpack_slug', 'mrpack_version', 'curseforge_project_id', 'curseforge_file_id',
  'server_port', 'tunnel_address', 'java_version', 'memory_gb', 'server_jar', 'launch_mode', 'start_script', 'delete_world',
  'difficulty', 'gamemode', 'hardcore', 'mc_version', 'server_type', 'plugins', 'version'
])

module.exports = async (req, res) => {
  if (req.method !== 'POST') return send(res, 405, { error: 'POST only' })
  if (!sameOrigin(req)) return send(res, 403, { error: 'Bad origin' })
  try {
    const s = await requireUser(req, res)
    if (!s) return
    const b = req.body || {}

    if (b.type === 'dispatch') {
      const start = b.workflow === 'start'
      if (!start && b.workflow !== 'manage') return send(res, 400, { error: 'Unknown workflow' })
      const inputs = {}
      for (const [k, v] of Object.entries(b.inputs || {})) {
        if (start ? k !== 'modpack' : !MANAGE_KEYS.has(k)) continue
        const sv = String(v)
        if (sv.length <= 4000) inputs[k] = sv
      }
      if (start && !/^[a-z0-9][a-z0-9_-]*$/.test(inputs.modpack || '')) return send(res, 400, { error: 'Invalid modpack name' })
      await dispatch(start ? 'start-server.yml' : 'manage-modpack.yml', inputs)
      return send(res, 200, { ok: true })
    }

    if (b.type === 'stop') {
      await putFile('console/stop.txt', 'stop\n', 'console: request graceful stop (dashboard)')
      return send(res, 200, { ok: true })
    }

    if (b.type === 'command') {
      const cmd = String(b.command || '').trim()
      if (!cmd || cmd.length > 256 || /[\r\n]/.test(cmd)) return send(res, 400, { error: 'Invalid command' })
      await putFile('console/command.txt', `${crypto.randomUUID()}\n${cmd}\n`, 'console: queue command (dashboard)')
      return send(res, 200, { ok: true })
    }

    send(res, 400, { error: 'Unknown action type' })
  } catch (e) {
    send(res, 500, { error: e.message })
  }
}
