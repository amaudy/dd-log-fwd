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

resource "aws_ecs_task_definition" "flask_echo" {
  family                   = "flask-echo"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = 256
  memory                  = 512
  execution_role_arn      = aws_iam_role.ecs_task_execution.arn  # Add execution role ARN
  
  container_definitions = jsonencode([
    {
      name  = "flask-echo"
      image = var.container_image
      
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.flask_echo.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

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
}

resource "aws_security_group" "flask_echo" {
  name        = "flask-echo-sg"
  description = "Security group for Flask Echo service"
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