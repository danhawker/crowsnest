# CrowsNest
Automated OpenShift Node Power Event Monitoring and Shutdown, using NUT UPS events and k8s GradefulNodeShutdown features.

CrowsNest monitors remote NUT servers for power events and acts accordingly, alerting and/or powering down OpenShift nodes based on the criticality of events raised.

CrowsNest leverages the Network UPS Toolit (NUT), in particular `upsmon` the NUT monitoring and shutdown controller, to monitor the state of a remotely connected UPS, and then act upon any event received.

## Features

- Automated graceful shutdown of OpenShift nodes
- Remote UPS monitoring using NUT upsmon
- Leverages k8s `GracefulNodeShutdown` FeatureGate and Systemd Inhibitor Locks to delay host shutdown
- Configurable host shutdown delay for critical and regular pods
- Configurable drain timeouts and grace periods to fit your node and UPS capacity
- Configurable using existing OpenShift/k8s tools, resources and APIs
- Static Pod or DaemonSet based deployment options


## Limitations

- Privileged pod needed to initiate systemd based `systemctl poweroff`
- Access to the local host filesystem needed by the privileged Pod means using `chroot` 
- `chroot` brings its own challenges when initiating system commands
- Although enabled, `GracefulNodeShutdown` is not documented nor officially supported by Red Hat.
- Very limited shutdown scenarios have been tested.
- Bring Your Own NUT server, no server is provided.


## Installation

CrowsNest can be deployed in two configurations, as a Static Pod or as a DaemonSet.

Why two options? 
Static Pods have few dependencies and do not depend on the k8s API being available, as static pods are managed directly by the Kubelet. They are designed for node critical workloads, which makes them ideal for reacting to power events when the API is not yet availeble, especially useful in single node deployments.

DaemonSets are perfect when you need an agent style service to be identically deployed across all hosts in a cluster. In addition, configuration and deployments use standard k8s/OpenShift approaches, making deployments simpler. This deployment can also help manage power events in a larger cluster environment where events may affect individual or subsets of cluster hosts, rather than all nodes.

### Static Pod

The static pod deployment utilises the MachineConfig Operator to place the required files onto the host. Static Pods cannot call upon other standard k8s resources like ConfigMap or Secret, so any configuration or dependencies must be baked within the cluster or deployed to the host. Due to this, a MachineConfig resource is to be created. As inlining yaml files is an utter ball ache, an openshift Butane file is provided which can embed local files, and output consolidated and validated OpenShift MachineConfig yaml.

Verify each config file, script and yaml file and adjust as necessary to suit your needs.

At a minimum edit...
- Edit `files/crowsnest_config.conf` to target your NUT Server and UPS
- Verify `static-pod/crowsnest-kubeletconfig.yaml` and adjust `shutdownGracePeriod` and `shutdownGracePeriodCriticalPods` to suit your cluster and UPS capacities.

Re-create the merged MachineConfig file to deploy.

```
% cd static-pod
% butane --files-dir ../files crowsnest-mco.bu -o crowsnest-mco.yaml
```

Apply the following yaml files to your cluster individually...
- `static-pod/crowsnest-namespace.yaml`
- `static-pod/crowsnest-kubeletconfig.yaml`
- `static-pod/crowsnest-mco.yaml`

or using oc/kustomize

```
% oc apply -k static-pod/
```

### Daemon Set

The Daemon Set deployment uses standard k8s resources, which makes things much easier.

Verify each config file, script and yaml file and adjust as necessary to suit your needs.

At a minimum edit...
- Edit `files/crowsnest_config.conf` to target your NUT Server and UPS
- Verify `crowsnest-kubeletconfig.yaml` and adjust `shutdownGracePeriod` and `shutdownGracePeriodCriticalPods` to suit your cluster and UPS capacities.

Apply with oc/kustomize

```
% oc apply -k daemonset/
```

## Usage

Once deployed and suitably configured, CrowsNest is mostly admin free.

However, it is worth verifying and tuning the various grace periods and drain timeouts to fit your use case, and ensure that your node(s) shutdown correctly and in sufficient time.


## Improvements aka PR's Welcome!!

- Clean up, fix and rationalise the current shutdown script
- Setup Github actions for container build, test, vuln scanning, cosign sign, etc.
- Reduce need for privileged pod (CAP_SYS_BOOT and other capabilities ought to be enough)
- Test with vanilla k8s
- Test more power event scenarios!!!
- Expand notifycmd to allow other notification methods, eg Slack, AlertManager, etc.
- Re-investigate use of UBI (EPEL nut-client package woes)

## Testing Power Events

See [TESTING.md](ups-tests/TESTING.md)



