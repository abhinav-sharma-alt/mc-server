const crypto = require('crypto')

const OWNER = process.env.REPO_OWNER || 'abhinav-sharma-alt'
const REPO = process.env.REPO_NAME || 'mc-server'
const REF = process.env.REPO_BRANCH || 'main'

function need(name) {
  const v = process.env[name]
  if (!v) throw new Error('Server is missing the ' + name + ' environment variable')
  return v
}

const b64u = s => Buffer.from(s).toString('base64url')

function mac(body) {
  return crypto.createHmac('sha256', need('SESSION_SECRET')).update(body).digest('base64url')
}

function signSession(payload) {
  const body = b64u(JSON.stringify(payload))
  return body + '.' + mac(body)
}

function readSession(token) {
  if (!token) return null
  const [body, sig] = token.split('.')
  if (!body || !sig) return null
  const a = Buffer.from(sig)
  const b = Buffer.from(mac(body))
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null
  try {
    const p = JSON.parse(Buffer.from(body, 'base64url').toString())
    return p.exp > Date.now() / 1000 ? p : null
  } catch (e) {
    return null
  }
}

function parseCookies(req) {
  const out = {}
  for (const part of (req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=')
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim()
  }
  return out
}

function cookie(name, value, maxAge, path = '/') {
  return `${name}=${value}; Path=${path}; Max-Age=${maxAge}; HttpOnly; Secure; SameSite=Lax`
}

async function gh(path, opts = {}, raw = false) {
  const r = await fetch('https://api.github.com' + path, {
    ...opts,
    headers: {
      Accept: raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
      Authorization: 'Bearer ' + need('GITHUB_TOKEN'),
      'User-Agent': 'mc-dashboard',
      'X-GitHub-Api-Version': '2022-11-28',
      ...(opts.headers || {})
    }
  })
  if (!r.ok) {
    let m = ''
    try { m = (await r.json()).message } catch (e) {}
    const err = new Error('GitHub ' + r.status + (m ? ': ' + m : ''))
    err.status = r.status
    throw err
  }
  if (r.status === 204) return null
  return raw ? r.text() : r.json()
}

const repoPath = p => `/repos/${OWNER}/${REPO}${p}`

let idCache = { at: 0, ids: [] }

async function authorizedIds() {
  if (Date.now() - idCache.at < 30000) return idCache.ids
  let ids = []
  try {
    const text = await gh(repoPath('/contents/console/authorized_users.json?ref=' + REF), {}, true)
    ids = (JSON.parse(text).users || []).map(u => String(u.id))
  } catch (e) {
    if (e.status && e.status !== 404) throw e
  }
  idCache = { at: Date.now(), ids }
  return ids
}

async function isAuthorized(id) {
  if (String(id) === String(need('AUTHORIZED_USER_ID'))) return true
  return (await authorizedIds()).includes(String(id))
}

function send(res, status, obj) {
  res.setHeader('Cache-Control', 'no-store')
  res.status(status).json(obj)
}

async function requireUser(req, res) {
  const s = readSession(parseCookies(req).mc_session)
  if (!s || !(await isAuthorized(s.id))) {
    send(res, 401, { error: 'Not signed in' })
    return null
  }
  return s
}

function host(req) {
  return req.headers['x-forwarded-host'] || req.headers.host
}

function publicOrigin(req) {
  return process.env.PUBLIC_URL || 'https://' + host(req)
}

function sameOrigin(req) {
  const o = req.headers.origin
  if (!o) return false
  try { return new URL(o).host === host(req) } catch (e) { return false }
}

async function putFile(path, content, message) {
  for (let i = 0; i < 2; i++) {
    let sha
    try {
      sha = (await gh(repoPath(`/contents/${path}?ref=${REF}`))).sha
    } catch (e) {
      if (e.status !== 404) throw e
    }
    try {
      await gh(repoPath('/contents/' + path), {
        method: 'PUT',
        body: JSON.stringify({ message, content: Buffer.from(content).toString('base64'), branch: REF, ...(sha ? { sha } : {}) })
      })
      return
    } catch (e) {
      if (e.status !== 409 || i) throw e
    }
  }
}

async function dispatch(file, inputs) {
  await gh(repoPath(`/actions/workflows/${file}/dispatches`), { method: 'POST', body: JSON.stringify({ ref: REF, inputs }) })
}

module.exports = { REF, need, signSession, readSession, parseCookies, cookie, gh, repoPath, isAuthorized, send, requireUser, publicOrigin, sameOrigin, putFile, dispatch }
