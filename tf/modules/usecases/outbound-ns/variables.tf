variable name {
  type = string
  description = "Name of the NAT to be created. It will be used as part of resource names."
}

variable day0 {
  description = "Object containing all necessary data from day0 remote state. Common for all usecase modules."
}

variable elb {
  description = "URL of network load balancer forwarding rule to be used for natting"
}
