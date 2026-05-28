# SBH Development Workflow

## Workflow Stages

### 1. Planning (`plan`)
**Goal:** Define scope and approach before implementation

**Entry Criteria:**
- User request received and understood
- Initial research completed
- Technical approach identified

**Activities:**
- Write plan.md in session state (not committed)
- Research findings documented in markdown
- Breaking points and constraints identified
- File/component changes listed

**Exit Criteria:**
- Plan is clear and documented
- Implementation approach is decided
- User has reviewed and approved (for significant changes)

**Ownership:** Copilot (initial), User (approval)

---

### 2. Active Implementation (`active`)
**Goal:** Execute the plan and write code

**Entry Criteria:**
- Plan approved
- All todos created and status tracked

**Activities:**
- Create/edit files following code quality standards
- Run linters and type-checkers as appropriate
- Test on CachyOS (manual or via scripts)
- Update git status tracking
- Heartbeat todo status in SQL

**Exit Criteria:**
- Code written and verified
- Linters/type-checkers passing
- Manual testing complete
- All todos marked `done`

**Ownership:** Copilot (execution), User (decisions)

**Todo Types in Session DB:**
- `uki-setup` — Secure Boot + UKI automation scripts
- `verify-lock` — Driver 580 lock verification
- `health-check` — System health checks
- `workflow-setup` — Project workflow files (.plan/)
- `add-feature` — New feature implementation
- `doc-update` — Documentation updates

---

### 3. Post-Implementation Verification (`post`)
**Goal:** Verify changes meet requirements before commit

**Entry Criteria:**
- All implementation todos `done`

**Activities:**
- Run full test suite (if exists)
- Verify no regressions
- Review file changes
- Check git diff for quality
- Ensure docs are updated

**Exit Criteria:**
- All tests passing (or manual verification complete)
- No unintended side effects
- Documentation complete
- Ready to commit

**Ownership:** Copilot (checks), User (approval)

---

## SQL Todo Lifecycle

### Creating Todos
```sql
INSERT INTO todos (id, title, description, status) VALUES
  ('feature-x', 'Implementing feature X', 'Do Y and Z', 'pending');
```

### Claiming a Todo
```sql
UPDATE todos SET status = 'in_progress' WHERE id = 'feature-x';
```

### Completing a Todo
```sql
UPDATE todos SET status = 'done' WHERE id = 'feature-x';
```

### Blocking a Todo (if prerequisites missing)
```sql
UPDATE todos SET status = 'blocked' WHERE id = 'feature-x';
```

### Viewing All Todos
```sql
SELECT id, title, status FROM todos ORDER BY status, created_at;
```

### Dependencies
```sql
-- Create: feature-x depends on feature-y
INSERT INTO todo_deps (todo_id, depends_on) VALUES ('feature-x', 'feature-y');

-- Query: Find todos with no blocking dependencies
SELECT t.* FROM todos t
WHERE t.status = 'pending'
AND NOT EXISTS (
  SELECT 1 FROM todo_deps td
  JOIN todos dep ON td.depends_on = dep.id
  WHERE td.todo_id = t.id AND dep.status != 'done'
);
```

---

## Branching & Commits

### Branch Strategy
- **Main Development:** Feature branches from `main`
- **Hotfixes:** From `main`, merged back immediately
- **Experiment:** Temporary branches, prefix with `exp/`

### Commit Message Format
```
[category] Short description (max 50 chars)

- Change 1 (what, why, impact)
- Change 2
- Change 3

Fixes: #issue_number (if applicable)
```

**Note:** Do NOT include Co-authored-by trailers. Commits should be attributed to the user only.

### Commit Categories
- `[docs]` — Documentation only
- `[scripts]` — New/updated shell scripts in `/bin/`
- `[config]` — Configuration files
- `[uki]` — Secure Boot/UKI changes
- `[nvidia]` — NVIDIA driver lock/CUDA changes
- `[fix]` — Bug fixes
- `[feat]` — New features

### Example Commits
```
[scripts] Add UKI setup orchestration script

- Create setup-complete-uki.sh to automate all UKI steps
- Includes MOK key generation, DKMS signing, pacman hooks
- Adds user prompts for MOK enrollment and reboot
- Verification checklist integrated

Fixes: #42

[docs] Update driver 580 documentation with UKI details

- Add "CachyOS UKI Best Practices" section (15KB)
- Include MOK key generation scripts
- Document 3 Secure Boot modes with procedures
- Add troubleshooting for module signing failures

[config] Lock NVIDIA 580xx packages in pacman.conf

- Add IgnorePkg directive to prevent 590+ auto-upgrade
- Protects Pascal GTX 1050 Ti from incompatibility
- Placement: [options] section (not multilib)
```

**Important:** None of these examples include Co-authored-by trailers. Commits are attributed to the user making the commit.

---

## Testing Strategy

### Manual Testing Checklist
For Secure Boot/UKI changes:
- [ ] UKI tools installed and available
- [ ] MOK keys generated without errors
- [ ] DKMS post-install hook executable
- [ ] Pacman hook triggers on kernel update (simulate: `sudo touch /usr/lib/modules/*/kernel`)
- [ ] systemd-boot entry created and readable
- [ ] (If enrolled) Reboot completes without errors
- [ ] (If enrolled) `mokutil --list-enrolled` shows key

For NVIDIA driver changes:
- [ ] Driver version locked (IgnorePkg working)
- [ ] `pacman -Syu --print` shows no nvidia upgrades
- [ ] CUDA version compatible with driver 580
- [ ] `nvidia-smi` runs (or fails gracefully if driver not loaded)

### Automated Testing (if Python involved)
```bash
# Run linters
ruff check --fix /path/to/code

# Run type checker
basedpyright /path/to/code

# Run tests
pytest /path/to/tests/
```

---

## Documentation Standards

### File Structure
```
doc/
├── NVIDIA-PASCAL-DRIVER-LOCK.md    (comprehensive, >15KB)
│   └── Sections: Overview, Installation, Secure Boot, UKI, Troubleshooting, References
├── NVIDIA-PASCAL-HELP.md           (quick reference, ~15KB)
│   └── Sections: FAQ, Quick Tasks, Troubleshooting, Use Cases, Checklist
├── README.md                       (project overview in repo root)
└── (other guides as needed)
```

### Content Requirements
- **What:** Clear description of feature/procedure
- **Why:** Rationale and constraints
- **How:** Step-by-step procedure with commands
- **Verify:** Commands to check success
- **Troubleshoot:** Common issues and solutions
- **References:** Links to external resources

### Markdown Conventions
- Headers: `# Main`, `## Section`, `### Subsection`
- Code blocks: Triple backticks with language hint
- Tables: GFM table syntax with alignment
- Lists: Bullet points (–) or numbered (1., 2.)
- Emphasis: **bold** for important, `code` for commands

---

## Integration with Copilot CLI

### Session Planning
1. User requests feature/fix
2. Copilot reads `.plan/rules.md` and development-workflow.md
3. Copilot creates todos in `session.db`
4. Todos tracked through implementation
5. Todos marked `done` on completion

### Workflow Gates
- **PRE:** Todos created, status `in_progress` before implementation
- **ACTIVE:** Code changes, tests run, linters pass
- **POST:** All todos `done`, no regressions, docs updated

### Session Output
- `.plan/` files: Rules and workflow definitions (persistent in repo)
- Session state: `session.db` todos, events (ephemeral, per session)
- Artifacts: `plan.md` in `~/.copilot/session-state/` (session-specific)

---

## FAQ

**Q: How do I track a large feature with multiple parts?**
A: Create separate todos for each part (e.g., `uki-mok`, `uki-dkms`, `uki-pacman-hook`). Use `todo_deps` to mark dependencies.

**Q: What if I find a bug while implementing a feature?**
A: If the bug is in code I'm changing, fix it as part of the feature. If it's pre-existing and unrelated, document it but don't fix (unless directly causing the failure).

**Q: Do I need to run all tests every time?**
A: Only run tests that touch your changed code. Full test suite should run before final commit.

**Q: Can I skip documentation?**
A: No. User-facing changes must include updated/new markdown in `/doc/`. Internal refactoring only needs inline comments.

**Q: What's the difference between `.plan/` and `plan.md`?**
A: `.plan/` files are project-wide rules (committed to repo). `plan.md` is per-session ephemeral planning (session state, not committed).

---

## Timeline & Milestones

### 2026-05-28: Initial Setup Complete
- ✅ Driver 580 lock verified (IgnorePkg configured)
- ✅ UKI setup scripts created (6 scripts, 540+ lines)
- ✅ Verification checklist implemented
- ✅ Project rules and workflow defined

### Upcoming: User Manual Setup
- [ ] Run `sudo /home/daen/Projects/sbh/bin/setup-complete-uki.sh`
- [ ] Enroll MOK in Secure Boot
- [ ] Test system updates don't upgrade driver
- [ ] Verify UKI on reboot

### Aug 4, 2026: Driver 580 Feature Support Ends
- ⚠ NVIDIA drops Game Ready drivers; LTSB only
- Action: Document status, no code changes needed (driver still works)

### Aug 4, 2028: Driver 580 End of Life
- ⚠ NVIDIA stops all support (including security patches)
- Action: GPU upgrade path starts; consider alternatives

---

## Contact & Support

- **Questions:** See `.plan/rules.md` for common tasks
- **Documentation:** Refer to `/doc/*.md` for detailed guides
- **Issues:** Create GitHub issue with system info and reproduction steps
- **Feedback:** User can update this workflow as needed
