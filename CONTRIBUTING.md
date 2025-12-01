# Contributing Guidelines

## Commit Message Format (Conventional Commits)

Kami menggunakan **Conventional Commits**:
https://www.conventionalcommits.org/

### Format:

`<type>`(optional scope): `<description>`

### Types yang digunakan:

- **feat** → menambah message / RPC / enum / API baru
- **fix** → memperbaiki bug pada proto
- **refactor** → merapikan struktur proto tanpa mengubah behavior
- **docs** → komentar, README, perubahan CHANGELOG
- **chore** → update tooling, CI, workflow, dependency
- **perf** → optimisasi API
- **test** → menambah / ubah test pada code generator

### Example:

feat(subscription): add trial_balance_cents

fix(invoice): correct enum type for InvoiceStatus

docs: update CHANGELOG for v0.2.0

refactor: normalize field names across product.proto
