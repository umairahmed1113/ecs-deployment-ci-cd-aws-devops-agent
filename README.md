# ADVENTURE 🏔️

A static HTML travel & tourism website containerized with Docker and deployed to AWS ECS Fargate via a fully automated CI/CD pipeline, monitored by AWS DevOps Agent for autonomous incident investigation.

---

## 🏗️ Architecture

```
GitHub → CodePipeline → CodeBuild → ECR → ECS Fargate → ALB
                                              ↑
                              EventBridge → Lambda → AWS DevOps Agent
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Application | Static HTML / CSS / JS |
| Web server | Nginx 1.27 on Alpine Linux |
| Container registry | Amazon ECR |
| Container runtime | ECS Fargate (serverless) |
| Load balancer | Application Load Balancer (ALB) |
| Source control | GitHub via CodeStar Connection |
| Build | AWS CodeBuild |
| Pipeline | AWS CodePipeline |
| AIOps | AWS DevOps Agent |
| Event routing | Amazon EventBridge + AWS Lambda |

---

## 📁 Project Structure

```
adventure/
├── index.html
├── site.webmanifest
├── Dockerfile
├── .dockerignore
├── buildspec.yml
├── css/
│   ├── style.css
│   └── responsive.css
├── js/
│   └── script.js
└── img/
    ├── mountain.png
    ├── mountain_dark.jpg
    ├── menu-btn.png
    ├── favicon-16x16.png
    ├── favicon-32x32.png
    ├── apple-touch-icon.png
    └── ...
```

---

## 🐳 Docker

### Build & run locally

```bash
# Run from the folder containing index.html
cd /path/to/adventure

docker build -t adventure .
docker run -p 8080:80 adventure
# Open http://localhost:8080
```

### Dockerfile highlights

- Base image: `nginx:1.27-alpine` (~45 MB, fast ECS cold starts)
- Gzip compression enabled for CSS, JS, HTML
- Images/fonts cached for 30 days, CSS/JS for 1 day
- Asset locations use `try_files $uri =404` to prevent rewrite loops
- Build fails fast if `index.html` is not found in the build context

---

## ⚙️ CI/CD Pipeline

### Pipeline stages

| Stage | Provider | Action |
|-------|----------|--------|
| Source | GitHub | Triggers on push to `main` via CodeStar Connection |
| Build | CodeBuild | Runs `buildspec.yml`: docker build → tag → push to ECR |
| Deploy | Amazon ECS | Updates task definition, rolling deployment to Fargate |

### buildspec.yml

```yaml
version: 0.2
phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
  build:
    commands:
      - docker build -t $IMAGE_REPO_NAME:$CODEBUILD_RESOLVED_SOURCE_VERSION .
      - docker tag $IMAGE_REPO_NAME:$CODEBUILD_RESOLVED_SOURCE_VERSION $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_REPO_NAME:latest
  post_build:
    commands:
      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_REPO_NAME:latest
      - printf '[{"name":"adventure","imageUri":"%s"}]' $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_REPO_NAME:latest > imagedefinitions.json
artifacts:
  files: imagedefinitions.json
```

### Required CodeBuild environment variables

| Variable | Description |
|----------|-------------|
| `AWS_ACCOUNT_ID` | Your AWS account ID |
| `AWS_REGION` | e.g. `us-east-1` |
| `IMAGE_REPO_NAME` | ECR repository name e.g. `adventure` |

### Required CodeBuild IAM permissions

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:PutImage",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload"
  ],
  "Resource": "*"
}
```

---

## ☁️ ECS Fargate + ALB

### Task definition settings

| Setting | Value |
|---------|-------|
| Launch type | FARGATE |
| Network mode | awsvpc |
| CPU | 256 (0.25 vCPU) |
| Memory | 512 MB |
| Container port | 80 |
| Log group | `/ecs/adventure` |
| Health check | `curl -f http://localhost/ \|\| exit 1` |

### Networking

- ALB in **public subnets** — accepts HTTP port 80 from `0.0.0.0/0`
- Fargate tasks in **private subnets** — only accept traffic from ALB security group
- NAT Gateway allows tasks to pull images from ECR

### Auto scaling

- Min tasks: 2 / Max tasks: 6
- Scale out trigger: CPU > 70%

---

## 🤖 AWS DevOps Agent

Automatically investigates pipeline failures and infrastructure incidents without any human intervention.

### How automatic investigation works

```
CodePipeline FAILED
       ↓
EventBridge Rule (CodePipeline Pipeline Execution State Change → FAILED)
       ↓
AWS Lambda (devops-agent-webhook-forwarder)
       ↓  computes HMAC-SHA256 signature
DevOps Agent Webhook
       ↓
Auto investigation starts → root cause analysis → Slack notification
```

### Why Lambda is needed

The DevOps Agent webhook requires HMAC-SHA256 signature authentication with two specific headers:
- `x-amzn-event-signature` — `HMAC-SHA256(timestamp:payload, secret)` encoded in Base64
- `x-amzn-event-timestamp` — ISO 8601 timestamp

EventBridge API destinations cannot compute dynamic HMAC signatures, so a Lambda function acts as the bridge.

### Lambda function (devops-agent-webhook-forwarder)

```python
import json, hmac, hashlib, base64, urllib.request, urllib.error
from datetime import datetime, timezone

WEBHOOK_URL = "https://event-ai.us-east-1.api.aws/webhook/generic/{YOUR_WEBHOOK_ID}"
SECRET_KEY  = "{YOUR_WEBHOOK_SECRET}"   # store in AWS Secrets Manager

def lambda_handler(event, context):
    detail    = event.get("detail", {})
    pipeline  = detail.get("pipeline", "unknown")
    state     = detail.get("state", "FAILED")
    exec_id   = detail.get("execution-id", "unknown")
    timestamp = datetime.now(timezone.utc).isoformat()

    payload = {
        "eventType":   "incident",
        "incidentId":  exec_id,
        "action":      "created",
        "priority":    "HIGH",
        "title":       f"CodePipeline {pipeline} FAILED",
        "description": f"Pipeline {pipeline} execution {exec_id} entered state {state}",
        "timestamp":   timestamp,
        "service":     pipeline,
        "data":        {}
    }

    payload_str = json.dumps(payload)
    message     = f"{timestamp}:{payload_str}"
    signature   = base64.b64encode(
        hmac.new(SECRET_KEY.encode(), message.encode("utf-8"), hashlib.sha256).digest()
    ).decode("utf-8")

    req = urllib.request.Request(
        WEBHOOK_URL,
        data=payload_str.encode("utf-8"),
        headers={
            "Content-Type":             "application/json",
            "x-amzn-event-signature":   signature,
            "x-amzn-event-timestamp":   timestamp,
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req) as r:
            return {"statusCode": r.status}
    except urllib.error.HTTPError as e:
        return {"statusCode": e.code}
```

> ⚠️ **Security**: Store `SECRET_KEY` in AWS Secrets Manager and fetch it at runtime — never hardcode it.

### EventBridge rule

| Setting | Value |
|---------|-------|
| Event source | AWS services → CodePipeline |
| Event type | **Pipeline Execution State Change** |
| State filter | FAILED |
| Target | AWS Lambda → `devops-agent-webhook-forwarder` |

### CloudWatch alarms (auto-trigger investigations)

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| `adventure-ecs-cpu-high` | CPUUtilization | > 80% for 2 min |
| `adventure-ecs-memory-high` | MemoryUtilization | > 80% for 2 min |
| `adventure-alb-5xx` | HTTPCode_Target_5XX_Count | Sum > 5 per min |
| `adventure-alb-no-healthy-hosts` | HealthyHostCount | < 1 |
| `adventure-alb-latency` | TargetResponseTime | p99 > 2s for 3 min |

---

## ✅ Setup Checklist

### AWS infrastructure

- [ ] Create ECR repository `adventure`
- [ ] Create ECS cluster, task definition, and service
- [ ] Create VPC with public/private subnets, NAT Gateway, ALB
- [ ] Create GitHub CodeStar Connection (OAuth)
- [ ] Create CodeBuild project with ECR push IAM permissions
- [ ] Create CodePipeline: Source → Build → Deploy

### DevOps Agent

- [ ] Create Agent Space in `us-east-1` DevOps Agent console
- [ ] Generate Agent Space Webhook URL and secret key
- [ ] Store secret key in AWS Secrets Manager
- [ ] Deploy Lambda function `devops-agent-webhook-forwarder`
- [ ] Create EventBridge rule: CodePipeline FAILED → Lambda
- [ ] Create 5 CloudWatch alarms
- [ ] Connect GitHub to Agent Space via OAuth
- [ ] Connect Slack for automatic root cause notifications

---

## 🔑 Key Lessons Learned

- CloudWatch is **not listed** in DevOps Agent Telemetry — it connects automatically via the Agent Space IAM role
- DevOps Agent webhook requires **HMAC-SHA256 signing** — EventBridge alone cannot do this
- A **Lambda function** is required between EventBridge and the DevOps Agent webhook
- EventBridge rule must use `Pipeline Execution State Change` not `Action Execution State Change`
- Always run `docker build` from the folder that **directly contains** `index.html`
- The `error_page 404 /index.html` pattern causes a **500 rewrite loop** for missing assets — use `try_files $uri =404` instead

---

## 📚 Resources

- [AWS DevOps Agent docs](https://docs.aws.amazon.com/devopsagent/latest/userguide/)
- [AWS DevOps Agent pricing](https://aws.amazon.com/devops-agent/pricing/)
- [CodePipeline docs](https://docs.aws.amazon.com/codepipeline/latest/userguide/)
- [ECS Fargate docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [EventBridge docs](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

---

*Built with ❤️ — April 2026*
