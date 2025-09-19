#!/bin/bash

# Shop Management API Test Runner
# Automated test execution script for CI/CD pipelines

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_FILE="$SCRIPT_DIR/postman-collection.json"
RESULTS_DIR="$SCRIPT_DIR/../test-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date +'%H:%M:%S')] ${message}${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_status $BLUE "Checking prerequisites..."
    
    # Check if Newman is installed
    if ! command -v newman &> /dev/null; then
        print_status $RED "Newman is not installed. Installing..."
        npm install -g newman
        if [ $? -ne 0 ]; then
            print_status $RED "Failed to install Newman. Exiting."
            exit 1
        fi
    fi
    
    # Check if collection file exists
    if [ ! -f "$COLLECTION_FILE" ]; then
        print_status $RED "Collection file not found: $COLLECTION_FILE"
        exit 1
    fi
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    print_status $GREEN "Prerequisites check completed"
}

# Function to run tests for a specific environment
run_tests() {
    local environment=$1
    local env_file="$SCRIPT_DIR/${environment}.postman_environment.json"
    
    print_status $BLUE "Running tests for $environment environment..."
    
    if [ ! -f "$env_file" ]; then
        print_status $YELLOW "Environment file not found: $env_file. Using collection variables."
        env_file=""
    fi
    
    local output_file="$RESULTS_DIR/test-results-${environment}-${TIMESTAMP}"
    local newman_args=(
        run "$COLLECTION_FILE"
        --reporters cli,html,junit
        --reporter-html-export "${output_file}.html"
        --reporter-junit-export "${output_file}.xml"
        --timeout-request 30000
        --timeout-script 10000
    )
    
    if [ -n "$env_file" ]; then
        newman_args+=(--environment "$env_file")
    fi
    
    # Add additional Newman options based on environment
    case $environment in
        "development")
            newman_args+=(--delay-request 100)
            ;;
        "staging")
            newman_args+=(--delay-request 500)
            ;;
        "production")
            newman_args+=(--delay-request 1000)
            newman_args+=(--global-var "read_only_mode=true")
            ;;
    esac
    
    # Run the tests
    if newman "${newman_args[@]}"; then
        print_status $GREEN "Tests completed successfully for $environment"
        return 0
    else
        print_status $RED "Tests failed for $environment"
        return 1
    fi
}

# Function to run load tests
run_load_tests() {
    local environment=$1
    
    print_status $BLUE "Running load tests for $environment..."
    
    local env_file="$SCRIPT_DIR/${environment}.postman_environment.json"
    local output_file="$RESULTS_DIR/load-test-${environment}-${TIMESTAMP}"
    
    newman run "$COLLECTION_FILE" \
        --environment "$env_file" \
        --iteration-count 10 \
        --delay-request 100 \
        --reporters cli,html \
        --reporter-html-export "${output_file}.html" \
        --timeout-request 60000
    
    if [ $? -eq 0 ]; then
        print_status $GREEN "Load tests completed successfully"
    else
        print_status $RED "Load tests failed"
        return 1
    fi
}

# Function to generate test summary
generate_summary() {
    local test_results_file="$RESULTS_DIR/test-summary-${TIMESTAMP}.md"
    
    print_status $BLUE "Generating test summary..."
    
    cat > "$test_results_file" << EOF
# Test Execution Summary

**Date**: $(date)
**Collection**: Shop Management API Tests
**Results Directory**: $RESULTS_DIR

## Test Results

EOF

    # Analyze XML results if available
    for xml_file in "$RESULTS_DIR"/*.xml; do
        if [ -f "$xml_file" ]; then
            local env_name=$(basename "$xml_file" .xml | sed 's/test-results-//' | sed 's/-[0-9_]*$//')
            echo "### $env_name Environment" >> "$test_results_file"
            
            # Extract test statistics from JUnit XML
            local total_tests=$(grep -o 'tests="[0-9]*"' "$xml_file" | sed 's/tests="//' | sed 's/"//')
            local failures=$(grep -o 'failures="[0-9]*"' "$xml_file" | sed 's/failures="//' | sed 's/"//')
            local errors=$(grep -o 'errors="[0-9]*"' "$xml_file" | sed 's/errors="//' | sed 's/"//')
            
            echo "- **Total Tests**: $total_tests" >> "$test_results_file"
            echo "- **Failures**: $failures" >> "$test_results_file"
            echo "- **Errors**: $errors" >> "$test_results_file"
            echo "" >> "$test_results_file"
        fi
    done
    
    print_status $GREEN "Test summary generated: $test_results_file"
}

# Function to cleanup old test results
cleanup_old_results() {
    print_status $BLUE "Cleaning up old test results..."
    
    # Keep only last 10 test runs
    find "$RESULTS_DIR" -name "test-results-*.html" -type f -printf '%T@ %p\n' | \
        sort -n | head -n -10 | cut -d' ' -f2- | xargs -r rm
    
    find "$RESULTS_DIR" -name "test-results-*.xml" -type f -printf '%T@ %p\n' | \
        sort -n | head -n -10 | cut -d' ' -f2- | xargs -r rm
    
    print_status $GREEN "Cleanup completed"
}

# Function to send notifications (optional)
send_notification() {
    local status=$1
    local environment=$2
    
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local color="good"
        if [ "$status" != "success" ]; then
            color="danger"
        fi
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Shop Management API Tests - $status for $environment environment\"}" \
            "$SLACK_WEBHOOK_URL"
    fi
}

# Main execution function
main() {
    print_status $BLUE "Starting Shop Management API Test Execution"
    
    # Parse command line arguments
    local environment="development"
    local run_load_tests_flag=false
    local cleanup_flag=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -l|--load-tests)
                run_load_tests_flag=true
                shift
                ;;
            --no-cleanup)
                cleanup_flag=false
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -e, --environment ENV    Environment to test (development|staging|production)"
                echo "  -l, --load-tests        Run load tests after functional tests"
                echo "  --no-cleanup           Skip cleanup of old test results"
                echo "  -h, --help             Show this help message"
                exit 0
                ;;
            *)
                print_status $RED "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate environment
    case $environment in
        development|staging|production)
            ;;
        *)
            print_status $RED "Invalid environment: $environment. Use development, staging, or production."
            exit 1
            ;;
    esac
    
    # Execute test pipeline
    check_prerequisites
    
    if [ "$cleanup_flag" = true ]; then
        cleanup_old_results
    fi
    
    local test_status="success"
    
    # Run functional tests
    if ! run_tests "$environment"; then
        test_status="failed"
    fi
    
    # Run load tests if requested
    if [ "$run_load_tests_flag" = true ] && [ "$test_status" = "success" ]; then
        if ! run_load_tests "$environment"; then
            test_status="failed"
        fi
    fi
    
    # Generate summary
    generate_summary
    
    # Send notification if configured
    send_notification "$test_status" "$environment"
    
    # Final status
    if [ "$test_status" = "success" ]; then
        print_status $GREEN "All tests completed successfully!"
        print_status $BLUE "Results available in: $RESULTS_DIR"
        exit 0
    else
        print_status $RED "Some tests failed. Check results for details."
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"