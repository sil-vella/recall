# Global broadcast message examples

Reference JSON for [`global_broadcast_messages`](../NOTIFICATION_SYSTEM_FLOW.md#11-global-broadcast-messages-rank-targeted-init-data-envelope) — **not** applied to local or VPS Mongo automatically.

| File | Purpose |
|------|---------|
| [global_broadcast_messages.examples.json](./global_broadcast_messages.examples.json) | Reference copy of **Welcome** + **App update** seed rows (same shape as production sync file) |

**Production / sync seed:** [`playbooks/00_local/files/global_broadcast_messages.json`](../../../playbooks/00_local/files/global_broadcast_messages.json)

| `msg_id` | `subtype` | Modal rule |
|----------|-----------|------------|
| `global_welcome_v1` | `welcome` | **Read-gated** — dismiss calls `global-mark-read` |
| `global_app_update_v1` | `app_update` | **Version-gated** via `data.target_version` — read ignored; modal while installed &lt; target |

Delivery: **`GET /userauth/dutch/get-init-data`** → `global_broadcast_messages`. See [§11.5](../NOTIFICATION_SYSTEM_FLOW.md#115-version-gated-app-update-vs-read-gated-welcome).

To deploy in dev or production:

1. Copy or edit `messages` in the playbook seed file (assign a **new** 24-character hex `_id` only for **new** campaigns).
2. **⚠️ REQUIRED:** Run the sync playbook after **every** seed edit — the app reads **Mongo**, not the JSON file:
   - Local: `ansible-playbook -i localhost, -c local playbooks/00_local/sync_global_broadcast_messages.yml`
   - VPS: `playbooks/rop01/sync_global_broadcast_messages.yml` (see [NOTIFICATION_SYSTEM_FLOW.md §11](../NOTIFICATION_SYSTEM_FLOW.md#110-seed-json-vs-mongo--sync-is-mandatory))

Re-syncing after removing rows from the seed **deletes** those documents from Mongo (orphan cleanup). Changing `_id` without removing the old doc causes **duplicate** Welcome modals.

**If modals or `target_version` behave wrong:** check Mongo still matches the seed (stale `target_version` in DB is a frequent cause).
