const { REF, gh, repoPath, requireUser, send } = require('../lib/common')

async function loadPacks() {
  let names = []
  try {
    const dir = await gh(repoPath('/contents/modpacks?ref=' + REF))
    names = dir.filter(x => x.type === 'dir').map(x => x.name)
  } catch (e) {
    if (e.status !== 404) throw e
  }
  if (!names.includes('vanilla')) names.unshift('vanilla')
  return Promise.all(names.map(async name => {
    let meta = {}
    try { meta = JSON.parse(await gh(repoPath(`/contents/modpacks/${name}/meta.json?ref=${REF}`), {}, true)) } catch (e) {}
    return { name, meta }
  }))
}

async function loadRuns() {
  const j = await gh(repoPath('/actions/runs?per_page=40'))
  return j.workflow_runs
    .filter(r => /start-server|manage-modpack/.test(r.path || ''))
    .map(r => ({ id: r.id, path: r.path, display_title: r.display_title, status: r.status, conclusion: r.conclusion, html_url: r.html_url, created_at: r.created_at }))
}

module.exports = async (req, res) => {
  try {
    const s = await requireUser(req, res)
    if (!s) return
    if (req.query.runs) return send(res, 200, { runs: await loadRuns() })
    const [packs, runs] = await Promise.all([loadPacks(), loadRuns()])
    send(res, 200, { me: { id: s.id, name: s.name, owner: s.owner }, packs, runs })
  } catch (e) {
    send(res, 500, { error: e.message })
  }
}
