# SBH Project Rules

## Project Overview
**SBH** (Secure Boot Hardening) is a CachyOS-based security hardening framework supporting:
- NVIDIA driver 580 lock for Pascal architecture (GTX 1050 Ti, CC 6.1)
- Secure Boot integration (3 modes: disabled, UKI, TPM2+LUKS)
- Unified Kernel Image (UKI) automation
- System hardening via pacman hooks

**Repository:** `DystopianOS/dystopian-sbh`  
**Maintainer Context:** User on CachyOS with Garuda migration  
**Critical Constraint:** Driver 580 is FINAL for Pascal (590+ = no support)

---

## Code Quality Standards

### Documentation
- **Required:** All user-facing changes must include markdown docs in `/doc/`
- **Scope:** Architecture decisions, configuration procedures, troubleshooting
- **Format:** GFM (GitHub-Flavored Markdown) with code blocks and tables
- **Examples:**
  - `NVIDIA-PASCAL-DRIVER-LOCK.md` — Comprehensive driver lock guide
  - `NVIDIA-PASCAL-HELP.md` — Quick reference and FAQ

### Scripts (`/bin/`)
- **Style:** Bash 4.0+ compatible, no external DSL
- **Error Handling:** `set -e`, trap exit codes, informative error messages
- **Sudo Awareness:** Scripts requiring root must check `$EUID -ne 0` and fail gracefully
- **Comments:** Only for non-obvious logic; self-documenting code preferred
- **Testing:** Manual verification on CachyOS before commit

### Configuration Files (`/config/`, `/etc/`)
- **Syntax:** YAML/INI/Conf as appropriate to tool (pacman.conf, mkinitcpio.conf, etc.)
- **Comments:** Explain _why_ settings differ from defaults
- **Safety:** Never remove security controls without documented justification

### Python Code (`/python-dev/`)
- **Linter:** `ruff` (if used)
- **Type Checker:** `basedpyright` (if used)
- **Dependency Analyzer:** Check before/after changes
- **Tests:** Run existing tests; don't remove or weaken them

---

## Workflow: Adding a Feature

1. **Research Phase**
   - Document findings in markdown (don't commit to repo yet)
   - Test on actual system or in sandbox
   - Record breaking points and compatibility matrix

2. **Implementation Phase**
   - Create/edit files following code quality standards above
   - For Secure Boot changes: test with MOK keys and UKI
   - For driver changes: verify IgnorePkg prevents unwanted upgrades
   - Run linters/type-checkers on relevant code

3. **Testing Phase**
   - Verify on CachyOS (or equivalent test environment)
   - Check boot behavior if Secure Boot changes
   - Confirm NVIDIA driver doesn't auto-upgrade
   - Document any edge cases in markdown

4. **Documentation Phase**
   - Update or create `/doc/*.md` with:
     - What changed and why
     - Breaking points and caveats
     - Step-by-step reproduction
     - Links to relevant files
   - Update `README.md` if user-facing interface changed

5. **Commit & Review**
   - Commit message format:
     ```
     [category] Short description
     
     - Detailed change 1
     - Detailed change 2
     
     Fixes: (issue number if applicable)
     ```
   - Include Co-authored-by trailer for Copilot assists

---

## Critical Constraints

### NVIDIA Driver 580 Lock
- **Hard Constraint:** Pascal CC 6.1 only works with driver 580 (Final Release)
- **Support Timeline:**
  - Now – Aug 4, 2026: Full support (Game Ready, CUDA updates)
  - Aug 4, 2026 – Aug 4, 2028: LTSB only (security patches)
  - Aug 4, 2028: End of life (no updates)
- **Repository Issue:** CachyOS repos only serve 590+ drivers; 580 comes from Garuda/Chaotic-AUR
- **Solution:** IgnorePkg in `/etc/pacman.conf` prevents accidental 590+ upgrade

### CUDA Compatibility
- **Current:** CUDA 12.x (last version supporting Pascal CC 6.1)
- **Future:** CUDA 13.0+ requires Turing (CC 7.5+) minimum
- **Action:** Cannot upgrade CUDA without GPU upgrade

### Secure Boot Modes
| Mode | Signing | TPM | Auto-unlock | Use Case |
|------|---------|-----|-------------|----------|
| Disabled | No | No | N/A | Development |
| UKI | Yes | No | Manual | Standard |
| TPM2 | Yes | Yes | Yes | Production |

---

## Directory Structure

```
sbh/
├── .plan/
│   ├── rules.md                        (this file)
│   └── development-workflow.md         (workflow definitions)
├── bin/
│   ├── setup-mok-keys.sh              (MOK key generation)
│   ├── setup-dkms-signing.sh          (DKMS module signing)
│   ├── setup-uki-hook.sh              (UKI automation)
│   ├── setup-complete-uki.sh          (orchestrates all steps)
│   ├── verify-uki-setup.sh            (10-point verification)
│   └── enroll-mok.sh                  (Secure Boot enrollment)
├── config/
│   └── (pacman.conf snippets, mkinitcpio.conf examples, etc.)
├── doc/
│   ├── NVIDIA-PASCAL-DRIVER-LOCK.md   (20KB comprehensive guide)
│   ├── NVIDIA-PASCAL-HELP.md          (15KB quick reference)
│   ├── NVIDIA-INTEGRATION.md          (GPU tuning)
│   ├── NVIDIA-DRIVER-MODES.md         (LKM vs BUILTIN)
│   └── (other guides)
├── patches/
│   └── (kernel patches if needed)
└── README.md
```

---

## Common Tasks

### Lock NVIDIA Driver 580
```bash
# Already configured in /etc/pacman.conf
grep IgnorePkg /etc/pacman.conf

# Test lock works
pacman -Syu --print | grep nvidia
# Should show nothing
```

### Set Up Secure Boot + UKI
```bash
# Complete setup (all steps)
sudo /home/daen/Projects/sbh/bin/setup-complete-uki.sh

# Or individual steps:
sudo /home/daen/Projects/sbh/bin/setup-mok-keys.sh
sudo /home/daen/Projects/sbh/bin/setup-dkms-signing.sh
sudo /home/daen/Projects/sbh/bin/setup-uki-hook.sh
sudo /home/daen/Projects/sbh/bin/enroll-mok.sh
```

### Verify Setup
```bash
/home/daen/Projects/sbh/bin/verify-uki-setup.sh
```

### Manual UKI Regeneration (if hooks fail)
```bash
# Rebuild NVIDIA modules
sudo dkms install nvidia/580 -k 7.0.10-zen1-1-zen

# Sign modules
sudo /etc/dkms/post-install.sh 7.0.10-zen1-1-zen

# Regenerate UKI
sudo /usr/local/bin/generate-uki.sh
```

---

## Communication & Support

- **Issues:** Create GitHub issues with:
  - System: CachyOS kernel version, NVIDIA driver version
  - Error output (full stack trace if applicable)
  - Steps to reproduce
- **Questions:** Refer to `doc/NVIDIA-PASCAL-HELP.md` FAQ first
- **Contributions:** Follow workflow above; include docs with code

---

## Version History

- **2026-05-28:** Initial rules + workflow setup; driver 580 lock verified; UKI scripts created
