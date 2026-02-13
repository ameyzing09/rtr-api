# Service Authority

| Concern | Owner | Readers | Writers |
|---------|-------|---------|---------|
| Job definitions | jobs | tracking (token RPC), evaluations (FK check), interview (display join) | jobs |
| Applications & candidates | jobs | tracking (board join), evaluations (existence check), interview (display join) | jobs |
| Pipeline definitions & stages | pipeline | tracking (stage lookup), evaluations (stage FK), interview (display join) | pipeline |
| Pipeline state & history | tracking | jobs (token RPC, read-only) | tracking |
| Actions & statuses | tracking | — | tracking |
| Evaluation templates | evaluations | tracking (signal RPC), interview (template validation) | evaluations |
| Evaluation instances & participants | evaluations | — | evaluations, interview (instance + participant creation) |
| Signals | evaluations | tracking (`get_action_signal_status` RPC) | evaluations |
| Auth & tenancy | auth | all services | auth |
| Interview intent, rounds & assignments | interview | tracking (signal RPC) | interview |
