variable location {
  type = string
  default = "australiaeast"
}

variable hostname {
  type = string
  default = "vault"
}

variable description {
  type = string
  default = "Vault deployment resources"
}

variable cluster_size {
  type = number
  default = 5
}

variable deployment_name {
  type = string
  default = "vault"
}

variable admin_username {
  type = string
  default = "grant"
}

variable server_size {
  type = string
  default = "Standard_F2"
}

variable public_key_location {
  type = string
  default = "~/.ssh/id_rsa.pub"
}
