# TexasARNG.com — Units, Badges, Awards & Personnel Assignment System

A dark, professional personnel-administration application for the Texas Army National Guard
roleplay platform. Units, badges, awards and assignments are **real database entities** — the
admin panel is the only thing anyone needs to touch to add more.

```
texasarng/
├── server/          Express + SQLite REST API (RBAC, audit log, image uploads)
│   ├── src/
│   │   ├── schema.sql          full relational schema
│   │   ├── seed.js             bootstrap units / badges / awards / roles / demo users
│   │   ├── lib/permissions.js  canonical permission catalogue
│   │   └── routes/             auth, users, units, badges, awards, assignments, admin
│   ├── scripts/generate-placeholders.js
│   └── test/e2e.js             43-check end-to-end verification
└── client/          React + Vite SPA
```

## Getting started

```bash
npm run install:all      # installs server + client deps
npm run seed             # creates data/texasarng.db and loads the catalogues
npm --prefix server run  seed        # (same thing, if you prefer)
node server/scripts/generate-placeholders.js   # optional placeholder artwork

npm run dev              # API on :4000, Vite dev server on :5173
```

For a single-process production run:

```bash
npm run build            # builds the SPA into client/dist
npm start                # Express serves the API *and* the built SPA on :4000
```

### Seeded accounts

| Login      | Password       | Role          |
|------------|----------------|---------------|
| `jdavis`   | `Admin!2345`   | Administrator |
| `mreyes`   | `Change!2345`  | Officer       |
| `tkline`   | `Change!2345`  | Personnel NCO |
| `rnguyen`  | `Change!2345`  | Member        |

Change these before going anywhere near production, and set `JWT_SECRET`.

### Environment

Copy `server/.env.example` to `server/.env`:

| Variable            | Default                | Purpose                               |
|---------------------|------------------------|---------------------------------------|
| `PORT`              | `4000`                 | API port                              |
| `JWT_SECRET`        | dev placeholder        | **Set this in production**            |
| `JWT_EXPIRES`       | `12h`                  | Session lifetime                      |
| `DB_FILE`           | `server/data/…​.db`     | SQLite database location              |
| `UPLOAD_DIR`        | `server/uploads`       | Where badge/award/unit images land    |
| `MAX_UPLOAD_BYTES`  | `2097152` (2 MB)       | Upload size limit                     |
| `CORS_ORIGIN`       | reflect request origin | Lock down in production               |

## Data model

```
users ──┬── primary_unit_id ──► units
        ├── role_id ──► roles ──► role_permissions ──► permissions
        ├── user_badges ──► badges          (many-to-many, UNIQUE(user,badge))
        ├── user_awards ──► awards          (many-to-many, ordered, repeat-aware)
        └── unit_command ──► units          (command appointments)

audit_logs — actor, target, action, entity, item, timestamp, notes
```

* **Soft delete everywhere.** `DELETE /api/units/:id`, `/api/badges/:id` and `/api/awards/:id`
  set `active = 0` and report how many records still reference the row. Nothing referenced is
  ever destroyed.
* **Duplicate protection.** `user_badges` has a `UNIQUE(user_id, badge_id)` constraint. Awards
  use a database trigger that blocks repeats unless the award's `allow_multiple` flag is set
  (oak-leaf-cluster style awards), so no code path — API or direct SQL — can create a duplicate.
* **Award order.** `user_awards.sort_order` lets administrators arrange awards in order of
  precedence; the profile renders them in that order.

## Permissions

Defined once in `server/src/lib/permissions.js` and enforced by `requirePermission()` on every
route:

```
view_units  manage_units  assign_units
view_badges manage_badges assign_badges
view_awards manage_awards assign_awards
view_user_awards  remove_user_awards
view_personnel    manage_personnel
manage_roles  view_audit_logs  manage_settings  view_cad  view_radio  manage_announcements
```

The frontend hides navigation and buttons using the same keys, but **that is cosmetic only** —
the API re-checks every request, and the e2e suite asserts that a Member account receives `403`
on assign, create and delete operations even though the UI never offers them.

## The assignment workflow

`POST /api/assignments` is the single entry point behind the "Assign to User" panel:

```json
{ "user_id": 5, "type": "badge" | "award" | "unit", "item_id": 12, "notes": "Class 04-26" }
```

One request: validates the permission, checks for duplicates, writes the assignment, writes the
audit-log row **in the same transaction**, and returns the user's complete refreshed badge/award/
unit state so the panel and profile update without a page reload.

```
Admin → Awards & Badges → select user → Badge/Award/Unit → select item → ASSIGN
      → DB row + audit entry → profile, directory, unit roster and CAD context all reflect it
```

## Images

Badge, award and unit artwork is uploaded through the admin panel. Uploads are validated by MIME
type (PNG, WebP, SVG, JPEG), capped at 2 MB, and raster images are normalised to a 512×512
transparent-safe WebP so every badge renders at a consistent size. Filenames are randomised and
the path is stored on the database row.

`server/scripts/generate-placeholders.js` draws simple original SVG marks for everything in the
catalogue so the UI has consistent artwork out of the box. Nothing is downloaded or scraped —
replace them with official imagery through the upload control when you have it.

## Extending it

Adding a unit, badge, award, role or permission grant is an admin-panel action, not a code change:

* **New unit** → Units → Manage Units → Add Unit
* **New badge / award** → Awards & Badges → Add Badge / Add Award (pick a type or category)
* **New role** → Roles & Permissions
* **New badge type or award category** → add the string to the `categories` array in
  `server/src/routes/badges.js` / `awards.js` and the matching list in the client. The
  catalogue router itself (`routes/catalog.js`) is generic — calling `makeCatalogRouter()` again
  gives you a whole new catalogue (qualifications, ribbons, personnel categories) with CRUD,
  search, filtering, image upload, soft delete and audit logging already wired.

## Verification

```bash
npm --prefix server run test:e2e
```

Boots against a running API and asserts 43 behaviours: authentication, catalogue loading, search
and filters, badge/award/unit assignment, duplicate rejection, repeat-award allowance, permission
denial for non-admins, profile/directory/roster propagation, audit-log contents, removal, soft
delete and runtime extensibility.
