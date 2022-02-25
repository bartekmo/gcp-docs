# Design choices and options for FGT ref arch

## Static vs. Dynamic addresses
Static addresses are required:
- for the hasync interface as the peer IP address needs to be explicitly provided in FGT config
- for any interface with secondary ip (see Probing)
- for SDN connector failover (does not apply)

Dynamic addresses:
- provide flexibility when deploying to existing VPCs
- require less configuration changes in FGT
- require using loopback interface and VIP forwarding for probes

### Choice
Static IP only for hasync interface, others left to dynamic.


## Probing
Available probe response options:
1. probes are forwarded by FGT using VIP to the backend server. Response is sent by backend
1. probes are forwarded by FGT using VIP to a loopback interface. Response is sent by FGT
1. probes are responded using secondaryip on FGT interface.

### Choice
Probes are forwarded to loopback for response.
