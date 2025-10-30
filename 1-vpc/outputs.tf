output "vpc_id" {
  value = aws_vpc.gj_lab_vpc.id
}

output "public_subnet_ids" {
  value = [
    aws_subnet.public_2a.id,
    aws_subnet.public_2c.id,
  ]
}

output "private_subnet_ids" {
  value = [
    aws_subnet.private_2a.id,
    aws_subnet.private_2c.id,
  ]
}
