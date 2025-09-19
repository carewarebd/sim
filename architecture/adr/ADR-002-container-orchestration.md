# ADR-002: Container Orchestration Platform

**Status**: Accepted  
**Date**: 2024-01-01  
**Deciders**: Platform Team  
**Technical Story**: Choose container orchestration for scalable microservices

## Context

The shop management system requires a container orchestration platform that can:
- Scale automatically based on demand (10-200 requests/sec)
- Provide high availability and fault tolerance
- Minimize operational overhead
- Support CI/CD deployment pipelines
- Integrate well with AWS services
- Handle both API services and background workers

## Decision Drivers

* **Operational Overhead**: Minimize server management and maintenance
* **Auto-scaling**: Automatic scaling based on CPU, memory, and custom metrics
* **Cost Efficiency**: Pay only for resources actually used
* **AWS Integration**: Native integration with other AWS services
* **Deployment Velocity**: Fast, reliable deployments with rollback capability
* **Monitoring**: Rich metrics and observability
* **Security**: Container isolation and network security

## Options Considered

### Option 1: Amazon EKS (Kubernetes)
**Description**: Managed Kubernetes service on AWS

**Pros**:
- Industry standard container orchestration
- Powerful scaling and scheduling capabilities
- Rich ecosystem and tooling
- Multi-cloud portability
- Advanced networking (Istio, etc.)
- Comprehensive monitoring options

**Cons**:
- High operational complexity
- Steep learning curve
- Control plane costs ($0.10/hour = $73/month)
- Worker node management required
- Over-engineered for simple applications

**Cost Analysis**: 
- EKS Control Plane: $73/month
- Worker Nodes (3 × t3.medium): $100/month
- **Total**: ~$173/month base cost

### Option 2: Amazon ECS with EC2
**Description**: ECS with self-managed EC2 instances

**Pros**:
- AWS native container service
- Lower learning curve than Kubernetes
- Good AWS service integration
- Fine-grained instance control
- No control plane costs

**Cons**:
- EC2 instance management required
- Patching and maintenance overhead
- Capacity planning complexity
- Underutilized resources during low traffic

**Cost Analysis**:
- EC2 Instances (2 × t3.medium): $67/month
- ELB: $22/month  
- **Total**: ~$89/month base cost

### Option 3: Amazon ECS Fargate
**Description**: Serverless container platform

**Pros**:
- Zero server management
- Automatic scaling
- Pay per actual usage
- Built-in security isolation
- No capacity planning needed
- Fast deployment times

**Cons**:
- Higher per-vCPU/GB costs
- Less control over underlying infrastructure
- Cold start latency (minimal for long-running services)
- Limited customization options

**Cost Analysis**:
- Base workload (2 API + 1 worker): $248/month
- Scales automatically with demand
- **Total**: $248/month (variable with usage)

### Option 4: AWS Lambda
**Description**: Serverless functions for API endpoints

**Pros**:
- Ultimate serverless - no containers to manage
- Automatic scaling to zero
- Pay per request
- Built-in high availability

**Cons**:
- 15-minute execution limit
- Cold start latency
- Limited runtime environments
- Complex for stateful applications
- Vendor lock-in

**Cost Analysis**:
- Estimated 10M requests/month: $20/month
- **Total**: Very low cost but architectural constraints

## Decision

**Chosen Option**: **Option 3 - Amazon ECS Fargate**

### Rationale

1. **Serverless Benefits**: Zero server management eliminates operational overhead
2. **Auto-scaling**: Scales automatically based on demand without pre-provisioning
3. **Cost Efficiency**: Pay only for resources actually used, not idle capacity
4. **AWS Integration**: Native integration with ALB, CloudWatch, IAM, VPC
5. **Security**: Built-in container isolation and network security
6. **Development Velocity**: Fast deployments without infrastructure concerns
7. **Monitoring**: Rich CloudWatch metrics and AWS X-Ray integration

### Implementation Architecture

```yaml
ECS Cluster: shop-management-cluster
Services:
  - shop-management-api (public subnet, ALB)
  - shop-management-worker (private subnet)
  - shop-management-scheduler (private subnet)

Task Definitions:
  API Service:
    CPU: 0.5 vCPU (512 CPU units)
    Memory: 1 GB (1024 MB)
    Desired Count: 2
    Max Count: 10
    
  Worker Service:
    CPU: 0.25 vCPU (256 CPU units)  
    Memory: 0.5 GB (512 MB)
    Desired Count: 1
    Max Count: 5

Auto Scaling Policies:
  - Target CPU Utilization: 70%
  - Target Memory Utilization: 80%
  - Custom metrics: Request count, response time
```

## Consequences

### Positive Consequences

* **Zero Server Management**: No EC2 instances to patch, monitor, or maintain
* **Automatic Scaling**: Handles traffic spikes without manual intervention
* **Cost Optimization**: Pay only for actual compute usage, not idle capacity
* **Fast Deployments**: New versions deploy in 2-3 minutes with rolling updates
* **Built-in Security**: Task isolation, VPC networking, IAM integration
* **Observability**: Native CloudWatch metrics, logs, and distributed tracing

### Negative Consequences

* **Higher Unit Costs**: ~40% more expensive per vCPU-hour than EC2
* **Less Control**: Cannot customize underlying infrastructure
* **AWS Lock-in**: Fargate is AWS-specific, limits multi-cloud options
* **Resource Limits**: Maximum 4 vCPU and 30 GB memory per task
* **Networking**: More complex networking compared to EC2-based solutions

### Risk Mitigation

1. **Cost Management**: Implement detailed CloudWatch billing alarms
2. **Resource Optimization**: Right-size tasks based on actual usage patterns
3. **Multi-AZ Deployment**: Ensure high availability across availability zones
4. **Monitoring**: Comprehensive monitoring for performance and cost optimization
5. **Escape Hatch**: Can migrate to ECS + EC2 if cost becomes prohibitive

## Performance Characteristics

### Expected Performance
- **Cold Start**: < 30 seconds for new tasks
- **Scaling Speed**: New tasks ready in 2-3 minutes
- **Resource Efficiency**: 95%+ CPU utilization possible
- **Network Performance**: Up to 10 Gbps networking

### Scaling Behavior
```yaml
Traffic Pattern: 50 req/sec → 200 req/sec → 50 req/sec
Current Tasks: 2 → 8 → 2 (over 10 minutes)
Cost Impact: $248/month → $992/month → $248/month
```

## Operational Considerations

### Deployment Strategy
- **Blue/Green Deployments**: Zero-downtime deployments with ECS service updates
- **Health Checks**: Application Load Balancer health checks with custom endpoints
- **Rollback**: Automatic rollback on failed health checks
- **Circuit Breaker**: Fail fast and isolate failures

### Monitoring & Alerting
```yaml
CloudWatch Metrics:
  - CPUUtilization > 80% for 5 minutes
  - MemoryUtilization > 85% for 5 minutes
  - Service unhealthy task count > 0
  - Deployment failures

Custom Metrics:
  - API response time > 2000ms
  - Error rate > 1%
  - Background job queue depth
```

### Security Configuration
```yaml
Network Security:
  - Private subnets for workers
  - Security groups with least privilege
  - VPC endpoints for AWS services

Container Security:
  - Non-root container execution
  - Read-only root filesystem
  - Resource limits enforced
  - Secrets via AWS Parameter Store
```

## Integration Points

### AWS Service Integration
* **Application Load Balancer**: Traffic distribution and health checks
* **CloudWatch**: Metrics, logs, and alarms
* **IAM**: Task roles with least privilege access
* **Parameter Store**: Secure configuration management
* **VPC**: Network isolation and security groups

### CI/CD Integration
* **GitHub Actions**: Automated builds and deployments
* **ECR**: Container image registry with vulnerability scanning
* **CodeDeploy**: Blue/green deployment orchestration

## Cost Optimization Strategies

### Immediate Optimizations
1. **Right-sizing**: Monitor actual resource usage and adjust task definitions
2. **Reserved Capacity**: Use Savings Plans for predictable workloads (20% savings)
3. **Spot Capacity**: Use Fargate Spot for fault-tolerant batch workloads (70% savings)

### Long-term Optimizations
1. **Multi-region**: Consider regional pricing differences
2. **Hybrid Approach**: Use EC2 for baseline capacity, Fargate for bursts
3. **Container Optimization**: Optimize Docker images for size and startup time

## Success Metrics

### Performance Metrics
- API response time: < 200ms 95th percentile
- Deployment time: < 5 minutes
- Auto-scaling response time: < 3 minutes
- Service availability: > 99.9%

### Cost Metrics
- Infrastructure cost per request: < $0.001
- Cost predictability: ±10% monthly variance
- Resource utilization: > 70% average CPU/memory

## Related Decisions

* ADR-001: Multi-tenant Architecture (affects scaling strategy)
* ADR-003: Database Technology (impacts container networking)
* ADR-005: Monitoring Strategy (CloudWatch vs third-party)

## References

* [AWS Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
* [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
* [Container Security Best Practices](https://aws.amazon.com/blogs/containers/)