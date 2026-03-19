# DB Structure Alignment: Playbooks vs VPS Actual

## VPS actual (from inspect_db_structure.yml)

**Database:** `external_system`

| Collection        | Docs (VPS) | Created by                    |
|-------------------|------------|-------------------------------|
| user_modules      | 5          | Playbook 09/10 (fresh/update) |
| user_events       | 167        | **Application** (analytics)   |
| states            | 1          | **Application** (state_manager) |
| tournaments       | 1          | Playbook 10/09 update        |
| notifications     | 36         | Playbook 09/10               |
| users             | 510        | Playbook 09/10               |
| user_audit_logs   | 3          | Playbook 09/10                |

---

## Playbook-defined structure

### rop01 (VPS target)

| Playbook | Purpose | Collections created/ensured |
|----------|---------|-----------------------------|
| **09_setup_apps_database_structure.yml** | Fresh setup (empties DB first) | users, user_modules, user_audit_logs, notifications |
| **10_setup_apps_database_structure(update_existing).yml** | Non-destructive update | Ensures user_modules entries, user fields (role, is_comp_player, modules), notifications, **tournaments** |

### 00_local (localhost Docker)

| Playbook | Purpose | Collections created/ensured |
|----------|---------|-----------------------------|
| **10_setup_apps_database_structure.yml** | Fresh setup (empties DB first) | users, user_modules, user_audit_logs, notifications |
| **09_setup_apps_database_structure(update_existing).yml** | Non-destructive update | Same as rop01/10: modules, role, is_comp_player, notifications, tournaments |

**Naming quirk:** On rop01, **09** = fresh and **10** = update. On 00_local, **10** = fresh and **09** = update. Logic is the same; only numbering differs.

---

## Alignment summary

- **Playbooks create/ensure:** users, user_modules, user_audit_logs, notifications, tournaments (and indexes as in the playbooks).
- **Application creates at runtime:** `user_events` (analytics_service), `states` (state_manager). Not in any playbook; MongoDB creates these on first insert.
- **VPS** has exactly these seven collections, so the **actual VPS DB aligns with playbooks + app runtime**.

### Indexes (playbook-defined)

- **users:** email (unique), username, status, created_at, updated_at; (from update playbook) is_comp_player, role.
- **user_modules:** module_name (unique), status, created_at.
- **user_audit_logs:** user_id, action, timestamp, module.
- **notifications:** user_id, (user_id, read_at), created_at (-1).
- **tournaments:** _id, tournament_id (unique), name, status, type, format, start_date, matches.match_id, matches.status, matches.room_id.

No discrepancies found between playbook-defined structure and VPS. The rop01 and 00_local playbooks define the same schema; they only differ by target (VPS vs localhost) and the 09/10 numbering on 00_local.
