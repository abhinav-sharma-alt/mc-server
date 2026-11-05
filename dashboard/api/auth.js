const crypto = require('crypto')
const { need, signSession, parseCookies, cookie, isAuthorized, publicOrigin } = require('../lib/common')

module.exports = async (req, res) => {
  const action = req.query.action
  try {
    if (action === 'logout') {
      res.setHeader('Set-Cookie', cookie('mc_session', '', 0))
      res.writeHead(302, { Location: '/' })
      return res.end()
    }

    const redirectUri = publicOrigin(req) + '/api/auth?action=callback'

    if (action === 'login') {
      const state = crypto.randomBytes(16).toString('hex')
      res.setHeader('Set-Cookie', cookie('mc_oauth', state, 600, '/api/auth'))
      const q = new URLSearchParams({ client_id: need('DISCORD_CLIENT_ID'), response_type: 'code', redirect_uri: redirectUri, scope: 'identify', state })
      res.writeHead(302, { Location: 'https://discord.com/oauth2/authorize?' + q })
      return res.end()
    }

    if (action === 'callback') {
      const saved = parseCookies(req).mc_oauth
      if (!saved || saved !== req.query.state || !req.query.code) {
        res.writeHead(302, { Location: '/?err=state' })
        return res.end()
      }
      const tok = await fetch('https://discord.com/api/oauth2/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ client_id: need('DISCORD_CLIENT_ID'), client_secret: need('DISCORD_CLIENT_SECRET'), grant_type: 'authorization_code', code: req.query.code, redirect_uri: redirectUri })
      })
      if (!tok.ok) {
        res.writeHead(302, { Location: '/?err=discord' })
        return res.end()
      }
      const { access_token } = await tok.json()
      const me = await (await fetch('https://discord.com/api/users/@me', { headers: { Authorization: 'Bearer ' + access_token } })).json()
      if (!me.id || !(await isAuthorized(me.id))) {
        res.setHeader('Set-Cookie', cookie('mc_oauth', '', 0, '/api/auth'))
        res.writeHead(302, { Location: '/?err=not_authorized' })
        return res.end()
      }
      const session = signSession({
        id: me.id,
        name: me.global_name || me.username,
        owner: String(me.id) === String(need('AUTHORIZED_USER_ID')),
        exp: Math.floor(Date.now() / 1000) + 7 * 86400
      })
      res.setHeader('Set-Cookie', [cookie('mc_session', session, 7 * 86400), cookie('mc_oauth', '', 0, '/api/auth')])
      res.writeHead(302, { Location: '/' })
      return res.end()
    }

    res.statusCode = 400
    res.end('Unknown action')
  } catch (e) {
    res.writeHead(302, { Location: '/?err=server' })
    res.end()
  }
}
