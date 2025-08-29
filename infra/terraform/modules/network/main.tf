# Network Module - VPC, Subnets, and Networking Components

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "default" {
  count   = var.use_custom_vpc ? 0 : 1
  default = true
}

data "aws_subnets" "default" {
  count = var.use_custom_vpc ? 0 : 1
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

locals {
  # Use provided AZs or select first 3 available
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # VPC configuration
  vpc_id = var.use_custom_vpc ? aws_vpc.main[0].id : data.aws_vpc.default[0].id
  
  # Subnet configuration
  private_subnet_ids = var.use_custom_vpc ? aws_subnet.private[*].id : data.aws_subnets.default[0].ids
  public_subnet_ids  = var.use_custom_vpc ? aws_subnet.public[*].id : data.aws_subnets.default[0].ids
}

# Custom VPC (optional)
resource "aws_vpc" "main" {
  count = var.use_custom_vpc ? 1 : 0
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count = var.use_custom_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = var.use_custom_vpc ? length(local.availability_zones) : 0
  
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-public-${count.index + 1}"
    Type = "public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = var.use_custom_vpc ? length(local.availability_zones) : 0
  
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.availability_zones[count.index]
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-private-${count.index + 1}"
    Type = "private"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.use_custom_vpc ? length(local.availability_zones) : 0
  
  domain = "vpc"
  
  depends_on = [aws_internet_gateway.main]
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = var.use_custom_vpc ? length(local.availability_zones) : 0
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  depends_on = [aws_internet_gateway.main]
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}"
  })
}

# Route Tables - Public
resource "aws_route_table" "public" {
  count = var.use_custom_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

# Route Tables - Private
resource "aws_route_table" "private" {
  count = var.use_custom_vpc ? length(local.availability_zones) : 0
  
  vpc_id = aws_vpc.main[0].id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
  })
}

# Route Table Associations - Public
resource "aws_route_table_association" "public" {
  count = var.use_custom_vpc ? length(aws_subnet.public) : 0
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# Route Table Associations - Private
resource "aws_route_table_association" "private" {
  count = var.use_custom_vpc ? length(aws_subnet.private) : 0
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# VPC Endpoints for S3 (cost optimization)
resource "aws_vpc_endpoint" "s3" {
  count = var.use_custom_vpc ? 1 : 0
  
  vpc_id            = aws_vpc.main[0].id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = concat(
    aws_route_table.public[*].id,
    aws_route_table.private[*].id
  )
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-s3-endpoint"
  })
}

# VPC Endpoint for SageMaker Runtime
resource "aws_vpc_endpoint" "sagemaker_runtime" {
  count = var.use_custom_vpc ? 1 : 0
  
  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sagemaker.runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-sagemaker-runtime-endpoint"
  })
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  count = var.use_custom_vpc ? 1 : 0
  
  name_prefix = "${var.project_name}-${var.environment}-vpc-endpoints"
  vpc_id      = aws_vpc.main[0].id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  })
}

# Security Group for SageMaker
resource "aws_security_group" "sagemaker" {
  name_prefix = "${var.project_name}-${var.environment}-sagemaker"
  vpc_id      = local.vpc_id
  
  # Allow HTTPS outbound for model downloads and API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow HTTP outbound for package downloads
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow all outbound for container registry access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-sagemaker-sg"
  })
}

# Data source for current region
data "aws_region" "current" {}