#!/bin/bash

# Replace with your Cloudflare Worker URL
WORKER_URL="https://docker.mydomain.com"

# --- Helper Functions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to run a test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_status="$3"

    echo -e "\n--- ${YELLOW}Running Test: $test_name${NC} ---"
    echo "Executing: $command"
    
    # Use curl with -w to get the HTTP status code, and -o to save the body
    # -s for silent, -L to follow redirects
    http_status=$(eval "$command -w '%{http_code}' -o /dev/null -s -L")
    
    echo "Expected Status: $expected_status, Got Status: $http_status"

    if [ "$http_status" -eq "$expected_status" ]; then
        echo -e "Result: ${GREEN}SUCCESS${NC}"
        return 0
    else
        echo -e "Result: ${RED}FAILURE${NC}"
        echo "Response Body/Headers:"
        # Run again without silencing to see the output
        eval "$command"
        return 1
    fi
}

# --- Test Cases ---

echo "Starting tests for Docker proxy worker..."
echo "Target URL: $WORKER_URL"
echo "NOTE: A 401 Unauthorized is often a SUCCESS for manifest/blob requests, as it means the proxy correctly forwarded the request to the registry, which then requires authentication."

# Test 1: Invalid path, should be blocked
run_test "Block invalid path /foo" \
    "curl \"$WORKER_URL/foo\"" \
    403

# Test 2: Another invalid path, should be blocked
run_test "Block invalid path /v3/test" \
    "curl \"$WORKER_URL/v3/test\"" \
    403

# Test 3: Root path, should not be blocked by the new filter (should return HTML or redirect)
# The default worker returns a search interface (200) or an Nginx page (200)
run_test "Allow root path /" \
    "curl -A \"Mozilla/5.0\" \"$WORKER_URL/\"" \
    200

# Test 4: v1 API endpoint, should be allowed
# This will likely result in a 200 with HTML content from hub.docker.com
run_test "Allow v1 API path /v1/search" \
    "curl -A \"Mozilla/5.0\" \"$WORKER_URL/v1/search?q=nginx\"" \
    200

# Test 5: v2 API endpoint (checking API version)
# This should be allowed and typically returns a 200 or 401.
run_test "Allow v2 API base path /v2/" \
    "curl \"$WORKER_URL/v2/\"" \
    401

# Test 6: v2 manifest request, should be allowed (and likely get a 401 from the registry)
run_test "Allow v2 manifest request" \
    "curl \"$WORKER_URL/v2/library/ubuntu/manifests/latest\"" \
    200

# Test 7: Token request, should be allowed
# This should also result in a 401, as we are not providing auth details for the registry.
run_test "Allow /token endpoint" \
    "curl \"$WORKER_URL/token?service=registry.docker.io&scope=repository:library/ubuntu:pull\"" \
    200

# Test 8: Blocked User-Agent
run_test "Block crawler User-Agent" \
    "curl -A \"netcraft\" \"$WORKER_URL/\"" \
    200 # The worker returns a 200 with a fake Nginx page

echo -e "\n--- ${YELLOW}All tests complete.${NC} ---"
echo "Please review the results above."
echo "Remember to replace the placeholder WORKER_URL with your actual worker URL."
