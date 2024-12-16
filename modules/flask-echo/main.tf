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
  name        = "flask-echo-alb-sg"
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

# Update container port mapping and task definition
resource "aws_ecs_task_definition" "flask_echo" {
  family                   = "flask-echo"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = 256
  memory                  = 512
  execution_role_arn      = aws_iam_role.ecs_task_execution.arn

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
        command     = ["CMD-SHELL", "curl -f http://localhost:5000/ || exit 1"]
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
        }
      ]

      # Add secrets from AWS Secrets Manager
      secrets = [
        {
          name      = "DD_API_KEY"
          valueFrom = "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:datadog-api-key"
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
resource "aws_security_group" "flask_echo" {
  name        = "flask-echo-sg"
  description = "Security group for Flask Echo service"
  vpc_id      = var.vpc_id
  
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
    security_groups = [aws_security_group.flask_echo.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.flask_echo.arn
    container_name   = "flask-echo"
    container_port   = 5000
  }
} 