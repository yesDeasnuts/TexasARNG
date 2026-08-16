# Deploying TexasARNG.com

Two separate things, often confused:

* **GitHub** stores the code. It does not run it. GitHub Pages serves static
  files only — it cannot run the Node API, so logins, assignments and the
  database would not work there. Pages would give you a dead shell of the UI.
* **A host** runs the container. That is what your domain points at.

The flow is: push to GitHub → the host rebuilds and redeploys → your domain
serves the new version.

---

## 1. Put it on GitHub

```bash
cd texasarng
git init -b main
git add .
git commit -m "TexasARNG.com — units, badges, awards and assignment system"

# create an empty repo at github.com/new (no README, no .gitignore), then:
git remote add origin https://github.com/<you>/texasarng.git
git push -u origin main
```

`.gitignore` already excludes `node_modules/`, `server/data/` (the live
database), `server/uploads/` and `.env`. **Never commit `.env`** — it holds the
signing secret for every session on the site.

Pushing runs `.github/workflows/ci.yml`, which installs, builds, seeds, runs the
43-check end-to-end suite, checks graceful shutdown, confirms the server refuses
to boot with a weak `JWT_SECRET`, and builds the Docker image. A red X on a
commit means don't deploy it.

---

## 2. Pick something to run it

The app needs a **persistent disk**. The SQLite database and every uploaded
badge image live in `/data`. On a host without persistent storage, all of it is
erased on each deploy — accounts, assignments, artwork, everything.

| Host | Cost | Setup | Notes |
|---|---|---|---|
| **Render** | Free to try, **$7/mo** for a disk | Dashboard, no terminal | Easiest. Free tier has **no disk** and sleeps after 15 min idle — testing only. |
| **Fly.io** | ~$3–5/mo | CLI | Cheapest with real storage. Dallas region available. |
| **Railway** | ~$5/mo after trial credit | Dashboard | Nicest UI, GitHub push-to-deploy. |
| **VPS** | ~$5/mo | Most work | Full control. `docker-compose.yml` + Caddy handles TLS automatically. |

Config files for all four are in the repo. Pick one; ignore the rest.

### Render

1. New → **Blueprint** → connect the repo. It reads `render.yaml`.
2. `JWT_SECRET` is generated for you. Leave `CORS_ORIGIN` blank until your
   domain is live, then set it to `https://yourdomain.com`.
3. Deploy. First boot creates the database, seeds the catalogues and draws the
   placeholder artwork automatically.

To test on the free plan first, delete the `disk:` block and change
`plan: starter` to `plan: free` — and expect data loss on every deploy.

### Fly.io

```bash
fly launch --no-deploy --copy-config       # claims the app name
fly volumes create texasarng_data --size 1 --region dfw
fly secrets set JWT_SECRET="$(node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))")"
fly deploy
```

Edit `app = "texasarng"` in `fly.toml` if that name is taken.

Keep `min_machines_running = 1`. SQLite lives on one volume that only one
machine can mount — running two machines would corrupt data.

### Railway

New Project → Deploy from GitHub repo. It reads `railway.json`. Then:

* Add a **Volume** mounted at `/data`.
* Add variables: `JWT_SECRET` (generate a long random string), `DATA_DIR=/data`,
  `DB_FILE=/data/texasarng.db`, `UPLOAD_DIR=/data/uploads`, `NODE_ENV=production`.

### Your own VPS

```bash
cp server/.env.example .env      # set DOMAIN, ACME_EMAIL, JWT_SECRET
docker compose up -d
```

Caddy obtains and renews a Let's Encrypt certificate automatically once DNS
points at the server. The compose file also runs a nightly database backup.

---

## 3. The domain

**I can't buy this for you** — it needs your payment details. Register it
yourself at Cloudflare Registrar (at-cost, no markup, ~$10/yr), Namecheap, or
Porkbun.

### Before you buy: the name

`texasarng.com` reads as the official Texas Army National Guard. With the state
seal, real unit designations and real decorations on the page, a visitor could
reasonably think it is a government site. Registrars and hosts do act on
impersonation complaints about government entities, and losing a domain after
your community has settled on it is painful.

The app ships with an "unofficial roleplay community, not affiliated with…"
notice on the login screen and in the footer of every page, which is the
important part. A name that signals roleplay — `texasarng-rp.com`,
`txarng-rp.com` — lowers the risk further. Your call; the code works either way.

### DNS records

Every host gives you a hostname to point at. At your registrar, in DNS
settings:

| Type | Name | Value | Notes |
|---|---|---|---|
| `CNAME` | `www` | `your-app.onrender.com` (or `.fly.dev`, `.up.railway.app`) | |
| `A` | `@` | the IPv4 the host shows you | Apex domains usually can't be CNAMEs |
| `AAAA` | `@` | the IPv6, if given | Fly always gives one |

Cloudflare, Namecheap and Porkbun all support `ALIAS`/`ANAME` at the apex — if
yours does, use that instead of the `A` record and it tracks IP changes
automatically.

Then, on the host:

* **Render** → Settings → Custom Domains → add both `yourdomain.com` and `www.yourdomain.com`
* **Fly** → `fly certs add yourdomain.com` then `fly certs add www.yourdomain.com`
* **Railway** → Settings → Networking → Custom Domain

DNS usually propagates in minutes, occasionally up to 48 hours. HTTPS
certificates are issued automatically once the records resolve — you don't
need to buy one.

Finally set `CORS_ORIGIN=https://yourdomain.com` and redeploy.

---

## 4. Before you let anyone in

- [ ] `JWT_SECRET` is a long random value, set as a secret, not in the repo.
      The server refuses to boot in production without one.
- [ ] **Change every seeded password.** `jdavis` / `Admin!2345` is public — it's
      in this repo. Sign in, change it, then delete or rename the demo accounts.
- [ ] Remove the demo credentials hint from `client/src/pages/Login.jsx`.
- [ ] `CORS_ORIGIN` set to your domain.
- [ ] Persistent disk mounted at `/data` and confirmed — deploy twice and check
      your data is still there.
- [ ] A backup ran and you have restored one somewhere else at least once.
- [ ] Review the Roles & Permissions screen so members can't reach admin areas.

## 5. Backups

```bash
npm --prefix server run backup      # safe to run while the site is serving
```

Writes a consistent snapshot to `/data/backups/` and keeps the last 14. On the
VPS setup this runs nightly on its own. On Render/Fly/Railway, either add a
scheduled job or pull a copy down periodically:

```bash
fly ssh console -C "node server/scripts/backup.js"
fly sftp get /data/backups/texasarng-<stamp>.db
```

Uploaded artwork lives in `/data/uploads` and is **not** in the database
snapshot — archive that directory too.

**Restoring:** stop the app, replace `/data/texasarng.db` with the backup,
restore the uploads directory, start it again.

## 6. Updating

```bash
git add . && git commit -m "…" && git push
```

CI runs, the host rebuilds, and the new version goes live in a few minutes.
The database is untouched by deploys — `schema.sql` uses `CREATE TABLE IF NOT
EXISTS` and the seed upserts, so existing rows, assignments and uploads survive.

If you add a column later, write it as an `ALTER TABLE` guarded by a check
rather than editing `schema.sql` in place, or existing installs won't pick it up.

## 7. When to leave SQLite

SQLite is fine for a community of hundreds. Move to Postgres when you need more
than one instance running at once, or want the database to survive the host
disappearing. That means rewriting `server/src/db.js` and the `better-sqlite3`
calls in `routes/` — the SQL itself is close to portable, but the driver API is
synchronous and Postgres clients are not, so every query site needs `await`.
Budget a day, and do it before you have data you can't lose rather than after.
