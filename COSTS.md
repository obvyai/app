# Cost Analysis - AWS Image Generation Platform

This document provides detailed cost analysis and optimization strategies for the AWS Image Generation Platform.

## Cost Components

### 1. Compute Costs (Primary Driver)

#### SageMaker Inference Instances

| Instance Type | vCPUs | Memory | GPU | Price/Hour | Use Case |
|---------------|-------|--------|-----|------------|----------|
| ml.g5.xlarge | 4 | 16 GB | 1x A10G (24GB) | $1.006 | Standard workload |
| ml.g5.2xlarge | 8 | 32 GB | 1x A10G (24GB) | $1.515 | Higher throughput |
| ml.g5.4xlarge | 16 | 64 GB | 1x A10G (24GB) | $2.03 | Memory-intensive models |
| ml.g5.12xlarge | 48 | 192 GB | 4x A10G (96GB) | $5.672 | Multi-GPU inference |

*Prices as of 2024 in us-east-1 region*

#### Lambda Functions

| Function | Memory | Avg Duration | Requests/Month | Monthly Cost |
|----------|--------|--------------|----------------|--------------|
| submit-job | 512 MB | 200ms | 1,000 | $0.42 |
| get-job | 256 MB | 50ms | 5,000 | $0.52 |
| callback | 512 MB | 500ms | 1,000 | $1.05 |

### 2. Storage Costs

#### S3 Storage

| Bucket | Purpose | Size (GB) | Storage Class | Monthly Cost |
|--------|---------|-----------|---------------|--------------|
| Images | Generated images | 100 | Standard | $2.30 |
| Inference Input | Job inputs | 10 | Standard | $0.23 |
| Inference Output | Raw outputs | 50 | Standard → IA (30d) | $1.15 → $0.64 |
| Artifacts | Model artifacts | 20 | Standard | $0.46 |

#### DynamoDB

| Table | RCU | WCU | Storage (GB) | Monthly Cost |
|-------|-----|-----|--------------|--------------|
| Jobs | 5 | 5 | 1 | $2.50 |

### 3. Network Costs

| Service | Data Transfer | Monthly Cost |
|---------|---------------|--------------|
| CloudFront | 100 GB | $8.50 |
| API Gateway | 1M requests | $3.50 |
| S3 → Internet | 50 GB | $4.50 |

### 4. Other Services

| Service | Configuration | Monthly Cost |
|---------|---------------|--------------|
| Cognito | 1,000 MAU | $5.50 |
| CloudWatch | Logs + Metrics | $5.00 |
| SNS | 10,000 notifications | $0.50 |
| KMS | 1,000 requests | $1.00 |

## Cost Scenarios

### Scenario 1: Light Usage (50 jobs/month)

**Assumptions:**
- 50 image generation jobs per month
- Average 2 minutes per job (including cold start)
- ml.g5.xlarge instance
- Scale-to-zero enabled

| Component | Calculation | Monthly Cost |
|-----------|-------------|--------------|
| **SageMaker Compute** | 50 jobs × 2 min × $1.006/60 | **$1.68** |
| Lambda Functions | 200 invocations | $0.50 |
| S3 Storage | 10 GB images | $0.23 |
| DynamoDB | Minimal usage | $2.50 |
| CloudFront | 5 GB transfer | $0.43 |
| Other Services | Cognito, CloudWatch, etc. | $8.00 |
| **Total** | | **~$13.34** |

### Scenario 2: Medium Usage (500 jobs/month)

**Assumptions:**
- 500 image generation jobs per month
- Average 1.5 minutes per job (warmer instances)
- ml.g5.xlarge instance
- Some concurrent usage

| Component | Calculation | Monthly Cost |
|-----------|-------------|--------------|
| **SageMaker Compute** | 500 jobs × 1.5 min × $1.006/60 | **$12.58** |
| Lambda Functions | 2,000 invocations | $2.00 |
| S3 Storage | 50 GB images | $1.15 |
| DynamoDB | Moderate usage | $3.00 |
| CloudFront | 25 GB transfer | $2.13 |
| Other Services | Cognito, CloudWatch, etc. | $10.00 |
| **Total** | | **~$30.86** |

### Scenario 3: Heavy Usage (5,000 jobs/month)

**Assumptions:**
- 5,000 image generation jobs per month
- Average 1 minute per job (mostly warm instances)
- ml.g5.xlarge instance
- High concurrency, multiple instances

| Component | Calculation | Monthly Cost |
|-----------|-------------|--------------|
| **SageMaker Compute** | 5,000 jobs × 1 min × $1.006/60 | **$83.83** |
| Lambda Functions | 20,000 invocations | $8.00 |
| S3 Storage | 200 GB images | $4.60 |
| DynamoDB | Heavy usage | $10.00 |
| CloudFront | 100 GB transfer | $8.50 |
| Other Services | Cognito, CloudWatch, etc. | $15.00 |
| **Total** | | **~$129.93** |

### Scenario 4: Real-time Mode (Always-on)

**Assumptions:**
- 1 ml.g5.xlarge instance running 24/7
- 1,000 jobs/month with low latency
- No cold start delays

| Component | Calculation | Monthly Cost |
|-----------|-------------|--------------|
| **SageMaker Compute** | 730 hours × $1.006 | **$734.38** |
| Lambda Functions | 4,000 invocations | $2.00 |
| S3 Storage | 100 GB images | $2.30 |
| DynamoDB | Moderate usage | $5.00 |
| CloudFront | 50 GB transfer | $4.25 |
| Other Services | Cognito, CloudWatch, etc. | $12.00 |
| **Total** | | **~$759.93** |

## Cost Optimization Strategies

### 1. Instance Right-sizing

#### Performance vs Cost Trade-offs

| Instance Type | Jobs/Hour | Cost/Job | Best For |
|---------------|-----------|----------|----------|
| ml.g5.xlarge | 30 | $0.034 | Standard workloads |
| ml.g5.2xlarge | 40 | $0.038 | Higher throughput |
| ml.g5.4xlarge | 45 | $0.045 | Memory-intensive models |

**Recommendation:** Start with ml.g5.xlarge and scale up based on actual performance needs.

### 2. Auto-scaling Configuration

```hcl
# Optimal auto-scaling settings
min_capacity = 0  # Scale to zero when idle
max_capacity = 10 # Adjust based on peak demand
target_value = 70 # CPU utilization target

# Scale-down policy
scale_down_cooldown = 300  # 5 minutes
scale_up_cooldown = 60     # 1 minute
```

### 3. Storage Optimization

#### S3 Lifecycle Policies

```hcl
lifecycle_configuration {
  rule {
    id     = "optimize_costs"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    expiration {
      days = 365
    }
  }
}
```

**Savings:** Up to 40% on storage costs after 30 days.

### 4. Network Optimization

#### CloudFront Caching

```hcl
# Optimize cache behavior
default_cache_behavior {
  cache_policy_id = "optimized-caching"
  ttl = 86400  # 24 hours for images
}
```

**Savings:** Reduce origin requests by 80-90%.

### 5. Reserved Instances (For Predictable Workloads)

| Commitment | Discount | Break-even (hours/month) |
|------------|----------|--------------------------|
| 1 Year | 40% | 292 hours |
| 3 Year | 60% | 175 hours |

**Use Case:** If running >300 hours/month consistently, consider Reserved Instances.

## Budget Controls

### 1. AWS Budgets Configuration

```hcl
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filters = {
    Service = [
      "Amazon SageMaker",
      "AWS Lambda",
      "Amazon S3",
      "Amazon CloudFront"
    ]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
```

### 2. Cost Anomaly Detection

```hcl
resource "aws_ce_anomaly_detector" "service_monitor" {
  name         = "${var.project_name}-anomaly-detector"
  monitor_type = "DIMENSIONAL"
  
  specification = jsonencode({
    Dimension = "SERVICE"
    MatchOptions = ["EQUALS"]
    Values = ["Amazon SageMaker"]
  })
}
```

### 3. Rate Limiting

```hcl
# API Gateway throttling
throttle_settings {
  rate_limit  = 100  # requests per second
  burst_limit = 200  # burst capacity
}

# Per-user limits in Lambda
const RATE_LIMIT_PER_USER = 10; // jobs per hour
```

## Monitoring and Alerts

### 1. Cost Monitoring Dashboard

Key metrics to track:
- SageMaker instance hours
- Lambda invocation count and duration
- S3 storage growth
- Data transfer costs
- Cost per job

### 2. Automated Alerts

```hcl
resource "aws_cloudwatch_metric_alarm" "high_cost" {
  alarm_name          = "high-sagemaker-cost"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.daily_cost_threshold
  alarm_description   = "This metric monitors daily SageMaker costs"
  
  dimensions = {
    Currency    = "USD"
    ServiceName = "AmazonSageMaker"
  }
}
```

## Cost Optimization Checklist

### Daily
- [ ] Monitor active SageMaker endpoints
- [ ] Check for stuck or long-running jobs
- [ ] Review CloudWatch cost metrics

### Weekly
- [ ] Analyze job patterns and optimize scaling
- [ ] Review S3 storage growth
- [ ] Check for unused resources

### Monthly
- [ ] Review budget vs actual costs
- [ ] Analyze cost per job trends
- [ ] Optimize instance types based on usage
- [ ] Review and adjust lifecycle policies

## Emergency Cost Controls

### 1. Circuit Breaker Pattern

```typescript
// Implement in Lambda functions
const MAX_DAILY_SPEND = process.env.MAX_DAILY_SPEND || 100;

if (await getCurrentDailySpend() > MAX_DAILY_SPEND) {
  throw new Error('Daily spend limit exceeded');
}
```

### 2. Auto-shutdown

```hcl
# CloudWatch event to stop endpoints during off-hours
resource "aws_cloudwatch_event_rule" "stop_endpoints" {
  name                = "stop-sagemaker-endpoints"
  description         = "Stop SageMaker endpoints during off-hours"
  schedule_expression = "cron(0 22 * * ? *)"  # 10 PM UTC
}
```

## ROI Calculations

### Break-even Analysis

For a SaaS offering:
- **Cost per image:** $0.034 (ml.g5.xlarge, 2-minute job)
- **Suggested pricing:** $0.10 per image
- **Gross margin:** 66%
- **Break-even:** 150 images/month (covers fixed costs)

### Scaling Economics

| Monthly Volume | Cost per Image | Total Cost | Revenue (@ $0.10) | Profit |
|----------------|----------------|------------|-------------------|--------|
| 1,000 | $0.034 | $34 | $100 | $66 |
| 10,000 | $0.031 | $310 | $1,000 | $690 |
| 100,000 | $0.028 | $2,800 | $10,000 | $7,200 |

*Economies of scale due to reduced cold starts and fixed cost amortization*

## Conclusion

The platform is designed for cost efficiency with scale-to-zero capabilities. Key cost drivers are:

1. **SageMaker compute time** (60-80% of total cost)
2. **Data transfer** (10-15% of total cost)
3. **Storage and other services** (10-15% of total cost)

**Recommendations:**
- Start with async mode and scale-to-zero
- Monitor usage patterns and optimize instance types
- Implement comprehensive budget controls
- Consider Reserved Instances for predictable workloads >300 hours/month