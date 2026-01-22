#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Provider Functions
# ============================================================================
# Handles execution for different AI providers:
# - claude: Anthropic Claude Code CLI
# - gemini: Google Gemini CLI
# - codex: OpenAI Codex CLI
# - opencode: OpenCode CLI (optional :model)
# - ollama:<model>: Ollama with specified model
# ============================================================================

# Colors (in case sourced independently)
RED='\033[0;31m'
NC='\033[0m'

# ============================================================================
# Provider Validation
# ============================================================================

validate_provider() {
  local provider="$1"
  
  # Extract first command from provider string (handles spaces and args)
  local first_cmd
  first_cmd=$(echo "$provider" | awk '{print $1}')
  
  # Check if first command is available
  if ! command -v "$first_cmd" &> /dev/null; then
    echo -e "${RED}❌ Command not found: $first_cmd${NC}"
    echo ""
    echo "The PROVIDER command must be executable and available in PATH."
    echo ""
    echo "Current PROVIDER: $provider"
    echo ""
    echo "Examples of valid PROVIDER configurations:"
    echo "  # Using local installation:"
    echo "  PROVIDER=\"gemini\""
    echo "  PROVIDER=\"claude\""
    echo "  PROVIDER=\"opencode run --model anthropic/claude-opus-4-5\""
    echo "  PROVIDER=\"ollama run llama3.2\""
    echo ""
    echo "  # Using npx/bunx (no local installation needed):"
    echo "  PROVIDER=\"bunx @google/gemini-cli\""
    echo "  PROVIDER=\"npx @google/gemini-cli\""
    echo "  PROVIDER=\"bunx github-copilot-cli\""
    echo ""
    echo "Make sure '$first_cmd' is installed or use npx/bunx to run it."
    echo ""
    return 1
  fi

  return 0
}

# ============================================================================
# Provider Execution
# ============================================================================

execute_provider() {
  local provider="$1"
  local prompt="$2"
  local timeout="${GGA_TIMEOUT:-300}"  # Default 5 minutes
  
  # Execute the provider command with prompt via stdin
  # This is the most universal method - works with gemini, claude, etc.
  
  # Create temp file for prompt to handle large content safely
  local temp_prompt
  temp_prompt=$(mktemp)
  printf '%s' "$prompt" > "$temp_prompt"
  
  echo -e "\033[0;36m━━━ Provider Output ━━━\033[0m"
  echo ""
  
  # Show debug info if DEBUG_MODE is enabled
  if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
    echo -e "\033[1;33m🔍 DEBUG MODE ENABLED\033[0m"
    echo -e "\033[0;36mExecuting command:\033[0m $provider"
    echo -e "\033[0;36mPrompt size:\033[0m $(wc -c < "$temp_prompt") bytes"
    echo ""
  fi
  
  # Execute with timeout and capture output
  local result
  local status
  
  # Use timeout command if available, otherwise run without it
  if command -v timeout &> /dev/null; then
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
      echo -e "\033[1;33mRunning with ${timeout}s timeout (streaming output)...\033[0m"
      echo ""
      # In debug mode, show output in real-time
      timeout "$timeout" bash -c "cat '$temp_prompt' | $provider" 2>&1 | tee /dev/tty
      status=${PIPESTATUS[0]}
      # Also capture for processing
      result=$(timeout "$timeout" bash -c "cat '$temp_prompt' | $provider" 2>&1)
    else
      echo "Running with ${timeout}s timeout..."
      result=$(timeout "$timeout" bash -c "cat '$temp_prompt' | $provider" 2>&1)
      status=$?
    fi
    
    # Check if timeout occurred
    if [[ $status -eq 124 ]]; then
      echo ""
      echo -e "\033[0;31m⏱️  Command timed out after ${timeout} seconds\033[0m"
      echo ""
      echo "Try:"
      echo "  • Set GGA_TIMEOUT environment variable (e.g., export GGA_TIMEOUT=600)"
      echo "  • Use a faster model"
      echo "  • Reduce the number of files to review"
      rm -f "$temp_prompt"
      return 1
    fi
  else
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
      echo -e "\033[1;33mRunning without timeout (streaming output)...\033[0m"
      echo ""
      # In debug mode, show output in real-time
      bash -c "cat '$temp_prompt' | $provider" 2>&1 | tee /dev/tty
      status=${PIPESTATUS[0]}
      # Also capture for processing
      result=$(bash -c "cat '$temp_prompt' | $provider" 2>&1)
    else
      result=$(bash -c "cat '$temp_prompt' | $provider" 2>&1)
      status=$?
    fi
  fi
  
  # Show the output (only if not in debug mode, since we already showed it)
  if [[ "${DEBUG_MODE:-false}" != "true" ]]; then
    echo "$result"
  fi
  echo ""
  echo -e "\033[0;36m━━━ End Output ━━━\033[0m"
  echo ""
  
  # Cleanup temp file
  rm -f "$temp_prompt"
  
  # If command failed, show helpful error
  if [[ $status -ne 0 ]]; then
    echo -e "${RED}❌ Provider command failed${NC}" >&2
    echo "" >&2
    echo "Command: $provider" >&2
    echo "Exit code: $status" >&2
    echo "" >&2
    
    # Check for common error patterns and provide specific guidance
    if echo "$result" | grep -qi "model.*not.*found\|404"; then
      echo -e "\033[0;33m💡 Model Not Found:\033[0m" >&2
      echo "  The specified model is not available." >&2
      echo "  • Remove --model flag to use the default model" >&2
      echo "  • Check available models for your API tier" >&2
      echo "  • Example: PROVIDER=\"bunx @google/gemini-cli\"" >&2
    elif echo "$result" | grep -qi "quota\|rate.limit\|429"; then
      echo -e "\033[0;33m💡 API Quota/Rate Limit Issue:\033[0m" >&2
      echo "  Your API provider has rate limits or quota restrictions." >&2
      echo "  • Wait for the quota to reset (check provider's rate limit policy)" >&2
      echo "  • Use a different model or provider" >&2
      echo "  • Upgrade your API plan if available" >&2
    elif echo "$result" | grep -qi "auth\|api.key\|unauthorized\|403"; then
      echo -e "\033[0;33m💡 Authentication Issue:\033[0m" >&2
      echo "  The provider requires authentication." >&2
      echo "  • Set the required API key environment variable" >&2
      echo "  • Check your provider's authentication documentation" >&2
      echo "  • Example: export GEMINI_API_KEY='your-key-here'" >&2
    elif echo "$result" | grep -qi "not found\|command not found\|no such"; then
      echo -e "\033[0;33m💡 Command Not Found:\033[0m" >&2
      echo "  The provider command is not available." >&2
      echo "  • Install the provider locally, or" >&2
      echo "  • Use npx/bunx to run without installing" >&2
      echo "  • Example: PROVIDER=\"bunx @google/gemini-cli\"" >&2
    else
      echo -e "\033[0;33m💡 General Troubleshooting:\033[0m" >&2
      echo "  Make sure your PROVIDER command:" >&2
      echo "  1. Accepts input via stdin (pipe)" >&2
      echo "  2. Returns the AI response to stdout" >&2
      echo "  3. Includes all necessary arguments (model, API keys, etc.)" >&2
      echo "" >&2
      echo -e "\033[0;36mExamples:\033[0m" >&2
      echo "  PROVIDER=\"gemini\"" >&2
      echo "  PROVIDER=\"bunx @google/gemini-cli\"" >&2
      echo "  PROVIDER=\"opencode run --model anthropic/claude-opus-4-5\"" >&2
      echo "  PROVIDER=\"ollama run llama3.2\"" >&2
    fi
    
    echo "" >&2
    return 1
  fi
  
  echo "$result"
  return 0
}

# ============================================================================
# Note: Individual provider implementations removed
# ============================================================================
# The new system executes provider commands directly without hardcoded
# implementations. Users specify the full command in PROVIDER config.
# Examples:
#   PROVIDER="gemini"
#   PROVIDER="bunx @google/gemini-cli"
#   PROVIDER="opencode run --model anthropic/claude-opus-4-5"
#   PROVIDER="ollama run llama3.2"

# ============================================================================
# Provider Info
# ============================================================================

get_provider_info() {
  local provider="$1"
  echo "$provider"
}

# ============================================================================
# Provider Verification - Show provider configuration before executing
# ============================================================================

verify_provider_config() {
  local provider="$1"
  
  echo -e "\033[1mProvider Configuration:\033[0m"
  echo -e "  Command: \033[0;36m$provider\033[0m"
  
  # Try to get model info if specified in command
  if echo "$provider" | grep -q "\-\-model"; then
    local model
    model=$(echo "$provider" | sed -n 's/.*--model[= ]\([^ ]*\).*/\1/p')
    if [[ -n "$model" ]]; then
      echo -e "  Model: \033[0;36m$model\033[0m"
    fi
  fi
  
  echo ""
}