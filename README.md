# btcfinder
Fun project for creating random bitcoin addresses and looking up their balance.

## 🎯 Overview

The btcfinder is designed for legitimate research purposes, such as:
- Academic research on Bitcoin address patterns
- Blockchain analysis and forensics
- Security research on cryptocurrency systems
- Validation of address generation algorithms

**⚠️ Important:** This tool is intended for educational and research purposes only. Always comply with local laws and regulations when using cryptocurrency-related tools.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Amazon S3     │    │   Amazon ECS    │    │  Amazon ECR     │
│                 │    │                 │    │                 │
│ Target Address  │◄───┤  Rust App       │◄───┤ Docker Image    │
│ List Storage    │    │  (Fargate)      │    │ Repository      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  CloudWatch     │    │   Auto Scaling  │
│  Logs & Metrics │    │   (1-10 tasks)  │
└─────────────────┘    └─────────────────┘
```

## ✨ Features

### Bitcoin Address Generation
- **Multiple Address Types**: P2PKH (Legacy), P2SH-P2WPKH (Nested SegWit), P2WPKH (Native SegWit)
- **Cryptographically Secure**: Uses `secp256k1` for secure key generation
- **High Performance**: Multi-threaded generation with configurable batch sizes

### Cloud-Native Architecture
- **AWS ECS Fargate**: Serverless container deployment
- **Auto Scaling**: Automatically scales 1-10 tasks based on CPU utilization
- **S3 Integration**: Stores target addresses and found matches
- **CloudWatch**: Comprehensive logging and monitoring

### Performance & Monitoring
- **Real-time Statistics**: Addresses/second generation rate
- **Progress Reporting**: Configurable reporting intervals
- **Zero-Downtime Deployments**: Rolling updates with ECS
- **Resource Optimization**: Efficient memory and CPU usage

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Docker installed
- Terraform >= 1.0
- Git

### 1. Clone the Repository

```bash
git clone <repository-url>
cd bitcoin-address-matcher
```

### 2. Deploy Infrastructure

```bash
# Make deployment script executable
chmod +x deploy.sh

# Run full deployment
./deploy.sh
```

This will:
- Deploy AWS infrastructure (ECS, S3, VPC, IAM roles)
- Build and push Docker image to ECR
- Start the ECS service
- Upload a sample target address list

### 3. Monitor the Application

```bash
# View real-time logs
aws logs tail /ecs/bitcoin-address-matcher-dev --follow

# Check service status
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name)
```

## 📁 Project Structure

```
bitcoin-address-matcher/
├── src/
│   └── main.rs              # Main Rust application
├── terraform/
│   └── main.tf              # Infrastructure as Code
├── Dockerfile               # Multi-stage Docker build
├── docker-compose.yml       # Local development setup
├── deploy.sh               # Automated deployment script
├── Cargo.toml              # Rust dependencies
├── .gitignore              # Git ignore patterns
└── README.md               # This file
```

## ⚙️ Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUCKET_NAME` | - | S3 bucket containing target addresses |
| `THREADS` | CPU count | Number of worker threads |
| `BATCH_SIZE` | 1000 | Addresses to generate per batch |
| `NETWORK` | mainnet | Bitcoin network (mainnet/testnet) |
| `REPORT_INTERVAL` | 30 | Progress reporting interval (seconds) |
| `RUST_LOG` | info | Logging level |

### Terraform Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | us-east-1 | AWS region for deployment |
| `environment` | dev | Environment name |
| `desired_count` | 1 | Initial number of ECS tasks |
| `cpu` | 2048 | CPU units per task (1024 = 1 vCPU) |
| `memory` | 4096 | Memory in MB per task |

## 📊 Usage Examples

### Basic Deployment

```bash
# Deploy with defaults
./deploy.sh

# Deploy to specific region
AWS_REGION=eu-west-1 ./deploy.sh
```

### Custom Target Addresses

```bash
# Upload your own address list
aws s3 cp my_addresses.txt s3://$(terraform output -raw s3_bucket_name)/bitcoin_addresses.txt

# Restart service to pick up new addresses
./deploy.sh update
```

### Scaling Operations

```bash
# Scale up to 5 tasks
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 5

# Scale down to 0 (stop processing)
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 0
```

### Local Development

```bash
# Run locally with Docker Compose
docker-compose up

# Run with custom configuration
BUCKET_NAME=my-bucket THREADS=8 docker-compose up
```

## 🔧 Advanced Configuration

### Custom Docker Build

```bash
# Build custom image
docker build -t bitcoin-matcher:custom .

# Run with custom parameters
docker run -e BUCKET_NAME=my-bucket \
           -e THREADS=8 \
           -e BATCH_SIZE=2000 \
           bitcoin-matcher:custom
```

### Infrastructure Customization

Edit `main.tf` to customize:
- Instance types and sizing
- Auto scaling parameters
- Network configuration
- Monitoring settings

```hcl
# Example: High-performance configuration
variable "cpu" {
  default = 4096  # 4 vCPUs
}

variable "memory" {
  default = 8192  # 8 GB RAM
}
```

## 📈 Monitoring & Observability

### CloudWatch Dashboards

The application provides comprehensive monitoring through:

- **Application Logs**: Real-time address generation statistics
- **ECS Metrics**: CPU, memory, and task health
- **Auto Scaling Events**: Scale up/down activities
- **S3 Access Logs**: Target list download activities

### Key Metrics to Monitor

| Metric | Description | Threshold |
|--------|-------------|-----------|
| CPU Utilization | Task processing load | < 80% |
| Memory Utilization | RAM usage | < 90% |
| Task Count | Running instances | 1-10 |
| Generation Rate | Addresses per second | Baseline + 20% |

### Log Analysis

```bash
# View performance statistics
aws logs filter-log-events \
  --log-group-name /ecs/bitcoin-address-matcher-dev \
  --filter-pattern "addresses generated"

# Check for matches found
aws logs filter-log-events \
  --log-group-name /ecs/bitcoin-address-matcher-dev \
  --filter-pattern "MATCH FOUND"
```

## 🛡️ Security Considerations

### AWS Security Best Practices

- **IAM Roles**: Least-privilege access to S3 and CloudWatch
- **VPC**: Isolated network environment
- **Encryption**: S3 server-side encryption enabled
- **Container Security**: Non-root user, minimal base image

### Data Protection

- **Private Keys**: Stored securely in CloudWatch logs
- **Target Addresses**: Encrypted at rest in S3
- **Network Traffic**: TLS encryption for all AWS API calls

### Access Control

```bash
# Restrict S3 bucket access (example policy)
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::ACCOUNT:role/ecs-task-role"},
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::bucket/*", "arn:aws:s3:::bucket"]
    }
  ]
}
```

## 🐛 Troubleshooting

### Common Issues

#### Service Won't Start

```bash
# Check service events
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name) \
  --query 'services[0].events'

# Check task definition
aws ecs describe-task-definition \
  --task-definition bitcoin-address-matcher-dev
```

#### High CPU Usage

```bash
# Check current scaling
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs

# Manually scale if needed
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 3
```

#### S3 Access Issues

```bash
# Verify bucket permissions
aws s3api get-bucket-policy \
  --bucket $(terraform output -raw s3_bucket_name)

# Test S3 access from task
aws ecs execute-command \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task TASK_ID \
  --interactive \
  --command "/bin/bash"
```

### Performance Tuning

#### Optimize for Speed

```bash
# High-performance configuration
THREADS=16 BATCH_SIZE=5000 ./deploy.sh
```

#### Optimize for Cost

```bash
# Cost-optimized configuration
terraform apply -var="cpu=1024" -var="memory=2048" -var="desired_count=1"
```

## 📚 API Reference

### Command Line Arguments

```bash
bitcoin-matcher [OPTIONS]

OPTIONS:
    -b, --bucket <BUCKET>           S3 bucket name [env: BUCKET_NAME]
    -k, --key <KEY>                 S3 object key [default: bitcoin_addresses.txt]
    -t, --threads <THREADS>         Number of worker threads [default: CPU count]
        --batch-size <BATCH_SIZE>   Addresses per batch [default: 1000]
    -n, --network <NETWORK>         Bitcoin network [default: mainnet]
        --report-interval <SECONDS> Progress reporting interval [default: 30]
    -h, --help                      Print help information
    -V, --version                   Print version information
```

### Output Format

When matches are found, they are logged in the following format:

```
🎉 MATCH FOUND! Address: 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa, Type: P2PKH
```

And saved to files as:
```
# Found Bitcoin Addresses
# Generated at: 2025-01-15T10:30:45Z
# Format: Address,PrivateKey(WIF),AddressType

1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa,L4rK1yDtCWekvXuE6oXD9jCYfFNV2cWRpVuPLBcCU2z8TrisoyY1,P2PKH
```

## 💰 Cost Estimation

### AWS Resources Monthly Costs (us-east-1)

| Resource | Configuration | Estimated Cost |
|----------|---------------|----------------|
| ECS Fargate | 1 task, 2 vCPU, 4GB RAM | ~$35/month |
| S3 Storage | 1GB addresses + logs | ~$1/month |
| CloudWatch Logs | 10GB/month retention | ~$5/month |
| Data Transfer | Minimal | ~$2/month |
| **Total** | | **~$43/month** |

### Cost Optimization Tips

- Use Spot pricing for non-critical workloads
- Adjust log retention periods
- Scale down during off-hours
- Use S3 Intelligent Tiering for large address lists

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Setup

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Clone and build
git clone <repo-url>
cd bitcoin-address-matcher
cargo build

# Run tests
cargo test

# Run locally
BUCKET_NAME=test-bucket cargo run
```

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This software is provided for educational and research purposes only. The authors are not responsible for any misuse or damages arising from the use of this software. Always ensure compliance with local laws and regulations when working with cryptocurrency-related tools.

## 🙋 Support

For questions, issues, or feature requests:

1. Check the [Issues](../../issues) page
2. Review the troubleshooting section above
3. Create a new issue with detailed information

---

**Happy address matching! 🚀**