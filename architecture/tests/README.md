# API Testing Documentation

This directory contains comprehensive testing resources for the Shop Management API, including Postman collections, test environments, and testing guidelines.

## Test Files

### 1. Postman Collection
- **File**: `postman-collection.json`
- **Description**: Complete Postman collection with all API endpoints
- **Coverage**: Authentication, CRUD operations, search, analytics, error handling
- **Tests**: 40+ requests with automated assertions

### 2. Test Environments
- **Development**: Local development testing
- **Staging**: Pre-production testing
- **Production**: Production API testing (read-only tests)

## Getting Started

### Prerequisites
- Postman installed (latest version)
- API access credentials
- Test database with sample data

### Setup Instructions

1. **Import Collection**
   ```bash
   # Import the collection file into Postman
   File → Import → Upload Files → postman-collection.json
   ```

2. **Configure Environment**
   ```json
   {
     "base_url": "https://api.shopmanagement.com",
     "auth_token": "",
     "tenant_id": "",
     "shop_id": "",
     "user_id": ""
   }
   ```

3. **Run Authentication**
   - Execute "Login" request first
   - This will auto-populate auth tokens and user context

4. **Execute Tests**
   - Run individual requests or entire collection
   - Monitor test results in Postman console

## Test Categories

### Authentication Tests
- ✅ User login with valid credentials
- ✅ User registration and email verification
- ✅ Token refresh functionality
- ✅ Logout and token invalidation
- ❌ Invalid credentials handling
- ❌ Expired token scenarios

### CRUD Operations Tests
- ✅ Shop creation, read, update operations
- ✅ Product management lifecycle
- ✅ Order creation and status updates
- ✅ Inventory adjustments
- ❌ Validation error handling
- ❌ Resource not found scenarios

### Multi-tenant Security Tests
- ✅ Tenant data isolation verification
- ❌ Cross-tenant access prevention
- ✅ Row-level security validation
- ❌ Unauthorized access attempts

### Search & Filtering Tests
- ✅ Product search with text queries
- ✅ Category and price filtering
- ✅ Geographic location search
- ✅ Sorting and pagination
- ❌ Malformed search queries

### Performance Tests
- ✅ Response time validation (< 500ms)
- ✅ Large payload handling
- ✅ Concurrent request handling
- ❌ Load testing scenarios

### Analytics Tests
- ✅ Sales analytics data accuracy
- ✅ Product performance metrics
- ✅ Date range filtering
- ❌ Invalid date parameters

## Test Execution

### Manual Testing
```bash
# Run specific test category
Postman → Collections → Shop Management API → Authentication → Run

# Run entire collection
Postman → Collections → Shop Management API → Run Collection
```

### Automated Testing
```bash
# Newman CLI execution
npm install -g newman
newman run postman-collection.json \
  --environment development.json \
  --reporters html,cli \
  --reporter-html-export test-results.html

# CI/CD Integration
newman run postman-collection.json \
  --environment staging.json \
  --reporters junit \
  --reporter-junit-export results.xml
```

## Environment Configuration

### Development Environment
```json
{
  "id": "development",
  "name": "Development",
  "values": [
    {
      "key": "base_url",
      "value": "http://localhost:3000",
      "enabled": true
    },
    {
      "key": "auth_token",
      "value": "",
      "enabled": true
    }
  ]
}
```

### Staging Environment
```json
{
  "id": "staging", 
  "name": "Staging",
  "values": [
    {
      "key": "base_url",
      "value": "https://staging-api.shopmanagement.com",
      "enabled": true
    },
    {
      "key": "auth_token",
      "value": "",
      "enabled": true
    }
  ]
}
```

### Production Environment
```json
{
  "id": "production",
  "name": "Production",
  "values": [
    {
      "key": "base_url", 
      "value": "https://api.shopmanagement.com",
      "enabled": true
    },
    {
      "key": "auth_token",
      "value": "",
      "enabled": true
    }
  ]
}
```

## Test Data Management

### Sample Test Data
```javascript
// Pre-request script to generate test data
const testShop = {
  name: `Test Shop ${Math.random().toString(36).substr(2, 9)}`,
  category: "electronics",
  email: `test-${Date.now()}@example.com`
};

pm.environment.set("test_shop_name", testShop.name);
pm.environment.set("test_email", testShop.email);
```

### Data Cleanup
```javascript
// Test cleanup script
pm.test("Cleanup test data", function () {
  // Delete test resources after test completion
  const shopId = pm.environment.get("shop_id");
  if (shopId && shopId !== "{{shop_id}}") {
    // Cleanup logic here
  }
});
```

## Assertion Guidelines

### Standard Assertions
```javascript
// Status code validation
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

// Response time validation  
pm.test("Response time is less than 500ms", function () {
    pm.expect(pm.response.responseTime).to.be.below(500);
});

// JSON structure validation
pm.test("Response has required fields", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData.id).to.not.be.undefined;
    pm.expect(jsonData.tenant_id).to.not.be.undefined;
});

// Data integrity validation
pm.test("Tenant isolation maintained", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData.tenant_id).to.eql(pm.environment.get("tenant_id"));
});
```

### Security Assertions
```javascript
// Authentication validation
pm.test("Unauthorized request blocked", function () {
    pm.response.to.have.status(401);
});

// Cross-tenant access prevention
pm.test("Cross-tenant access denied", function () {
    pm.expect(pm.response.code).to.be.oneOf([403, 404]);
});

// Input validation
pm.test("Invalid input rejected", function () {
    pm.response.to.have.status(400);
    var jsonData = pm.response.json();
    pm.expect(jsonData.error).to.not.be.undefined;
});
```

## Continuous Integration

### GitHub Actions Integration
```yaml
# .github/workflows/api-tests.yml
name: API Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install Newman
        run: npm install -g newman
      - name: Run API Tests
        run: |
          newman run architecture/tests/postman-collection.json \
            --environment architecture/tests/staging.json \
            --reporters cli,junit \
            --reporter-junit-export test-results.xml
      - name: Publish Test Results
        uses: EnricoMi/publish-unit-test-result-action@v1
        if: always()
        with:
          files: test-results.xml
```

## Test Coverage Metrics

### Current Coverage
- **Authentication**: 100% (4/4 endpoints)
- **Shops**: 90% (4/4 CRUD + search)
- **Products**: 95% (5/5 CRUD + search + inventory)
- **Orders**: 85% (3/4 CRUD operations)
- **Analytics**: 80% (2/3 report types)
- **Error Handling**: 70% (key scenarios covered)

### Target Coverage
- **Functional Tests**: > 95%
- **Error Scenarios**: > 80%
- **Performance Tests**: > 70%
- **Security Tests**: 100%

## Best Practices

### Test Organization
1. Group related tests into folders
2. Use descriptive test names
3. Include setup and teardown steps
4. Document expected vs actual behavior

### Test Data
1. Use dynamic test data generation
2. Clean up test resources after execution
3. Avoid dependencies between tests
4. Use realistic data scenarios

### Assertions
1. Test both positive and negative scenarios
2. Validate response structure and data
3. Check business logic correctness
4. Verify security constraints

### Maintenance
1. Update tests when API changes
2. Review test results regularly
3. Add tests for new features
4. Remove obsolete tests

## Troubleshooting

### Common Issues

**Issue**: Authentication fails
```javascript
// Check token format and expiry
console.log("Token:", pm.environment.get("auth_token"));
console.log("Expires:", pm.environment.get("token_expires"));
```

**Issue**: Cross-tenant access test passes (should fail)
```javascript
// Verify tenant context is set correctly
console.log("User Tenant:", pm.environment.get("tenant_id"));  
console.log("Resource Tenant:", jsonData.tenant_id);
```

**Issue**: Performance tests fail
```javascript
// Log response times for analysis
console.log("Response Time:", pm.response.responseTime + "ms");
console.log("Response Size:", pm.response.size());
```

### Debug Tips
1. Enable Postman console for request/response logging
2. Use environment variables for dynamic data
3. Add console.log statements for debugging
4. Check API logs for server-side errors
5. Validate request headers and authentication

For support and questions, contact the API development team or check the project documentation.