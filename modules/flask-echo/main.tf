# Add IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "flask-echo-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create CloudWatch log group
resource "aws_cloudwatch_log_group" "flask_echo" {
  name              = "/ecs/flask-echo"
  retention_in_days = 30
}

# Create CloudWatch Log Group for ALB logs
resource "aws_cloudwatch_log_group" "alb_logs" {
  name              = "/aws/alb/flask-echo"
  retention_in_days = 30
}

# Create ALB
resource "aws_lb" "flask_echo" {
  name               = "flask-echo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "flask-echo-alb"
  }
}

# Create ALB target group
resource "aws_lb_target_group" "flask_echo" {
  name        = "flask-echo-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher            = "200"
    path               = "/"
    port               = "traffic-port"
    timeout            = 5
    unhealthy_threshold = 3
  }
}

# Create ALB listener
resource "aws_lb_listener" "flask_echo" {
  load_balancer_arn = aws_lb.flask_echo.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_echo.arn
  }
}

# Create security group for ALB
resource "aws_security_group" "alb" {
  name        = "flask-echo-alb-sg-${formatdate("YYYYMMDDHHmm", timestamp())}"
  description = "Security group for Flask Echo ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Add Secrets Manager policy to the task execution role
resource "aws_iam_role_policy" "secrets_access" {
  name = "flask-echo-secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:datadog-api-key-*",
          "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:datadog-app-key-*"
        ]
      }
    ]
  })
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Create IAM role for ECS tasks (Datadog permissions)
resource "aws_iam_role" "ecs_task_role" {
  name = "flask-echo-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Add ECS permissions for Datadog agent
resource "aws_iam_role_policy" "datadog_permissions" {
  name = "flask-echo-datadog-permissions"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:ListContainerInstances",
          "ecs:DescribeContainerInstances",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
      }
    ]
  })
}

# Add ECR pull permissions to the task execution role
resource "aws_iam_role_policy" "ecr_access" {
  name = "flask-echo-ecr-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:us-east-1:058264373862:repository/generic/repo"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# Update container port mapping and task definition
resource "aws_ecs_task_definition" "flask_echo" {
  family                   = "flask-echo"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = 256
  memory                  = 512
  execution_role_arn      = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "flask-echo"
      image = var.container_image
      
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f -s -w '%%{http_code}' http://localhost:5000/ | grep -q 200 || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.flask_echo.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name  = "datadog-agent"
      image = "public.ecr.aws/datadog/agent:latest"
      essential = false

      portMappings = [
        {
          containerPort = 8126
          hostPort      = 8126
          protocol      = "tcp"
        },
        {
          containerPort = 8125
          hostPort      = 8125
          protocol      = "udp"
        }
      ]

      environment = [
        {
          name  = "DD_LOGS_ENABLED"
          value = "true"
        },
        {
          name  = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL"
          value = "true"
        },
        {
          name  = "DD_AC_EXCLUDE"
          value = "name:datadog-agent"
        },
        {
          name  = "ECS_FARGATE"
          value = "true"
        },
        {
          name  = "DD_SITE"
          value = "datadoghq.com"
        },
        {
          name  = "DD_SERVICE"
          value = "flask-echo"
        },
        {
          name  = "DD_ENV"
          value = "production"
        },
        {
          name  = "DD_ECS_COLLECT_RESOURCE_TAGS_EC2"
          value = "true"
        },
        {
          name  = "DD_ECS_COLLECT_RESOURCE_TAGS_ECS"
          value = "true"
        },
        {
          name  = "DD_ECS_FARGATE"
          value = "true"
        },
        {
          name  = "DD_CLUSTER_NAME"
          value = "flask-echo-cluster"
        },
        {
          name  = "DD_PROCESS_AGENT_ENABLED"
          value = "true"
        },
        {
          name  = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC"
          value = "true"
        },
        {
          name  = "DD_APM_NON_LOCAL_TRAFFIC"
          value = "true"
        },
        {
          name  = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL"
          value = "true"
        },
        {
          name  = "DD_CONTAINER_EXCLUDE_LOGS"
          value = "name:datadog-agent"
        },
        {
          name  = "DD_LOGS_CONFIG_ALB_LOGS_ENABLED"
          value = "true"
        },
        {
          name  = "DD_LOGS_CONFIG_ALB_LOG_GROUP"
          value = aws_cloudwatch_log_group.alb_logs.name
        },
        {
          name  = "DD_APM_ENABLED"
          value = "true"
        },
        {
          name  = "DD_APM_PORT"
          value = "8126"
        }
      ]

      # Add secrets from AWS Secrets Manager
      secrets = [
        {
          name      = "DD_API_KEY"
        #   valueFrom = "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:datadog-api-key"
          valueFrom = "arn:aws:secretsmanager:us-east-1:058264373862:secret:datadog-api-key-f491aP"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.flask_echo.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "datadog"
        }
      }
    }
  ])
}

# Update security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "flask-echo-sg-${formatdate("YYYYMMDDHHmm", timestamp())}"
  description = "Security group for Flask Echo service"
  vpc_id      = var.vpc_id
  
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Add ingress rule for Datadog agent
  ingress {
    from_port       = 8126
    to_port         = 8126
    protocol        = "tcp"
    self            = true
    description     = "Datadog trace agent"
  }

  ingress {
    from_port       = 8125
    to_port         = 8125
    protocol        = "udp"
    self            = true
    description     = "Datadog DogStatsD"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "flask-echo-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Update ECS service to use ALB
resource "aws_ecs_service" "flask_echo" {
  name            = "flask-echo"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.flask_echo.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  depends_on = [aws_lb_listener.flask_echo]

  load_balancer {
    target_group_arn = aws_lb_target_group.flask_echo.arn
    container_name   = "flask-echo"
    container_port   = 5000
  }
}

# Update CloudWatch Logs permissions for Datadog task role
resource "aws_iam_role_policy" "datadog_cloudwatch" {
  name = "datadog-cloudwatch-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = [
          # Add permissions for both ALB and ECS logs
          aws_cloudwatch_log_group.alb_logs.arn,
          "${aws_cloudwatch_log_group.alb_logs.arn}:*",
          aws_cloudwatch_log_group.flask_echo.arn,
          "${aws_cloudwatch_log_group.flask_echo.arn}:*"
        ]
      }
    ]
  })
}

# Create IAM role for Lambda
resource "aws_iam_role" "lambda_datadog_forwarder" {
  name = "lambda-datadog-forwarder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Add permissions for Lambda to read from S3 and write to CloudWatch Logs
resource "aws_iam_role_policy" "lambda_datadog_forwarder" {
  name = "lambda-datadog-forwarder-policy"
  role = aws_iam_role.lambda_datadog_forwarder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Create Lambda deployment package
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/lambda/main.py"
  output_path = "${path.module}/lambda/function.zip"
}

# Create Lambda function using Datadog's forwarder
resource "aws_lambda_function" "datadog_forwarder" {
  filename         = "${path.module}/lambda/function.zip"
  function_name    = "datadog-forwarder"
  role            = aws_iam_role.lambda_datadog_forwarder.arn
  handler         = "main.lambda_handler"
  runtime         = "python3.8"
  timeout         = 120
  memory_size     = 1024

  environment {
    variables = {
      DD_API_KEY = data.aws_secretsmanager_secret_version.datadog_api_key.secret_string
      DD_SITE    = "datadoghq.com"
      DD_TAGS    = "env:production,service:flask-echo"
    }
  }

  source_code_hash = data.archive_file.lambda_package.output_base64sha256
}

# Create CloudWatch Log subscription for ALB logs
resource "aws_cloudwatch_log_subscription_filter" "datadog_alb" {
  name            = "datadog-alb-logs"
  log_group_name  = aws_cloudwatch_log_group.alb_logs.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.datadog_forwarder.arn
}

# Create CloudWatch Log subscription for ECS logs
resource "aws_cloudwatch_log_subscription_filter" "datadog_ecs" {
  name            = "datadog-ecs-logs"
  log_group_name  = aws_cloudwatch_log_group.flask_echo.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.datadog_forwarder.arn
}

# Update Lambda permissions to allow CloudWatch
resource "aws_lambda_permission" "cloudwatch_alb" {
  statement_id  = "AllowCloudWatchALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.datadog_forwarder.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.alb_logs.arn}:*"
}

resource "aws_lambda_permission" "cloudwatch_ecs" {
  statement_id  = "AllowCloudWatchECS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.datadog_forwarder.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.flask_echo.arn}:*"
}

# Get Datadog API key from Secrets Manager
data "aws_secretsmanager_secret_version" "datadog_api_key" {
  secret_id = "datadog-api-key"
}

module "datadog_logs" {
  source = "../datadog-log-forwarder"

  name_prefix     = "flask-echo"
  aws_region      = "us-east-1"
  aws_account_id  = data.aws_caller_identity.current.account_id
  datadog_api_key = data.aws_secretsmanager_secret_version.datadog_api_key.secret_string
  datadog_tags    = "env:production,service:flask-echo"
  
  log_group_names = [
    aws_cloudwatch_log_group.alb_logs.name,
    aws_cloudwatch_log_group.flask_echo.name
  ]
} 