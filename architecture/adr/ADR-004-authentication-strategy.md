# ADR-004: Authentication & Authorization Strategy

**Status**: Accepted  
**Date**: 2024-01-01  
**Deciders**: Security Architecture Team  
**Technical Story**: Design secure authentication and authorization for multi-tenant shop management system

## Context

The shop management system requires a robust authentication and authorization system that can:
- Support multiple user types (shop owners, employees, customers, admins)
- Handle multi-tenant access control and tenant isolation
- Scale to 100,000+ users across 10,000+ shops
- Integrate with modern web and mobile applications
- Provide strong security with minimal operational overhead
- Support SSO integration for enterprise customers
- Meet compliance requirements (SOX, PCI DSS, GDPR)

## Decision Drivers

* **Security**: Strong authentication with MFA and session management
* **Scalability**: Handle 100K+ users with minimal performance impact
* **Multi-tenancy**: Tenant-aware authorization and resource isolation
* **Developer Experience**: Simple integration with frontend and API
* **Operational Simplicity**: Managed service with minimal maintenance
* **Compliance**: Meet security audit requirements
* **Cost Efficiency**: Reasonable costs at scale
* **Integration**: OAuth, SAML, and social login support

## Options Considered

### Option 1: Custom JWT Authentication
**Description**: Build custom authentication service with JWT tokens

**Pros**:
- Complete control over authentication logic
- Custom tenant-aware claims
- No vendor lock-in
- Optimal performance tuning
- Custom session management

**Cons**:
- High development and maintenance overhead
- Security implementation complexity
- Need to build user management UI
- MFA implementation required
- Password policy management
- Audit trail implementation

**Cost Analysis**: 
- Development: 6-8 weeks initial + ongoing maintenance
- Infrastructure: ~$100/month
- **Total**: High development cost, low operational cost

### Option 2: Auth0
**Description**: Third-party identity platform as a service

**Pros**:
- Feature-rich authentication platform
- Social login providers built-in
- MFA and security features
- Good developer experience
- Extensive customization options
- Enterprise SSO support

**Cons**:
- Vendor lock-in and dependencies
- Higher costs at scale ($0.015 per user/month)
- Data residency concerns
- Limited customization for multi-tenancy
- Complex pricing tiers

**Cost Analysis**:
- 100K users: $1,500/month
- Enterprise features: +$500/month
- **Total**: $2,000+/month

### Option 3: AWS Cognito User Pools
**Description**: AWS managed authentication service

**Pros**:
- AWS native integration
- Built-in MFA and security features
- Social and enterprise identity providers
- Custom attributes and triggers
- Pay-per-active-user pricing
- Compliance certifications
- Lambda triggers for customization

**Cons**:
- AWS vendor lock-in
- Limited UI customization
- Complex configuration for advanced use cases
- Lambda function dependency for customization
- Limited audit trail details

**Cost Analysis**:
- First 50K users: Free
- Next 50K users: $0.0055/user/month = $275/month
- **Total**: ~$275/month for 100K users

### Option 4: AWS IAM + Custom Identity Provider
**Description**: Use AWS IAM with custom SAML/OAuth identity provider

**Pros**:
- Fine-grained AWS resource access control
- Direct AWS service integration
- Custom identity provider flexibility
- No user limits

**Cons**:
- Complex implementation
- Limited user management features
- Not suitable for web application authentication
- High development overhead

**Cost Analysis**:
- Development: 8-10 weeks
- Infrastructure: ~$200/month
- **Total**: High development cost

### Option 5: Firebase Authentication
**Description**: Google's managed authentication service

**Pros**:
- Excellent mobile SDK support
- Social providers integration
- Real-time database integration
- Good developer experience

**Cons**:
- Google vendor lock-in
- Limited enterprise features
- Multi-tenancy limitations
- Not optimized for AWS integration

**Cost Analysis**:
- Pay per authentication: $0.006 per user/month
- 100K users: $600/month

## Decision

**Chosen Option**: **Option 3 - AWS Cognito User Pools with Custom RBAC**

### Rationale

1. **AWS Integration**: Native integration with ECS, API Gateway, ALB, and other AWS services
2. **Cost Efficiency**: Free for first 50K users, then $0.0055 per user - very competitive
3. **Security Features**: Built-in MFA, password policies, account verification, threat protection
4. **Scalability**: Handles millions of users with automatic scaling
5. **Compliance**: SOC, PCI DSS, and HIPAA compliant
6. **Customization**: Lambda triggers for custom authentication flows
7. **Identity Federation**: Support for SAML, OAuth, and social identity providers

### Implementation Architecture

```yaml
Cognito User Pool Configuration:
  Pool Name: shop-management-users
  Username Attributes: email, phone_number
  Policies:
    Password: 
      MinimumLength: 12
      RequireNumbers: true
      RequireSymbols: true
      RequireUppercase: true
      RequireLowercase: true
    
  MFA Configuration: OPTIONAL (SMS + TOTP)
  Account Recovery: email + SMS
  User Verification: email required
  
  Custom Attributes:
    tenant_id: UUID (required)
    user_role: string (required) 
    shop_ids: string array (for multi-shop access)
    permissions: string array (custom RBAC)
    last_login: datetime
    failed_login_count: number

Lambda Triggers:
  PreSignUp: Validate tenant context and user limits
  PostConfirmation: Initialize user profile and permissions
  PreAuthentication: Check account status and tenant access
  PostAuthentication: Update last login and audit logs
  
App Client Configuration:
  Client Name: shop-management-web
  Auth Flows: USER_PASSWORD_AUTH, USER_SRP_AUTH
  Token Validity:
    Access Token: 1 hour
    ID Token: 1 hour  
    Refresh Token: 30 days
  Read/Write Attributes: custom + standard
```

## Custom RBAC Implementation

### Role-Based Access Control
```javascript
// Custom permission system
const ROLES = {
  SUPER_ADMIN: {
    permissions: ['*'], // All permissions
    scope: 'global'
  },
  TENANT_ADMIN: {
    permissions: [
      'shop:read', 'shop:write', 'shop:delete',
      'user:read', 'user:write', 'user:invite',
      'product:*', 'order:*', 'inventory:*',
      'analytics:read'
    ],
    scope: 'tenant'
  },
  SHOP_OWNER: {
    permissions: [
      'shop:read', 'shop:write',
      'user:read', 'user:invite',
      'product:*', 'order:*', 'inventory:*'
    ],
    scope: 'shop'
  },
  SHOP_MANAGER: {
    permissions: [
      'shop:read',
      'product:read', 'product:write',
      'order:read', 'order:write',
      'inventory:read', 'inventory:write'
    ],
    scope: 'shop'
  },
  SHOP_EMPLOYEE: {
    permissions: [
      'product:read',
      'order:read', 'order:write',
      'inventory:read'
    ],
    scope: 'shop'
  },
  CUSTOMER: {
    permissions: [
      'product:read',
      'order:read_own', 'order:write_own'
    ],
    scope: 'customer'
  }
};

// JWT token structure
{
  "sub": "user-uuid",
  "email": "user@example.com",
  "tenant_id": "tenant-uuid",
  "user_role": "SHOP_OWNER",
  "shop_ids": ["shop-uuid-1", "shop-uuid-2"],
  "permissions": ["shop:read", "shop:write", "product:*"],
  "iat": 1640995200,
  "exp": 1640998800
}
```

### Authorization Middleware
```javascript
// Express.js authorization middleware
const authorize = (requiredPermission, resourceType = null) => {
  return async (req, res, next) => {
    try {
      const token = extractToken(req);
      const decoded = jwt.verify(token, process.env.COGNITO_PUBLIC_KEY);
      
      // Set tenant context for RLS
      await db.query('SET app.current_tenant = $1', [decoded.tenant_id]);
      
      // Check permission
      if (!hasPermission(decoded.permissions, requiredPermission)) {
        return res.status(403).json({ error: 'Insufficient permissions' });
      }
      
      // Check resource-level access (shop-specific)
      if (resourceType === 'shop' && req.params.shopId) {
        if (!decoded.shop_ids.includes(req.params.shopId)) {
          return res.status(403).json({ error: 'Access denied to shop' });
        }
      }
      
      req.user = decoded;
      next();
    } catch (error) {
      return res.status(401).json({ error: 'Invalid token' });
    }
  };
};
```

## Consequences

### Positive Consequences

* **Cost Efficiency**: Free for first 50K users, very low cost scaling
* **AWS Integration**: Seamless integration with ALB, API Gateway, Lambda
* **Security**: Built-in security features, threat protection, compliance
* **Scalability**: Automatic scaling to millions of users
* **Developer Productivity**: Well-documented SDKs for web and mobile
* **Operational Simplicity**: Managed service with minimal maintenance
* **Customization**: Lambda triggers for custom business logic

### Negative Consequences

* **AWS Vendor Lock-in**: Tied to AWS ecosystem
* **UI Limitations**: Hosted UI has limited customization options
* **Complex Configuration**: Advanced features require careful configuration
* **Lambda Dependencies**: Custom logic requires Lambda functions
* **Limited Audit**: Basic audit trails, may need custom audit system

### Risk Mitigation Strategies

1. **Custom UI**: Build custom authentication UI using Cognito APIs
2. **Audit Enhancement**: Implement detailed audit logging in Lambda triggers
3. **Backup Strategy**: Export user data regularly for disaster recovery
4. **Multi-Region**: Configure User Pool in multiple regions for HA
5. **Rate Limiting**: Implement custom rate limiting in Lambda triggers

## Session Management

### Token Strategy
```yaml
Access Token (1 hour):
  - Contains user permissions and tenant context
  - Used for API authorization
  - Short-lived for security

ID Token (1 hour):
  - Contains user profile information
  - Used for UI personalization
  - Short-lived for security

Refresh Token (30 days):
  - Used to obtain new access/ID tokens
  - Secure HTTP-only cookie storage
  - Rotation on each use

Session Management:
  - Stateless JWT-based authentication
  - Client-side token refresh handling
  - Logout token revocation
  - Concurrent session limits per user
```

### Security Features
```yaml
Password Policy:
  - Minimum 12 characters
  - Require upper, lower, numbers, symbols
  - Password history: prevent reuse of last 12
  - Account lockout: 5 failed attempts

MFA Configuration:
  - SMS-based MFA (backup)
  - TOTP-based MFA (primary)
  - Recovery codes for backup access
  - Admin override for account recovery

Threat Protection:
  - Adaptive authentication based on risk
  - Block suspicious IP addresses
  - Rate limiting per user account
  - Anomaly detection for login patterns
```

## Integration Implementation

### Frontend Integration (React)
```javascript
// AWS Amplify authentication
import { Auth } from 'aws-amplify';

// Login function
const signIn = async (email, password) => {
  try {
    const user = await Auth.signIn(email, password);
    
    // Handle MFA challenge if required
    if (user.challengeName === 'SMS_MFA') {
      const code = prompt('Enter MFA code:');
      await Auth.confirmSignIn(user, code, 'SMS_MFA');
    }
    
    // Get user session and tokens
    const session = await Auth.currentSession();
    const accessToken = session.getAccessToken().getJwtToken();
    
    // Set authorization header for API calls
    axios.defaults.headers.common['Authorization'] = `Bearer ${accessToken}`;
    
    return user;
  } catch (error) {
    console.error('Login failed:', error);
    throw error;
  }
};

// Auto token refresh
Auth.configure({
  authenticationFlowType: 'USER_SRP_AUTH',
  tokenRefreshInterval: 300000 // 5 minutes
});
```

### API Gateway Integration
```yaml
API Gateway Authorizer:
  Type: COGNITO_USER_POOLS
  Name: shop-management-authorizer
  Provider ARNs: 
    - arn:aws:cognito-idp:us-east-1:123456789012:userpool/us-east-1_AbCdEfGhI
  
Route Authorization:
  /api/shops/*: 
    Authorization: shop-management-authorizer
    Required Scopes: shop:read, shop:write
  /api/products/*:
    Authorization: shop-management-authorizer  
    Required Scopes: product:read, product:write
```

### Database Integration
```sql
-- RLS policy using Cognito context
CREATE POLICY tenant_isolation ON shops
    FOR ALL TO application_user
    USING (tenant_id = current_setting('app.current_tenant')::uuid);

-- Set tenant context from JWT token
SET app.current_tenant = '<tenant_id_from_jwt>';
```

## Multi-Tenant User Management

### Tenant User Isolation
```javascript
// Cognito Pre-SignUp Lambda Trigger
exports.preSignUp = async (event) => {
  const { userAttributes, clientMetadata } = event.request;
  
  // Validate tenant context
  const tenantId = clientMetadata?.tenant_id;
  if (!tenantId) {
    throw new Error('Tenant context required for user registration');
  }
  
  // Check tenant user limits
  const userCount = await getUserCountForTenant(tenantId);
  const tenantLimits = await getTenantLimits(tenantId);
  
  if (userCount >= tenantLimits.maxUsers) {
    throw new Error('Tenant user limit exceeded');
  }
  
  // Set custom attributes
  event.response.userAttributes = {
    ...userAttributes,
    'custom:tenant_id': tenantId,
    'custom:user_role': clientMetadata.role || 'SHOP_EMPLOYEE'
  };
  
  return event;
};
```

### Cross-Tenant Access Prevention
```javascript
// Authorization validation
const validateTenantAccess = (userTenantId, resourceTenantId) => {
  if (userTenantId !== resourceTenantId) {
    throw new Error('Cross-tenant access denied');
  }
};

// API endpoint example
app.get('/api/shops/:shopId', authorize('shop:read'), async (req, res) => {
  const { shopId } = req.params;
  const { tenant_id } = req.user;
  
  const shop = await Shop.findById(shopId);
  
  // Additional tenant validation (belt and suspenders with RLS)
  validateTenantAccess(tenant_id, shop.tenant_id);
  
  res.json(shop);
});
```

## Cost Analysis

### Cognito Pricing Breakdown
```yaml
Monthly Active Users (MAU) Pricing:
  First 50,000 MAU: Free
  Next 50,000 MAU (50K-100K): $0.0055 per MAU
  Next 900,000 MAU (100K-1M): $0.0046 per MAU

Example Costs:
  10,000 users: $0/month
  50,000 users: $0/month  
  75,000 users: $137.50/month (25K × $0.0055)
  100,000 users: $275/month (50K × $0.0055)

Additional Features:
  Advanced Security: $0.05 per MAU
  SMS MFA: $0.15 per message
  Voice MFA: $0.15 per message

Estimated Monthly Cost at Scale:
  100K users with basic features: $275/month
  100K users with advanced security: $5,275/month
  SMS costs (10% MFA usage): ~$150/month
```

### Cost Comparison
```yaml
Solution Comparison (100K users):
  Custom JWT: ~$100/month (infrastructure only, high dev cost)
  Auth0: ~$2,000/month
  AWS Cognito: ~$425/month (with advanced security + SMS)
  Firebase Auth: ~$600/month
  
Winner: AWS Cognito (best value with AWS integration)
```

## Monitoring & Alerting

### Key Metrics
```yaml
Authentication Metrics:
  - Login success/failure rates
  - MFA adoption rates  
  - Password reset frequency
  - Token refresh patterns
  - Concurrent session counts

Security Metrics:
  - Failed login attempts per user/IP
  - Suspicious authentication patterns
  - Cross-tenant access attempts
  - Token validation failures
  - Account lockout events
```

### CloudWatch Alerts
```yaml
Critical Alerts:
  - Authentication failure rate > 10%
  - Cross-tenant access attempts detected
  - Massive login failures from single IP
  - Cognito service errors

Warning Alerts:
  - High MFA failure rate
  - Unusual login patterns
  - Token refresh failures
  - Account lockout threshold reached
```

## Compliance & Security

### Audit Requirements
```javascript
// Enhanced audit logging in Lambda triggers
const auditLog = async (event, action, details) => {
  const logEntry = {
    timestamp: new Date().toISOString(),
    action,
    userId: event.request.userAttributes.sub,
    tenantId: event.request.userAttributes['custom:tenant_id'],
    ipAddress: event.request.clientMetadata?.ipAddress,
    userAgent: event.request.clientMetadata?.userAgent,
    details,
    source: 'cognito-trigger'
  };
  
  // Send to CloudWatch Logs + S3 for long-term retention
  await logToCloudWatch(logEntry);
  await logToS3(logEntry);
};
```

### Data Protection
```yaml
GDPR Compliance:
  - User consent tracking in custom attributes
  - Data portability via Cognito export APIs
  - Right to erasure via user deletion
  - Data minimization in user attributes

PCI DSS Compliance:
  - No payment data stored in user attributes
  - Strong authentication for payment access
  - Audit trails for all authentication events
  - Network isolation and encryption
```

## Success Metrics

### Performance Targets
- Authentication response time: < 500ms 95th percentile
- Token validation: < 50ms 95th percentile
- User registration: < 2 seconds 95th percentile
- Password reset: < 30 seconds end-to-end

### Security Targets
- Account takeover rate: < 0.01%
- MFA adoption: > 80% for admin roles
- Password compliance: > 95%
- Cross-tenant access attempts: 0

### Cost Targets
- Authentication cost per user per month: < $0.01
- Total authentication costs: < 5% of infrastructure costs

## Related Decisions

* ADR-001: Multi-tenant Architecture (affects user isolation)
* ADR-003: Database Technology (affects RLS integration)
* ADR-005: Frontend Framework (affects SDK integration)

## References

* [AWS Cognito User Pools Documentation](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html)
* [Cognito Lambda Triggers](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-overview.html)
* [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)