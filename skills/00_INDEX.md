# 00 — Index

**Purpose:** Reading order by task, every document with its last-verified date, how to contribute, and a changelog (newest first).

**Confidence note:** verified against initial project state on 2026-11-23. The code wins (see 16).

---

## Reading Order by Task

| Task | Read First | Then |
|------|------------|------|
| New to the project | 01_ARCHITECTURE | 02_PROJECT_STRUCTURE, 03_CODE_STYLE |
| Making a change | 04_CHANGE_RULES | 05_DEBUGGING_PLAYBOOK, 06_FAILURE_STORIES |
| Debugging an issue | 05_DEBUGGING_PLAYBOOK | 06_FAILURE_STORIES, 04_CHANGE_RULES |
| Database work | 07_DATABASE | 04_CHANGE_RULES, 01_ARCHITECTURE |
| API work | 08_API | 04_CHANGE_RULES, 09_SECURITY |
| Security review | 09_SECURITY | 08_API, 07_DATABASE |
| Deploying | 10_DEPLOYMENT | 11_TESTING, 14_DEVELOPER_WORKFLOWS |
| Writing tests | 11_TESTING | 04_CHANGE_RULES, 05_DEBUGGING_PLAYBOOK |
| Performance tuning | 12_PERFORMANCE | 07_DATABASE, 08_API |
| Dependency update | 13_DEPENDENCIES | 04_CHANGE_RULES, 10_DEPLOYMENT |
| Onboarding a developer | 14_DEVELOPER_WORKFLOWS | 01_ARCHITECTURE, 02_PROJECT_STRUCTURE |
| Assessing risk | 15_KNOWN_LIMITATIONS | 06_FAILURE_STORIES, 16_ENGINEERING_PRINCIPLES |
| Understanding principles | 16_ENGINEERING_PRINCIPLES | 01_ARCHITECTURE, 06_FAILURE_STORIES |

---

## Document Inventory

| Doc | Title | Last Verified | Confidence |
|-----|-------|---------------|------------|
| 00 | Index | 2026-11-23 | verified |
| INBOX | Inbox | 2026-11-23 | verified |
| 01 | Architecture | 2026-11-23 | inferred from specs |
| 02 | Project Structure | 2026-11-23 | inferred from repo layout |
| 03 | Code Style | 2026-11-23 | inferred from git-guidelines |
| 04 | Change Rules | 2026-11-23 | inferred from db-design-choices |
| 05 | Debugging Playbook | 2026-11-23 | inferred |
| 06 | Failure Stories | 2026-11-23 | inferred |
| 07 | Database | 2026-11-23 | verified against db-design-choices.md |
| 08 | API | 2026-11-23 | inferred |
| 09 | Security | 2026-11-23 | inferred from business-logic |
| 10 | Deployment | 2026-11-23 | inferred from git-guidelines |
| 11 | Testing | 2026-11-23 | inferred |
| 12 | Performance | 2026-11-23 | inferred |
| 13 | Dependencies | 2026-11-23 | inferred |
| 14 | Developer Workflows | 2026-11-23 | inferred |
| 15 | Known Limitations | 2026-11-23 | inferred |
| 16 | Engineering Principles | 2026-11-23 | inferred |

---

## How to Contribute

See `INBOX.md` for the contribution template and instructions.

---

## Changelog

- **2026-11-23** — Initial creation of all skill documents from handoff.md and project specs