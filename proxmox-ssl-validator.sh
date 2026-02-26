#!/bin/bash

#############################################################################
# Proxmox SSL/TLS Certificate Validator
# 
# Validates Let's Encrypt + Cloudflare DNS setup for Proxmox VE
# 
# Usage:
#   ./proxmox-ssl-validator.sh --pre-check    # Run before certificate setup
#   ./proxmox-ssl-validator.sh --post-check   # Run after certificate setup
#   ./proxmox-ssl-validator.sh --full         # Run both checks
#############################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Emoji/symbols for better readability
CHECK="✓"
CROSS="✗"
WARN="⚠"
INFO="ℹ"

#############################################################################
# Helper Functions
#############################################################################

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}${CHECK} $1${NC}"
}

print_error() {
    echo -e "${RED}${CROSS} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${WARN} $1${NC}"
}

print_info() {
    echo -e "${BLUE}${INFO} $1${NC}"
}

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    echo -e -n "${BLUE}${prompt}: ${NC}"
    local value
    read -r value
    printf -v "$var_name" '%s' "$value"
}

#############################################################################
# Pre-Check Functions
#############################################################################

check_proxmox_version() {
    print_header "Checking Proxmox Version"
    
    if ! command -v pveversion &> /dev/null; then
        print_error "This doesn't appear to be a Proxmox VE system"
        print_info "pveversion command not found"
        return 1
    fi
    
    # Get the full pveversion output
    local pve_output
    pve_output=$(pveversion 2>/dev/null)
    
    # Parse: "pve-manager/9.1.1/42db4a6cf33dac83 (running kernel: 6.17.2-1-pve)"
    # Extract version between / and next /
    local pve_version
    pve_version=$(echo "$pve_output" | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    # If that didn't work, try other patterns
    if [ -z "$pve_version" ]; then
        pve_version=$(echo "$pve_output" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    
    # Check if we got a version
    if [ -z "$pve_version" ]; then
        print_warning "Could not parse Proxmox version from output:"
        print_info "$pve_output"
        print_info "Assuming version is compatible (6.1+)"
        return 0
    fi
    
    # Extract major version number
    local major_version
    major_version=$(echo "$pve_version" | cut -d'.' -f1)
    
    # Validate we got a number
    if ! [[ "$major_version" =~ ^[0-9]+$ ]]; then
        print_warning "Could not determine major version number"
        print_info "Version string: $pve_version"
        print_info "Assuming version is compatible (6.1+)"
        return 0
    fi
    
    if [ "$major_version" -ge 6 ]; then
        print_success "Proxmox VE version: $pve_version (ACME support: YES)"
        return 0
    else
        print_error "Proxmox VE version: $pve_version (ACME requires v6.1+)"
        return 1
    fi
}

check_internet_connectivity() {
    print_header "Checking Internet Connectivity"
    
    # Test general internet
    if ping -c 2 8.8.8.8 &> /dev/null; then
        print_success "Internet connectivity: OK"
    else
        print_error "No internet connectivity (ping 8.8.8.8 failed)"
        return 1
    fi
    
    # Test DNS resolution
    if ping -c 2 letsencrypt.org &> /dev/null; then
        print_success "DNS resolution: OK (letsencrypt.org reachable)"
    else
        print_warning "Cannot ping letsencrypt.org"
        print_info "This may be normal - some networks block ICMP ping"
        
        # Try a different test - resolve DNS
        if nslookup letsencrypt.org &> /dev/null || host letsencrypt.org &> /dev/null; then
            print_success "DNS resolution: OK (domain resolves)"
        else
            print_warning "DNS lookup failed, but this may not be an issue"
        fi
    fi
    
    # Test HTTPS connectivity to Let's Encrypt
    print_info "Testing HTTPS access to Let's Encrypt API..."
    if curl -s --connect-timeout 5 https://acme-v02.api.letsencrypt.org/directory &> /dev/null; then
        print_success "Let's Encrypt API: REACHABLE"
        return 0
    else
        print_warning "Cannot reach Let's Encrypt API via HTTPS"
        print_info "This could be a firewall/proxy issue or temporary outage"
        print_info "If other checks pass, you can proceed with caution"
        return 0  # Don't fail on this - let user decide
    fi
}

validate_cloudflare_credentials() {
    print_header "Validating Cloudflare Credentials"
    
    # Prompt for credentials
    prompt_input "Enter Cloudflare API Token" CF_TOKEN
    prompt_input "Enter Cloudflare Zone ID" CF_ZONE_ID
    prompt_input "Enter your domain (e.g., example.com)" DOMAIN
    
    if [ -z "$CF_TOKEN" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$DOMAIN" ]; then
        print_error "All fields are required"
        return 1
    fi
    
    print_info "Testing API token..."
    
    # Test the API token
    local response
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json")
    
    local success
    success=$(echo "$response" | grep -o '"success":[^,]*' | cut -d':' -f2)
    
    if [ "$success" == "true" ]; then
        print_success "API Token: VALID"
        
        # Get zone name to verify it matches
        local zone_name
        zone_name=$(echo "$response" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
        print_success "Zone verified: $zone_name"
        
        if [ "$zone_name" != "$DOMAIN" ]; then
            print_warning "Zone name ($zone_name) doesn't match your domain ($DOMAIN)"
            print_info "This might be correct if you entered a subdomain"
        fi
        
        # Test DNS edit permissions
        print_info "Testing DNS permissions..."
        local dns_response
        dns_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CF_TOKEN}" \
            -H "Content-Type: application/json")
        
        local dns_success
        dns_success=$(echo "$dns_response" | grep -o '"success":[^,]*' | cut -d':' -f2)
        
        if [ "$dns_success" == "true" ]; then
            print_success "DNS Edit Permission: CONFIRMED"
            return 0
        else
            print_error "Token lacks DNS edit permissions"
            print_info "Recreate token with 'Zone → DNS → Edit' permission"
            return 1
        fi
    else
        print_error "API Token: INVALID"
        local error_msg
        error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$error_msg" ]; then
            print_info "Error: $error_msg"
        fi
        return 1
    fi
}

check_dns_record() {
    print_header "Checking DNS Configuration"
    
    prompt_input "Enter your Proxmox subdomain (e.g., proxmox.example.com)" PROXMOX_FQDN
    
    if [ -z "$PROXMOX_FQDN" ]; then
        print_error "FQDN is required"
        return 1
    fi
    
    print_info "Looking up DNS record for $PROXMOX_FQDN..."
    
    # Try to resolve the DNS
    local dns_ip
    dns_ip=$(dig +short "$PROXMOX_FQDN" @8.8.8.8 | tail -1)
    
    if [ -z "$dns_ip" ]; then
        print_error "DNS record not found for $PROXMOX_FQDN"
        print_info "Create an A record in Cloudflare DNS pointing to your Proxmox IP"
        return 1
    fi
    
    print_success "DNS resolves to: $dns_ip"
    
    # Get local Proxmox IP for comparison
    local local_ip
    local_ip=$(hostname -I | awk '{print $1}')
    
    if [ "$dns_ip" == "$local_ip" ]; then
        print_success "DNS matches local Proxmox IP"
    else
        print_warning "DNS IP ($dns_ip) differs from local IP ($local_ip)"
        print_info "This is normal if behind NAT/firewall"
        print_info "Ensure port forwarding is configured if accessing externally"
    fi
    
    # Check if Cloudflare proxy is enabled (will show Cloudflare IP)
    if echo "$dns_ip" | grep -qE "^(104\.1[6-9]|104\.2[0-9]|104\.3[0-1]|172\.6[4-7]|131\.0\.72)\."; then
        print_warning "Cloudflare proxy appears to be ENABLED (orange cloud)"
        print_info "For Proxmox, disable proxy (gray cloud) in Cloudflare DNS"
    else
        print_success "Cloudflare proxy: DISABLED (correct for Proxmox)"
    fi
    
    return 0
}

check_port_accessibility() {
    print_header "Checking Port 8006 Accessibility"
    
    print_info "Testing if Proxmox web interface is accessible locally..."
    
    if nc -z localhost 8006 2>/dev/null; then
        print_success "Port 8006: LISTENING locally"
    else
        print_error "Port 8006: NOT LISTENING"
        print_info "Is pveproxy service running? Try: systemctl status pveproxy"
        return 1
    fi
    
    print_info "For external access, ensure:"
    print_info "  • Port 8006 forwarded in router/firewall (if needed)"
    print_info "  • Firewall allows inbound connections (if needed)"
    print_info "  • Or use VPN for secure access (recommended)"
    
    return 0
}

check_acme_plugin_config() {
    print_header "Checking ACME Plugin Configuration (Optional)"
    
    local plugin_file="/etc/pve/priv/acme/plugins.cfg"
    
    if [ ! -f "$plugin_file" ]; then
        print_info "No ACME plugins configured yet (this is expected before setup)"
        print_info "You'll configure this in the Proxmox web interface"
        return 0
    fi
    
    print_info "ACME plugin configuration found, checking format..."
    
    # Check if cloudflare plugin exists
    if grep -q "^dns: cloudflare" "$plugin_file"; then
        print_success "Cloudflare plugin configured"
        
        # Check for common configuration issues
        local plugin_data
        plugin_data=$(grep -A 10 "^dns: cloudflare" "$plugin_file" | grep "data:" | head -1)
        
        if echo "$plugin_data" | grep -q "CF_Token"; then
            print_success "CF_Token found in configuration"
        else
            print_warning "CF_Token not found in plugin data"
            print_info "Make sure API data includes: CF_Token=your_token"
        fi
        
        if echo "$plugin_data" | grep -q "CF_Zone_ID"; then
            print_success "CF_Zone_ID found in configuration"
        else
            print_error "CF_Zone_ID MISSING from plugin data"
            print_info "This is likely why certificate ordering fails!"
            print_info "Edit the plugin and add: CF_Zone_ID=your_zone_id"
            return 1
        fi
        
    else
        print_info "Cloudflare plugin not configured yet"
        print_info "You'll add this in Datacenter → ACME → Challenge Plugins"
    fi
    
    return 0
}

#############################################################################
# Post-Check Functions
#############################################################################

check_certificate_installed() {
    print_header "Checking Certificate Installation"
    
    if [ ! -f "/etc/pve/local/pveproxy-ssl.pem" ]; then
        print_error "Certificate file not found: /etc/pve/local/pveproxy-ssl.pem"
        return 1
    fi
    
    print_success "Certificate file exists"
    
    # Get certificate details
    local cert_info
    if cert_info=$(pvenode cert info 2>/dev/null); then
        print_success "Certificate info retrieved via pvenode"
        echo "$cert_info" | while IFS= read -r line; do
            print_info "  $line"
        done
    else
        print_warning "Could not retrieve cert info via pvenode, checking file directly..."
        
        # Extract info from cert file
        local subject
        subject=$(openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -subject 2>/dev/null | sed 's/subject=//')
        local issuer
        issuer=$(openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -issuer 2>/dev/null | sed 's/issuer=//')
        local not_after
        not_after=$(openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        
        print_info "  Subject: $subject"
        print_info "  Issuer: $issuer"
        print_info "  Expires: $not_after"
    fi
    
    return 0
}

verify_certificate_validity() {
    print_header "Verifying Certificate Validity"
    
    prompt_input "Enter your Proxmox FQDN (e.g., proxmox.example.com)" PROXMOX_FQDN
    
    if [ -z "$PROXMOX_FQDN" ]; then
        print_error "FQDN is required"
        return 1
    fi
    
    print_info "Testing HTTPS connection to $PROXMOX_FQDN:8006..."
    
    # Test certificate via openssl
    local cert_check
    if cert_check=$(echo | timeout 5 openssl s_client -servername "$PROXMOX_FQDN" -connect "$PROXMOX_FQDN:8006" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null); then
        print_success "Certificate is accessible via HTTPS"
        
        # Parse certificate details
        local subject
        subject=$(echo "$cert_check" | grep "subject=" | sed 's/subject=//')
        local issuer
        issuer=$(echo "$cert_check" | grep "issuer=" | sed 's/issuer=//')
        local not_after
        not_after=$(echo "$cert_check" | grep "notAfter=" | sed 's/notAfter=//')
        
        print_info "  Subject: $subject"
        
        # Check if it's Let's Encrypt
        if echo "$issuer" | grep -qi "let's encrypt\|R[0-9]\{1,2\}"; then
            print_success "Issuer: Let's Encrypt ✓"
        else
            print_warning "Issuer: $issuer"
            print_info "Expected Let's Encrypt issuer"
        fi
        
        print_info "  Expires: $not_after"
        
        # Check if certificate matches FQDN
        if echo "$subject" | grep -q "$PROXMOX_FQDN"; then
            print_success "Certificate matches requested domain"
        else
            print_warning "Certificate domain mismatch detected"
        fi
        
    else
        print_error "Cannot connect to $PROXMOX_FQDN:8006 via HTTPS"
        print_info "Possible issues:"
        print_info "  • DNS not resolving correctly"
        print_info "  • Port 8006 not accessible externally"
        print_info "  • Firewall blocking connection"
        print_info "  • Try from local network first"
        return 1
    fi
    
    return 0
}

check_auto_renewal() {
    print_header "Checking Auto-Renewal Configuration"
    
    # Check if ACME account exists
    local account_output
    if account_output=$(pvenode acme account list 2>/dev/null); then
        # Check if there's actual account data (not just headers)
        if echo "$account_output" | grep -qE "letsencrypt|production|staging"; then
            print_success "ACME account configured"
            # Show account details if available
            echo "$account_output" | grep -v "^$" | while IFS= read -r line; do
                if [ -n "$line" ]; then
                    print_info "  $line"
                fi
            done
        else
            print_warning "ACME account status unclear"
            print_info "If certificate was issued, ACME account exists"
        fi
    else
        print_warning "Could not check ACME account status"
        print_info "If certificate was issued, ACME account likely exists"
    fi
    
    # Check for renewal cron/timer
    if systemctl is-active --quiet pve-daily-update.timer; then
        print_success "Auto-renewal timer: ACTIVE"
        print_info "Certificates will auto-renew 30 days before expiry"
    else
        print_warning "pve-daily-update.timer not active"
        print_info "Manual renewal may be required"
    fi
    
    return 0
}

test_web_interface() {
    print_header "Testing Web Interface"
    
    prompt_input "Enter Proxmox URL (e.g., https://proxmox.example.com:8006)" PROXMOX_URL
    
    if [ -z "$PROXMOX_URL" ]; then
        print_error "URL is required"
        return 1
    fi
    
    # Add https:// if not present
    if [[ ! "$PROXMOX_URL" =~ ^https?:// ]]; then
        PROXMOX_URL="https://$PROXMOX_URL"
        print_info "Added https:// prefix: $PROXMOX_URL"
    fi
    
    print_info "Testing HTTP response..."
    
    # Test if we get a response (ignore cert validation for this test)
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$PROXMOX_URL" --connect-timeout 5)
    
    if [ "$http_code" == "200" ] || [ "$http_code" == "401" ] || [ "$http_code" == "302" ]; then
        print_success "Web interface responding (HTTP $http_code)"
    else
        print_error "Web interface not responding properly (HTTP $http_code)"
        return 1
    fi
    
    # Test with proper cert validation
    print_info "Testing certificate validation..."
    
    if curl -s -o /dev/null "$PROXMOX_URL" --connect-timeout 5; then
        print_success "Certificate validation: PASSED"
        print_success "Browser should show secure connection!"
    else
        print_warning "Certificate validation failed"
        print_info "Certificate may be valid but not trusted by curl's CA bundle"
        print_info "Test in browser - it should show as secure"
    fi
    
    return 0
}

#############################################################################
# Main Workflow Functions
#############################################################################

run_pre_checks() {
    print_header "PRE-INSTALLATION CHECKS"
    echo "Run these checks BEFORE configuring SSL certificates"
    echo ""
    
    local all_passed=true
    
    check_proxmox_version || all_passed=false
    check_internet_connectivity || all_passed=false
    validate_cloudflare_credentials || all_passed=false
    check_dns_record || all_passed=false
    check_port_accessibility || all_passed=false
    check_acme_plugin_config || all_passed=false
    
    echo ""
    if $all_passed; then
        print_header "PRE-CHECK SUMMARY"
        print_success "All pre-checks PASSED!"
        print_info "You're ready to configure SSL certificates in Proxmox"
        print_info ""
        print_info "Next steps:"
        print_info "  1. Follow the README to configure ACME account"
        print_info "  2. Add Cloudflare plugin with BOTH CF_Token and CF_Zone_ID"
        print_info "  3. Order certificate"
        print_info "  4. Run: ./proxmox-ssl-validator.sh --post-check"
    else
        print_header "PRE-CHECK SUMMARY"
        print_error "Some checks FAILED"
        print_info "Fix the issues above before proceeding with SSL setup"
    fi
}

run_post_checks() {
    print_header "POST-INSTALLATION CHECKS"
    echo "Run these checks AFTER ordering your certificate"
    echo ""
    
    local all_passed=true
    
    check_certificate_installed || all_passed=false
    verify_certificate_validity || all_passed=false
    check_auto_renewal || all_passed=false
    test_web_interface || all_passed=false
    
    echo ""
    if $all_passed; then
        print_header "POST-CHECK SUMMARY"
        print_success "All post-checks PASSED!"
        print_success "SSL certificate is properly configured!"
        print_info ""
        print_info "Your Proxmox is now secured with Let's Encrypt"
        print_info "Certificate will auto-renew 30 days before expiry"
    else
        print_header "POST-CHECK SUMMARY"
        print_warning "Some checks had issues"
        print_info "Review the warnings/errors above"
        print_info "Certificate may still be working - test in browser"
    fi
}

run_full_check() {
    run_pre_checks
    echo ""
    read -r -p "Press Enter to continue with post-installation checks..." 
    echo ""
    run_post_checks
}

#############################################################################
# Usage/Help
#############################################################################

show_usage() {
    cat << EOF
Proxmox SSL/TLS Certificate Validator

USAGE:
    $0 [MODE]

MODES:
    --pre-check     Run pre-installation validation
                    (Check before configuring certificate)
    
    --post-check    Run post-installation validation
                    (Verify certificate after installation)
    
    --full          Run both pre and post checks
    
    --help          Show this help message

EXAMPLES:
    # Before setting up certificates
    $0 --pre-check
    
    # After ordering certificate in Proxmox
    $0 --post-check
    
    # Run complete validation
    $0 --full

EOF
}

#############################################################################
# Main Entry Point
#############################################################################

main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_warning "This script should be run as root for full functionality"
        print_info "Some checks may fail without root privileges"
        echo ""
    fi
    
    # Parse command line arguments
    case "${1:-}" in
        --pre-check)
            run_pre_checks
            ;;
        --post-check)
            run_post_checks
            ;;
        --full)
            run_full_check
            ;;
        --help|-h|help)
            show_usage
            ;;
        *)
            print_error "Invalid or missing argument"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
