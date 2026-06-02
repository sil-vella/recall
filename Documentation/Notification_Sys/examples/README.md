# Global broadcast message examples

Reference JSON for [`global_broadcast_messages`](../NOTIFICATION_SYSTEM_FLOW.md#11-global-broadcast-messages-rank-targeted-stats-envelope) — **not** applied to local or VPS Mongo automatically.

| File | Purpose |
|------|---------|
| [global_broadcast_messages.examples.json](./global_broadcast_messages.examples.json) | Reference copy of the app-update row (see [NOTIFICATION_SYSTEM_FLOW.md](../NOTIFICATION_SYSTEM_FLOW.md) for other deeplink shapes) |

**Production / sync seed:** [`playbooks/00_local/files/global_broadcast_messages.json`](../../../playbooks/00_local/files/global_broadcast_messages.json)

To try an example in dev or production:

1. Copy one or more `messages` entries into the playbook seed file (assign a **new** 24-character hex `_id` if the row is new).
2. Run `playbooks/00_local/sync_global_broadcast_messages.yml` (local) or `playbooks/rop01/sync_global_broadcast_messages.yml` (VPS).

Re-syncing after removing rows from the seed **deletes** those documents from Mongo (orphan cleanup).
