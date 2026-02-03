# fn-45-comprehensive-documentation-overhaul.4 Document ephemeral vs persistent usage patterns

## Description
Create a usage patterns guide that explicitly documents THREE primary usage modes that match actual ContainAI behavior. Users currently have to piece this together from lifecycle.md and various hints.

**Size:** M
**Files:** `docs/usage-patterns.md` (new)

## Approach

1. **Disposable Container, Persistent Preferences** section (DEFAULT behavior):
   - When to use: most common - development work with shared preferences
   - Workflow: `cai` → work → `cai stop --remove`
   - Data handling: **container removed, volume preserved** (this is the reality per lifecycle.md:165-166)
   - Container: recreated each session
   - Volume: persists agent credentials, plugins, configuration
   - Flags: `--fresh` to force container recreation

2. **Fully Ephemeral** section (advanced):
   - When to use: untrusted code, CI, true isolation
   - Workflow: `cai` → work → `cai stop --remove` → delete volume manually
   - Data handling: EVERYTHING deleted including volume
   - **Volume deletion command** (correct syntax):
     ```bash
     # Get volume name (output is: value<TAB>source)
     cai config get data_volume
     # Example output: myproject-abc123    workspace:/path/.containai.toml

     # Delete volume (extract just the value before the tab)
     docker volume rm "$(cai config get data_volume | cut -f1)"

     # Or manually: note the volume name from the first command
     docker volume rm myproject-abc123
     ```
   - Flags: Document that volume deletion is manual (no `--remove-volume` flag exists)

3. **Long-lived Persistent Environment** section:
   - When to use: ongoing projects, heavily customized environments
   - Workflow: `cai` → work → `cai stop` → resume later with `cai`
   - Data handling: both container AND volume persist
   - Flags: default `cai stop` (no --remove)

4. **Comparison table**: THREE columns showing all patterns

5. **Mermaid decision flowchart** (REQUIRED):
   - Help users choose between the THREE patterns
   - Decision tree based on: "Do you need container persistence?" → "Do you need volume persistence?"
   - Include `accTitle` and `accDescr` for accessibility

6. **Migration scenarios**:
   - "I used disposable but want to keep container running" → just use `cai stop` instead
   - "I want to truly start fresh" → `cai stop --remove && docker volume rm "$(cai config get data_volume | cut -f1)"`
   - "I want container recreation but keep my creds" → `cai --fresh` or `cai stop --remove && cai`

7. Reference existing content:
   - `docs/lifecycle.md:165-166` (stop behaviors)
   - `docs/lifecycle.md:228-231` (cleanup matrix)
   - `docs/sync-architecture.md` (what syncs)

## Key context

**CRITICAL**: Per `docs/lifecycle.md:165-166`:
- `cai stop` = Stops container (keeps container and volume)
- `cai stop --remove` = Removes container **(keeps volume)**

This means "ephemeral" in ContainAI is NOT truly ephemeral by default - the volume always persists unless explicitly deleted.

**cai config get output format** (per src/containai.sh:2920):
- Output is `value<TAB>source` format
- Example: `myvolume	workspace:/path/.containai.toml`
- Use `cut -f1` to extract just the value

Key insight from lifecycle.md: containers are "persistent workspaces" by default, but the persistence level is controllable.

## Acceptance
- [ ] **THREE patterns documented** (not two): disposable+persist-vol, fully-ephemeral, long-lived
- [ ] Disposable pattern accurately states volume persists on `--remove`
- [ ] Fully ephemeral pattern documents correct volume deletion command with `cut -f1`
- [ ] Long-lived pattern documented with complete workflow
- [ ] Comparison table showing THREE patterns side-by-side
- [ ] **Mermaid decision flowchart** for choosing pattern (REQUIRED, include `accTitle`/`accDescr`)
- [ ] Migration scenarios covered (at least 3)
- [ ] Cross-references to lifecycle.md and sync-architecture.md
- [ ] Examples using actual cai commands with correct syntax
- [ ] Diagram renders correctly on GitHub

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
