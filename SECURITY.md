# Security Documentation

## Overview

This document outlines the security architecture, controls, and best practices implemented in the AWS Image Generation Platform. The platform follows AWS security best practices and implements defense-in-depth strategies.

## Security Architecture

### Identity and Access Management (IAM)

#### Principle of Least Privilege
All IAM roles and policies are designed with minimal required permissions:

**Lambda Execution Roles**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:region:account:table/jobs-table"
    }
  ]
}
```

**SageMaker Execution Role**:
- S3 access limited to specific buckets
- SNS publish permissions for callbacks only
- No cross-account access

#### Service-to-Service Authentication
- IAM roles for service authentication
- No long-term credentials stored
- Temporary credentials via STS

### Data Protection

#### Encryption at Rest
**S3 Buckets**:
- SSE-KMS encryption with customer-managed keys
- Bucket policies prevent unencrypted uploads
- Versioning enabled for critical buckets

**DynamoDB**:
- Encryption at rest with KMS
- Point-in-time recovery enabled
- Backup encryption with same KMS key

**KMS Key Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow service access",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "s3.amazonaws.com",
          "dynamodb.amazonaws.com",
          "sagemaker.amazonaws.com"
        ]
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Encryption in Transit
- TLS 1.2+ for all API communications
- HTTPS-only CloudFront distribution
- VPC endpoints for internal service communication

### Network Security

#### VPC Configuration
**Custom VPC (Production)**:
- Private subnets for SageMaker instances
- Public subnets for NAT gateways only
- VPC endpoints for AWS services

**Security Groups**:
```hcl
resource "aws_security_group" "sagemaker" {
  name_prefix = "sagemaker-sg"
  vpc_id      = var.vpc_id
  
  # HTTPS outbound only
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # No inbound rules - SageMaker doesn't need them
}
```

#### Web Application Firewall (WAF)
**Protection Rules**:
- Rate limiting: 2000 requests per 5 minutes per IP
- AWS Managed Core Rule Set
- SQL injection protection
- Cross-site scripting (XSS) protection

**WAF Configuration**:
```hcl
resource "aws_wafv2_web_acl" "main" {
  name  = "api-protection"
  scope = "REGIONAL"
  
  rule {
    name     = "RateLimitRule"
    priority = 1
    
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    action {
      block {}
    }
  }
}
```

### Authentication and Authorization

#### Amazon Cognito User Pools
**Configuration**:
- Email-based authentication
- Strong password policy
- Account lockout after failed attempts
- MFA support (optional)

**Password Policy**:
```hcl
password_policy {
  minimum_length                   = 12
  require_uppercase                = true
  require_lowercase                = true
  require_numbers                  = true
  require_symbols                  = true
  temporary_password_validity_days = 7
}
```

#### JWT Token Validation
**API Gateway Authorizer**:
- JWT signature verification
- Token expiration validation
- Audience and issuer validation
- User context extraction

### Input Validation and Sanitization

#### Request Validation
**Zod Schema Validation**:
```typescript
const SubmitJobRequestSchema = z.object({
  prompt: z.string()
    .min(1, 'Prompt cannot be empty')
    .max(1000, 'Prompt too long')
    .refine(val => !containsMaliciousContent(val)),
  steps: z.number()
    .int()
    .min(1)
    .max(50),
  // ... other validations
});
```

#### Content Filtering
- Prompt content validation
- File type restrictions for uploads
- Size limits for all inputs
- SQL injection prevention

### Logging and Monitoring

#### Security Event Logging
**CloudWatch Logs**:
- All API requests logged
- Authentication events tracked
- Failed access attempts recorded
- Structured logging with correlation IDs

**Log Format**:
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "requestId": "abc-123",
  "userId": "user-456",
  "action": "submit-job",
  "sourceIP": "192.168.1.1",
  "userAgent": "Mozilla/5.0...",
  "status": "success"
}
```

#### Security Monitoring
**CloudWatch Alarms**:
- High error rates
- Unusual access patterns
- Failed authentication attempts
- Cost anomalies

**AWS GuardDuty** (Optional):
- Threat detection
- Malicious IP monitoring
- Compromised instance detection

### Vulnerability Management

#### Container Security
**SageMaker Container**:
- Base image vulnerability scanning
- Regular security updates
- Minimal attack surface
- Non-root user execution

**ECR Image Scanning**:
```hcl
resource "aws_ecr_repository" "model" {
  name                 = "sagemaker-model"
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
}
```

#### Dependency Management
- Regular dependency updates
- Vulnerability scanning in CI/CD
- Security advisory monitoring
- Automated patching where possible

### Incident Response

#### Detection
1. **Automated Monitoring**:
   - CloudWatch alarms
   - AWS Config rules
   - GuardDuty findings

2. **Manual Monitoring**:
   - Security dashboard reviews
   - Log analysis
   - Cost anomaly investigation

#### Response Procedures
1. **Immediate Response**:
   - Isolate affected resources
   - Revoke compromised credentials
   - Block malicious traffic

2. **Investigation**:
   - Collect and preserve evidence
   - Analyze attack vectors
   - Assess impact scope

3. **Recovery**:
   - Restore from clean backups
   - Apply security patches
   - Update security controls

4. **Post-Incident**:
   - Document lessons learned
   - Update procedures
   - Implement preventive measures

### Compliance and Governance

#### Data Privacy
**GDPR Compliance**:
- User consent management
- Data portability support
- Right to deletion implementation
- Privacy by design principles

**Data Retention**:
- Automatic data expiration (TTL)
- User data deletion on request
- Audit trail preservation
- Backup encryption

#### Security Assessments
**Regular Reviews**:
- Quarterly security assessments
- Annual penetration testing
- Continuous vulnerability scanning
- Third-party security audits

### Secure Development Practices

#### Code Security
**Static Analysis**:
- ESLint security rules
- Dependency vulnerability scanning
- Secret detection in commits
- Infrastructure security scanning

**CI/CD Security**:
```yaml
- name: Security Scan
  run: |
    npm audit --audit-level high
    checkov -d infra/terraform
    git-secrets --scan
```

#### Infrastructure Security
**Terraform Security**:
- Checkov policy scanning
- TFLint rule validation
- State file encryption
- Remote state locking

### Security Configuration Checklist

#### AWS Account Security
- [ ] Root account MFA enabled
- [ ] CloudTrail logging enabled
- [ ] Config rules configured
- [ ] GuardDuty enabled (optional)
- [ ] Security Hub enabled (optional)

#### Network Security
- [ ] VPC with private subnets
- [ ] Security groups with minimal access
- [ ] NACLs configured appropriately
- [ ] VPC Flow Logs enabled
- [ ] WAF rules implemented

#### Data Protection
- [ ] S3 bucket encryption enabled
- [ ] DynamoDB encryption enabled
- [ ] KMS key rotation enabled
- [ ] Backup encryption configured
- [ ] SSL/TLS certificates valid

#### Access Control
- [ ] IAM roles follow least privilege
- [ ] No hardcoded credentials
- [ ] Service-to-service authentication
- [ ] User authentication via Cognito
- [ ] API authorization implemented

#### Monitoring
- [ ] CloudWatch alarms configured
- [ ] Security event logging enabled
- [ ] Cost monitoring active
- [ ] Incident response procedures documented
- [ ] Regular security reviews scheduled

### Security Contacts

**Security Team**: security@example.com
**Incident Response**: incident-response@example.com
**Compliance**: compliance@example.com

### Security Updates

This document should be reviewed and updated:
- After security incidents
- During architecture changes
- Quarterly security reviews
- When new threats are identified

**Last Updated**: [Current Date]
**Next Review**: [Quarterly]
**Document Owner**: Security Team