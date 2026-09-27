

variable "server_name" {
  description = "defines the name of the machine to use"
  type        = string
}

variable "location" {
  description = "location of the resource"
  type        = string
}

variable "resource_group" {
  description = "defines the RG of the machine to use"
  type        = string
}

variable "nic0_subnetid" {
  description = "NICs subnet ID"
  type        = string
}

variable "pubip" {
  description = "Assign public ip or not"
  default     = false
}

variable "storage_account" {
  description = "Diagnostics Storage Account"
  default     = null
}

variable "userpassword" {
  description = "Windows Admin Password"
  default     = false
}

variable "adsetup" {
  description = "Whether setup an ADC controller or nah!"
  default     = false
}

variable "size" {
  description = "Machine SKU size for VM"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "publisher" {
  description = "Image Publisher"
  type        = string
  default     = "MicrosoftWindowsServer"
}

variable "offer" {
  description = "Image Offer"
  type        = string
  default     = "windowsServer"
}

variable "sku" {
  description = "Image SKU"
  type        = string
  default     = "2022-datacenter-smalldisk-g2"
}

variable "image_version" {
  description = "Image version"
  type        = string
  default     = "latest"
}
