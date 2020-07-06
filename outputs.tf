output vault_url {
  value = "http://${aws_route53_record.this.fqdn}:8200"
}