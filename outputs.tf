output public_ips {
  value = azurerm_linux_virtual_machine.this.*.public_ip_address
}