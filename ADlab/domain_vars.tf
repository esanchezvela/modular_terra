
variable "custom_domain" {
  description = "Domain for controller22"
  default = "AD22.NEWXYZ.SITE"
}

variable "computer_ou" {
  description = "OU to stage the Linux Servers in Domain"
  default = "OU=LINUXSERVERS,OU=SERVERS,DC=AD22,DC=NEWXYZ,DC=SITE"
}

variable "domain_netbios_name" {
  description = "Domain NETBIOS Name"
  default = "OU=AD22NEWXYZ"
}
