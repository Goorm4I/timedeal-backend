output "alb_sg_id"    { value = aws_security_group.alb.id }
output "spring_sg_id" { value = aws_security_group.spring.id }
output "redis_sg_id"  { value = aws_security_group.redis.id }
output "rds_sg_id"    { value = aws_security_group.rds.id }
output "mockpg_sg_id" { value = aws_security_group.mockpg.id }
output "k6_sg_id"     { value = aws_security_group.k6.id }
