# Shop Management System - Complete Architecture

This repository contains a comprehensive architecture design for a multi-tenant shop management web application built on AWS.

## Repository Structure

```
architecture/
├── README.md                           # This file - repository overview
├── overview.md                         # High-level system architecture
├── diagram.puml                        # PlantUML architecture diagram
├── diagram.svg                         # Rendered architecture diagram
├── aws-deployment.md                   # AWS deployment patterns and infrastructure
├── infrastructure-iaac.md              # Infrastructure as Code (Terraform)
├── data-model/                         # Database design and schemas
│   ├── er_diagram.puml                 # PlantUML ER diagram
│   ├── schema.sql                      # PostgreSQL schema with RLS
│   └── read-optimized-tables.md        # Denormalization and caching strategy
├── api/                                # API specifications
│   └── openapi.yaml                    # Complete OpenAPI 3.1 specification
├── ui/                                 # Frontend design and components
│   ├── overview.md                     # UI overview and navigation flows
│   └── pages/                          # React TypeScript components
│       ├── Login.tsx                   # Authentication pages
│       ├── DashboardOwner.tsx          # Owner dashboard with KPIs
│       ├── ProductsList.tsx            # Product management
│       ├── ProductEditor.tsx           # Product creation/editing
│       ├── Inventory.tsx               # Inventory management
│       ├── Orders.tsx                  # Order management
│       ├── PublicMarketplace.tsx       # Public marketplace search
│       └── InvoiceViewer.tsx           # Invoice generation and viewing
├── notifications.md                    # Notification system design
├── search.md                          # Product search and marketplace
├── security.md                        # Security, authentication, and authorization
├── cost-estimate/                     # Cost analysis and optimization
│   ├── estimate.md                    # Detailed cost breakdown
│   └── estimate.csv                   # Cost spreadsheet
├── ops/                               # Operations and monitoring
│   └── runbook.md                     # Operational procedures
├── tests/                             # Testing strategy and examples
│   ├── api_contract.postman_collection.json  # API contract tests
│   └── load_test_k6.js                # Load testing scenarios
├── adr/                               # Architecture Decision Records
│   ├── 0001-choose-rds-postgres.md    # Database selection rationale
│   ├── 0002-choose-opensearch.md      # Search engine selection
│   ├── 0003-multi-tenant-shared-schema.md  # Multi-tenancy approach
│   ├── 0004-aws-services-selection.md # Cloud services selection
│   └── 0005-caching-strategy.md       # Caching approach
├── validation_checklist.md            # Validation and quality checks
└── commit-msgs.txt                    # Suggested commit messages
```

## System Overview

This shop management system is designed as a multi-tenant SaaS platform supporting:

- **10,000 shops** (tenants)
- **100,000 registered users**  
- **50,000 monthly active users**
- **4,000 daily orders**
- **Peak load**: 200 requests/sec sustained
- **SLA target**: 99.95% availability

### Key Features

- Multi-tenant architecture with shared schema + row-level security
- Product catalog management with image storage
- Inventory tracking and low-stock alerts
- Order management (pickup and delivery)
- Public marketplace with geospatial search
- Salesperson performance tracking
- Invoice generation (PDF)
- Real-time notifications
- Mobile-responsive web interface

### Technology Stack

- **Frontend**: React + TypeScript + Tailwind CSS
- **Backend**: Node.js/Python APIs (containerized)
- **Database**: PostgreSQL (Amazon Aurora) with read replicas
- **Search**: Amazon OpenSearch for product search
- **Caching**: Redis (ElastiCache)
- **Storage**: Amazon S3 for images and documents
- **Auth**: AWS Cognito
- **Messaging**: SQS + SNS for async processing
- **Hosting**: AWS ECS Fargate + Application Load Balancer
- **CDN**: CloudFront with custom domains

## Getting Started

1. **Review Architecture**: Start with `overview.md` for system design
2. **Database Setup**: Use `data-model/schema.sql` to create PostgreSQL schema
3. **API Integration**: Reference `api/openapi.yaml` for complete API specification
4. **Frontend Components**: Examine `ui/pages/` for React component examples
5. **Infrastructure**: Deploy using Terraform configs in `infrastructure-iaac.md`
6. **Cost Planning**: Review `cost-estimate/` for budget planning
7. **Operations**: Use `ops/runbook.md` for deployment and monitoring

## Validation

Run the validation checklist in `validation_checklist.md` to ensure:
- OpenAPI specification is valid
- SQL schema compiles without errors  
- React components are syntactically correct
- Terraform configurations validate
- Cost estimates include all required services

## Next Steps

See the end of this documentation for a concrete engineering roadmap to implement this architecture.

---

**Architecture Version**: 1.0  
**Last Updated**: September 19, 2025  
**Target AWS Region**: us-east-1  
**Estimated Monthly Cost**: $2,800 - $8,500 (see cost-estimate/)