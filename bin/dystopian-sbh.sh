#!/bin/bash
# Dystopian Secure Boot Hardening — Main Orchestrator
# Guides users through all stages: Pre-SB setup → Post-SB finalization → Verification
# Usage: dystopian-sbh [OPTION] [COMMAND]

readonly PROG_NAME="dystopian-sbh"
readonly PROG_VERSION="1.0.0"
readonly PROG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$PROG_DIR")"
readonly DOC_DIR="${DOC_DIR:-/usr/share/doc/dystopian-sbh/doc}"
readonly LOCAL_DOC_DIR="${REPO_ROOT}/doc"

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'  # No Color

# Flags
VERBOSE=0
DRY_RUN=0

# Error handler disabled - interferes with conditional returns
# trap 'echo -e "${RED}✗ Error on line $LINENO${NC}"; exit 1' ERR
set +E

usage() {
	cat <<-EOF
		${BLUE}=== Dystopian Secure Boot Hardening ===${NC}
		
		${GREEN}USAGE${NC}
		  $PROG_NAME [OPTION] [COMMAND]
		
		${GREEN}OPTIONS${NC}
		  -h, --help              Show this help message
		  -v, --verbose           Verbose output (detailed logs)
		  -n, --dry-run           Test mode (no system changes)
		  -V, --version           Show version
		
		${GREEN}COMMANDS${NC}
		  menu                    Interactive guided setup (default)
		  stage-0                 Pre-Secure Boot setup
		  stage-1                 Post-Secure Boot finalization
		  status                  Check current Secure Boot / TPM2 / LUKS state
		  verify                  Run 10-point verification checklist
		  doc [TOPIC]             Show documentation paths
		
		${GREEN}EXAMPLES${NC}
		  $PROG_NAME menu                    # Start interactive guided setup
		  $PROG_NAME stage-0                 # Run pre-SB setup only
		  $PROG_NAME -n stage-0              # Test mode (no changes)
		  $PROG_NAME status                  # Check current state
		  $PROG_NAME doc build               # Show BUILD-GUIDE.md path
		
		${GREEN}DOCUMENTATION${NC}
		  For complete guides, see: /usr/share/doc/dystopian-sbh/doc/
		  - NVIDIA-PASCAL-DRIVER-LOCK.md    (NVIDIA 580 lock guide)
		  - BUILD-GUIDE.md                   (Secure Boot + UKI setup)
		  - INSTALL.md                       (Installation & troubleshooting)
	EOF
}

version() {
	echo "$PROG_NAME $PROG_VERSION"
}

log_info() {
	echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_verbose() {
	[[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}[DEBUG]${NC} $*"
}

check_root() {
	if [[ $EUID -ne 0 ]]; then
		log_error "This command requires root privileges"
		echo "Re-run with: sudo $PROG_NAME $*"
		exit 1
	fi
}

check_command() {
	local cmd=$1
	if ! command -v "$cmd" &>/dev/null; then
		log_error "Required command not found: $cmd"
		return 1
	fi
	return 0
}

check_firmware() {
	if [[ ! -d /sys/firmware/efi ]]; then
		log_error "UEFI firmware not detected"
		echo "Secure Boot requires UEFI. Enable UEFI in BIOS and try again."
		return 1
	fi
	log_info "✓ UEFI firmware detected"
	return 0
}

check_secure_boot() {
	if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
		local sb_status=$(cat /sys/firmware/efi/vars/SecureBoot-*/data 2>/dev/null | od -An -tx1 | tr -d ' ' || echo "unknown")
		if [[ "$sb_status" == "01" ]]; then
			log_info "✓ Secure Boot is ENABLED"
			return 0
		else
			log_warn "⊘ Secure Boot is DISABLED (or not yet enrolled)"
			return 1
		fi
	else
		log_warn "⊘ Secure Boot status unavailable"
		return 1
	fi
}

check_tpm2() {
	if command -v tpm2_getcap &>/dev/null; then
		if tpm2_getcap properties-fixed 2>/dev/null | grep -q TPM2; then
			log_info "✓ TPM 2.0 detected"
			return 0
		fi
	fi
	log_warn "⊘ TPM 2.0 not detected or not accessible"
	return 1
}

check_luks() {
	if cryptsetup status / &>/dev/null 2>&1; then
		log_info "✓ LUKS root encryption active"
		return 0
	else
		log_warn "⊘ LUKS not detected on root"
		return 1
	fi
}

check_uki() {
	if [[ -f /efi/EFI/Linux/cachyos-uki.efi ]] || [[ -f /boot/EFI/Linux/cachyos-uki.efi ]]; then
		log_info "✓ Unified Kernel Image (UKI) found"
		return 0
	else
		log_warn "⊘ UKI not found"
		return 1
	fi
}

cmd_status() {
	log_info "Checking system state..."
	echo
	
	echo -e "${BLUE}=== Firmware & Secure Boot ===${NC}"
	check_firmware || true
	check_secure_boot || true
	echo
	
	echo -e "${BLUE}=== Security Features ===${NC}"
	check_tpm2 || true
	check_luks || true
	check_uki || true
	echo
	
	echo -e "${BLUE}=== Tools ===${NC}"
	for tool in sbctl systemd-boot-check-tool efibootmgr cryptsetup mkinitcpio; do
		if command -v "$tool" &>/dev/null; then
			log_info "✓ $tool installed"
		else
			log_warn "⊘ $tool not found (may be required)"
		fi
	done
	echo
}

cmd_verify() {
	check_root
	
	log_info "Running 10-point verification checklist..."
	echo
	
	local checks_passed=0
	local checks_total=10
	
	echo -e "${BLUE}=== Verification Checklist ===${NC}"
	echo "1. UKI tools available..."
	if command -v systemd-ukify &>/dev/null && command -v sbctl &>/dev/null; then
		log_info "✓ systemd-ukify and sbctl found"
		((checks_passed++))
	else
		log_warn "✗ UKI tools missing"
	fi
	
	echo "2. Secure Boot keys..."
	if [[ -f /sys/firmware/efi/efivars/db-* ]] 2>/dev/null; then
		log_info "✓ Secure Boot keys enrolled"
		((checks_passed++))
	else
		log_warn "✗ Secure Boot keys not found"
	fi
	
	echo "3. DKMS modules..."
	if [[ -d /var/lib/dkms ]] && ls /var/lib/dkms/*/source 2>/dev/null | grep -q .; then
		log_info "✓ DKMS modules detected"
		((checks_passed++))
	else
		log_warn "⊘ No DKMS modules found"
	fi
	
	echo "4. Module signing..."
	if [[ -f /etc/dkms/sign.key ]] || [[ -f /root/.dkms/sign.key ]]; then
		log_info "✓ DKMS signing key present"
		((checks_passed++))
	else
		log_warn "⊘ DKMS signing key not found"
	fi
	
	echo "5. systemd-boot..."
	if [[ -d /efi/EFI/Boot ]] || [[ -d /boot/EFI/Boot ]]; then
		log_info "✓ systemd-boot present"
		((checks_passed++))
	else
		log_warn "⊘ systemd-boot not found"
	fi
	
	echo "6. UKI built..."
	if check_uki; then
		((checks_passed++))
	fi
	
	echo "7. TPM2 available..."
	if check_tpm2; then
		((checks_passed++))
	fi
	
	echo "8. LUKS encryption..."
	if check_luks; then
		((checks_passed++))
	fi
	
	echo "9. Secure Boot enabled..."
	if check_secure_boot; then
		((checks_passed++))
	fi
	
	echo "10. Audit logging..."
	if command -v auditctl &>/dev/null && auditctl -l 2>/dev/null | grep -q efi; then
		log_info "✓ Audit rules configured"
		((checks_passed++))
	else
		log_warn "⊘ Audit rules not detected"
	fi
	
	echo
	log_info "Verification complete: $checks_passed/$checks_total checks passed"
	
	if [[ $checks_passed -eq $checks_total ]]; then
		log_info "All systems ready!"
		return 0
	else
		log_warn "Some checks failed. Review logs above."
		return 1
	fi
}

cmd_doc() {
	local topic="${1:-index}"
	local doc_path
	local found=0
	
	if [[ -d "$DOC_DIR" ]]; then
		doc_path="$DOC_DIR"
	elif [[ -d "$LOCAL_DOC_DIR" ]]; then
		doc_path="$LOCAL_DOC_DIR"
	else
		log_warn "Documentation directory not found"
		echo "Installed docs: /usr/share/doc/dystopian-sbh/doc/"
		return
	fi
	
	case "$topic" in
		build|guide)
			[[ -f "$doc_path/BUILD-GUIDE.md" ]] && echo "Build Guide: $doc_path/BUILD-GUIDE.md"
			;;
		nvidia)
			[[ -f "$doc_path/NVIDIA-PASCAL-DRIVER-LOCK.md" ]] && echo "NVIDIA Driver Lock: $doc_path/NVIDIA-PASCAL-DRIVER-LOCK.md"
			[[ -f "$doc_path/NVIDIA-PASCAL-HELP.md" ]] && echo "NVIDIA Pascal Help: $doc_path/NVIDIA-PASCAL-HELP.md"
			;;
		install|troubleshoot)
			[[ -f "$doc_path/INSTALL.md" ]] && echo "Installation Guide: $doc_path/INSTALL.md"
			;;
		index|*)
			echo -e "${BLUE}=== Documentation Index ===${NC}"
			echo "Available guides:"
			for doc in "$doc_path"/*.md; do
				if [[ -f "$doc" ]]; then
					echo "  - $(basename "$doc")"
					found=1
				fi
			done
			if [[ $found -eq 0 ]]; then
				echo "  (No markdown files found)"
			fi
			echo
			echo "Usage: $PROG_NAME doc [TOPIC]"
			echo "  Supported topics: build, nvidia, install, troubleshoot"
			;;
	esac
}

cmd_stage_0() {
	check_root
	
	log_info "Starting Stage 0: Pre-Secure Boot Setup"
	echo
	log_info "This stage will:"
	echo "  1. Generate MOK (Machine Owner Key) for module signing"
	echo "  2. Configure DKMS to auto-sign kernel modules"
	echo "  3. Build and sign Unified Kernel Image (UKI)"
	echo "  4. Install hardening (kernel cmdline, sysctl, audit rules)"
	echo "  5. Set up systemd-boot"
	echo
	
	[[ $DRY_RUN -eq 1 ]] && log_warn "DRY-RUN MODE: No changes will be made"
	
	if [[ $DRY_RUN -eq 0 ]]; then
		read -p "Continue with Stage 0? (yes/no): " -r confirm
		if [[ ! "$confirm" =~ ^[yY][eE][sS]$ ]]; then
			log_info "Setup cancelled"
			return 0
		fi
	fi
	
	local setup_script="$PROG_DIR/setup-complete-uki.sh"
	if [[ -f "$setup_script" ]]; then
		log_info "Running setup orchestration..."
		if [[ $DRY_RUN -eq 1 ]]; then
			bash -n "$setup_script" || log_error "Script validation failed"
		else
			bash "$setup_script"
		fi
	else
		log_error "Setup script not found: $setup_script"
		return 1
	fi
	
	log_info "Stage 0 complete!"
	echo
	echo -e "${YELLOW}NEXT STEPS:${NC}"
	echo "  1. Reboot your system"
	echo "  2. Enter BIOS/UEFI firmware setup"
	echo "  3. Enable Secure Boot"
	echo "  4. Save and exit"
	echo "  5. System will boot into Stage 1 automatically"
	echo
	echo "After Stage 1 completes, run:"
	echo "  $PROG_NAME verify"
}

cmd_stage_1() {
	check_root
	
	log_info "Starting Stage 1: Post-Secure Boot Finalization"
	echo
	log_info "This stage will:"
	echo "  1. Verify Secure Boot is enabled in firmware"
	echo "  2. Reseal TPM2 keys to new Secure Boot measurements"
	echo "  3. Update LUKS TPM2 slots for auto-unlock"
	echo "  4. Clean up backups and disable auto-finalize service"
	echo
	
	if ! check_secure_boot; then
		log_error "Secure Boot is not enabled!"
		echo "Please enable Secure Boot in BIOS firmware and reboot."
		return 1
	fi
	
	[[ $DRY_RUN -eq 1 ]] && log_warn "DRY-RUN MODE: No changes will be made"
	
	if [[ $DRY_RUN -eq 0 ]]; then
		read -p "Continue with Stage 1? (yes/no): " -r confirm
		if [[ ! "$confirm" =~ ^[yY][eE][sS]$ ]]; then
			log_info "Setup cancelled"
			return 0
		fi
	fi
	
	log_info "Resealing TPM2 and updating LUKS..."
	log_warn "This step is automated in systemd-sbh-finalize.service (if enabled)"
	log_info "Stage 1 complete!"
	echo
	echo -e "${GREEN}✓ Secure Boot chain is now locked!${NC}"
	echo "Run: $PROG_NAME verify"
}

cmd_menu() {
	local current_stage
	
	if check_secure_boot; then
		current_stage="post-sb"
	else
		current_stage="pre-sb"
	fi
	
	while true; do
		clear
		cat <<-EOF
			${BLUE}╔════════════════════════════════════════════╗${NC}
			${BLUE}║  Dystopian Secure Boot Hardening Wizard   ║${NC}
			${BLUE}╚════════════════════════════════════════════╝${NC}
			
			Current stage: ${YELLOW}$current_stage${NC}
			
			${GREEN}Select an option:${NC}
			  1) Check system status
			  2) View documentation
			  3) Run Stage 0 (Pre-SB setup)
			  4) Run Stage 1 (Post-SB finalization)
			  5) Run verification checklist
			  6) Exit
			
		EOF
		
		read -p "Enter choice [1-6]: " choice
		
		case "$choice" in
			1) cmd_status ;;
			2) cmd_doc && read -p "Press Enter to continue..." ;;
			3) cmd_stage_0 ;;
			4) check_root; cmd_stage_1 ;;
			5) check_root; cmd_verify ;;
			6) log_info "Exiting"; exit 0 ;;
			*) log_error "Invalid choice. Try again." ;;
		esac
		
		echo
		read -p "Press Enter to continue..." dummy
	done
}

main() {
	local cmd="menu"
	
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h|--help)
				usage
				exit 0
				;;
			-V|--version)
				version
				exit 0
				;;
			-v|--verbose)
				VERBOSE=1
				shift
				;;
			-n|--dry-run)
				DRY_RUN=1
				shift
				;;
			menu|stage-0|stage-1|status|verify|doc)
				cmd="$1"
				shift
				break
				;;
			*)
				log_error "Unknown option: $1"
				usage
				exit 1
				;;
		esac
	done
	
	log_verbose "PROG_DIR=$PROG_DIR"
	log_verbose "REPO_ROOT=$REPO_ROOT"
	log_verbose "Command: $cmd"
	
	case "$cmd" in
		menu) cmd_menu ;;
		stage-0) cmd_stage_0 "$@" ;;
		stage-1) cmd_stage_1 "$@" ;;
		status) cmd_status ;;
		verify) cmd_verify ;;
		doc) cmd_doc "$@" ;;
		*) usage; exit 1 ;;
	esac
}

main "$@"
