# Service Authority

| Concern | Owner | Readers | Writers |
|---------|-------|---------|---------|
| Job definitions | jobs | tracking (token RPC), evaluations (FK check) | jobs |
| Applications & candidates | jobs | tracking (board join), evaluations (existence check) | jobs |
| Pipeline definitions & stages | pipeline | tracking (stage lookup), evaluations (stage FK) | pipeline |
| Pipeline state & history | tracking | jobs (token RPC, read-only) | tracking |
| Actions & statuses | tracking | — | tracking |
| Evaluations & templates | evaluations | tracking (signal RPC) | evaluations |
| Signals | evaluations | tracking (`get_action_signal_status` RPC) | evaluations |
| Auth & tenancy | auth | all services | auth |
| Interview scheduling (future) | interview | tracking | interview |
