output public_ips {
  value = azurerm_linux_virtual_machine.this.*.public_ip_address
}

output vault_url {
  value = "http://${aws_route53_record.this.fqdn}:8200"
}