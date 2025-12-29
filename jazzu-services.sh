#!/bin/bash
# jazzu-services.sh - Registers Consul services with robust error handling
# Enhanced on Dec 29, 2025 for House of Jazzu Launch Kit

set -euo pipefail  # Exit on error, unset vars, pipe failures
LOG_FILE="/var/log/jazzu-services.log"
CONSUL_ADDR="localhost:8500"  # Configurable

# Trap for cleanup and error reporting
trap 'echo "[ERROR] Script failed at line $LINENO" >> "$LOG_FILE"; exit 1' ERR
trap 'echo "[INFO] Script completed successfully" >> "$LOG_FILE"' EXIT

# Function for logging
log() {
    local level="$1"
    shift
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [$level] $*" >> "$LOG_FILE"
}

# Validate dependencies
if ! command -v jq &> /dev/null; then
    log "ERROR" "jq is required but not installed."
    exit 1
fi
if ! command -v curl &> /dev/null; then
    log "ERROR" "curl is required but not installed."
    exit 1
fi

# Find and process JSON files
find consul/ -name "*.json" | while read -r file; do
    log "INFO" "Processing $file"
    
    # Validate JSON
    if ! jq . "$file" > /dev/null 2>&1; then
        log "ERROR" "Invalid JSON in $file"
        continue  # Skip invalid files instead of failing entirely
    fi
    
    # Register with Consul, with retry
    max_retries=3
    for ((i=1; i<=max_retries; i++)); do
        if curl -f -X PUT -d @"$file" "http://$CONSUL_ADDR/v1/agent/service/register"; then
            log "INFO" "Successfully registered service from $file"
            break
        else
            log "WARNING" "Failed to register $file (attempt $i/$max_retries)"
            sleep 2
        fi
    done
    if [[ $i -gt $max_retries ]]; then
        log "ERROR" "Max retries exceeded for $file"
    fi
done
variable "services" {
  type        = list(any)
  default     = []
  validation {
    condition     = alltrue([for s in var.services : contains(["web", "payments", "museforge"], s.name)])
    error_message = "Invalid service name; must be 'web', 'payments', or 'museforge'."
  }
}

variable "app_settings" {
  type        = map(string)
  default     = {}
  validation {
    condition     = lookup(var.app_settings, "QUANTUM_API_TOKEN", "") != ""  # Required for MuseForge
    error_message = "QUANTUM_API_TOKEN must be set for quantum integrations."
  }
}
resource "azurerm_linux_function_app" "museforge" {
  name                = try(var.function_app_name, "museforge-function-app")  # Fallback if var missing
  # ... (rest as before)
  
  lifecycle {
    ignore_changes = [app_settings["NON_CRITICAL"]]  # Ignore non-fatal changes
  }
}

output "deployment_status" {
  value = "Success"
  precondition {
    condition     = azurerm_linux_function_app.museforge.id != null
    error_message = "Failed to provision MuseForge Function App."
  }
}
import logging
from tenacity import retry, stop_after_attempt, wait_exponential  # For retries (if available; fallback to manual)
from web3.exceptions import Web3Exception  # Specific for NFT

# ... (rest of imports)

class CreativeAgent(NiaCore):
    # ... (init as before)

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))  # Retry decorator
    def integrate_museforge_nft_minting(self, composition_data: Dict[str, Any]) -> Dict[str, Any]:
        try:
            # Validate input
            required_keys = ['artist_id', 'user_id']
            if not all(key in composition_data for key in required_keys):
                raise ValueError(f"Missing required keys: {required_keys}")
            
            # Composition creation with context manager
            with self._museforge_context() as muse:  # Hypothetical context for cleanup
                composition = muse.create_composition(...)  # As before
            
            decision_result = self.hoj_agent.process_quantum_decision(...)
            
            if 'Harmony' in decision_result or 'Boost' in decision_result:
                token_uri = muse.create_token_uri(composition)
                tx_hash = muse.mint_nft(...)  # As before
                
                revenue_log = {...}
                self.vault.log_transaction('nft_mint', revenue_log)
                self.memory.store('nft_mints', revenue_log)
                
                health_status = self.hoj_agent.monitor_health()
                if 'error' in health_status.get('health', ''):
                    raise RuntimeError("Post-mint health check failed")
                
                return {'status': 'success', 'tx_hash': tx_hash, 'log': revenue_log}
            else:
                return {'status': 'denied', 'reason': decision_result}
        
        except ValueError as ve:
            logger.warning(f"Input validation error: {ve}")
            return {'status': 'input_error', 'details': str(ve)}
        except Web3Exception as we:
            logger.error(f"Blockchain error during mint: {we}")
            return {'status': 'blockchain_error', 'details': str(we)}
        except Exception as e:
            logger.critical(f"Unexpected error: {e}", exc_info=True)
            error_log = {'status': 'error', 'details': str(e)}
            self.memory.store('nft_errors', error_log)
            self.vault.store_audit('nft_mint_error', error_log)
            return error_log

    def _museforge_context(self):
        """Context manager for MuseForge resources."""
        muse = EnhancedMuseForge(...)
        try:
            yield muse
        finally:
            # Cleanup (e.g., stop playback, close connections)
            muse.stop_playback()
            logger.info("MuseForge resources cleaned up.")
