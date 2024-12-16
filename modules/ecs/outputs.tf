output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
} 