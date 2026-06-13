#!/bin/bash

# Extract validation functions from crawl.sh for testing
source <(sed -n '/^# Validate URL format/,/^validate_numeric() {$/p' ~/crawler-shell/crawl.sh | head -n -1)
source <(sed -n '/^validate_numeric() {$/,/^}$/p' ~/crawler-shell/crawl.sh)

echo "Testing URL validation:"
echo "1. Valid URL (http://example.com):"
if validate_url "http://example.com"; then
    echo "   ✓ PASS"
else
    echo "   ✗ FAIL"
fi

echo "2. Command injection attempt (http://example.com; rm -rf /):"
if validate_url "http://example.com; rm -rf /"; then
    echo "   ✗ FAIL - Should have rejected"
else
    echo "   ✓ PASS - Correctly rejected"
fi

echo "3. Invalid protocol (ftp://example.com):"
if validate_url "ftp://example.com"; then
    echo "   ✗ FAIL - Should have rejected"
else
    echo "   ✓ PASS - Correctly rejected"
fi

echo -e "\nTesting path sanitization:"
echo "4. Valid path (reports/test):"
result=$(sanitize_path "reports/test")
if [[ $? -eq 0 && "$result" == "reports/test" ]]; then
    echo "   ✓ PASS"
else
    echo "   ✗ FAIL"
fi

echo "5. Directory traversal (../../etc/passwd):"
if sanitize_path "../../etc/passwd" >/dev/null 2>&1; then
    echo "   ✗ FAIL - Should have rejected dangerous chars or cleaned path"
else
    echo "   ✓ PASS - Correctly handled"
fi

echo -e "\nTesting numeric validation:"
echo "6. Valid number (5, range 1-10):"
if validate_numeric "5" "test" 1 10; then
    echo "   ✓ PASS"
else
    echo "   ✗ FAIL"
fi

echo "7. Non-numeric (abc):"
if validate_numeric "abc" "test" 1 10; then
    echo "   ✗ FAIL - Should have rejected"
else
    echo "   ✓ PASS - Correctly rejected"
fi

echo "8. Out of range (150, range 1-100):"
if validate_numeric "150" "test" 1 100; then
    echo "   ✗ FAIL - Should have rejected"
else
    echo "   ✓ PASS - Correctly rejected"
fi

echo -e "\nAll security validation tests completed."
