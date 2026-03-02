output "instance_ids"  { value = aws_instance.k6[*].id }
output "public_ips"    { value = aws_instance.k6[*].public_ip }
