## Testing Power Events

With something as complex as an OpenShift cluster, testing power events can be a challenge, especially if the UPS being used is also looking after other devices, and the cluster is being used to host important workloads. 

The following is a simple approach to configure a virtual/dummy UPS on the NUT server, and configure the crowsnest container to connect to it just as if it is a real UPS. No actual UPS required.

Whilst connected, we can use standard NUT UPS commands (`upsc` and `upsrw`) to interatively change the dummy UPS status, causing it to report power events which are captured and acted upon by the crowsnest container.

The default configuration of `upsmon` provided with CrowsNest, recognises and reacts to transitions to the three most important states/flags. ONLINE (UPS Online), ONBATT (UPS On Battery) and LOWBATT (UPS Low Battery). With `usprw` we can dynamically transition the dummy UPS between these states.

Obviously when using the dummy UPS, there is no battery runtime to reduce or load to apply, however when a UPS reports the LOWBATT state, NUT initiates a Full Shutdown (FSD) event to all attached clients, so by connecting a client to the dummy UPS and transitioning the dummy UPS to LOWBATT, we can cause any connected client to initiate shutdown.

Be aware that most UPSes have a built in delay variable (`ups.delay.shutdown`) that delays the Full Shutdown command by a few of seconds (eg 20). Equally many UPSes have adjustable battery and runtime notification levels (`battery.charge.low`, `battery.charge.warning` and `battery.runtime.low`) you can set to fit your specific needs. 
 
### Setup NUT

This guide assumes you have a NUT server setup and configured. If you don't, head over to https://networkupstools.org/ and get one setup. NUT has very low resource needs, and low end SMCs like the Raspberry Pi Zero are perfectly sufficient. 

Once up and running, add a dummy UPS. I won't detail how here, but a set of known working NUT config files for a dummy UPS are included in `ups-tests` which can be merged with your existing setup.

### Prepare CrowsNest

- Deploy crowsnest to your OpenShift cluster
- Verify crowsnest is connected to your NUT server and dummy ups (check in NUT logs)
- Open a terminal on your nut server
- Watch the crowsnest logs (`oc logs -f crowsnest-xxxxx -n crowsnest` or using the webui)

To raise a power event, use `upsrw` to directly edit the dummy UPS variables, and raise UPS flags. Crowsnest will then depending upon the criticality of the flag, simply log the event, or initiate host shutdown.

### Transition states

Set the dummy UPS to be ONLINE (ups.status=OL)

```shell
% upsrw -s ups.status=OL -u admin -p admin apc-dummy@localhost
OK
```

```shell
UPS apc-dummy@localhost on line power

════════════════════════════════════════════════════════════
  CrowsNest UPS Notification
════════════════════════════════════════════════════════════
  Type:      ONLINE
  UPS:       apc-dummy@localhost
  Time:      2026-01-10 02:06:10 UTC
────────────────────────────────────────────────────────────
[2026-01-10 02:06:10] [DEBUG] NOTIFYTYPE=ONLINE
[2026-01-10 02:06:10] [DEBUG] Message: UPS apc-dummy@localhost on line power
[2026-01-10 02:06:10] [DEBUG] UPSNAME=apc-dummy@localhost
[2026-01-10 02:06:10] [INFO] ⚡ POWER RESTORED: UPS apc-dummy@localhost on line power
[2026-01-10 02:06:10] [INFO] UPS is back on line power - normal operation resumed
════════════════════════════════════════════════════════════
```

Transition to ONBATT (ups.status=OB)

```shell
% upsrw -s ups.status=OB -u admin -p admin apc-dummy@localhost
OK
```

```shell
UPS apc-dummy@localhost on battery
[WARN] Host filesystem not mounted at /host - logging to stdout only

════════════════════════════════════════════════════════════
  CrowsNest UPS Notification
════════════════════════════════════════════════════════════
  Type:      ONBATT
  UPS:       apc-dummy@localhost
  Time:      2026-01-10 02:06:00 UTC
────────────────────────────────────────────────────────────
[2026-01-10 02:06:00] [DEBUG] NOTIFYTYPE=ONBATT
[2026-01-10 02:06:00] [DEBUG] Message: UPS apc-dummy@localhost on battery
[2026-01-10 02:06:00] [DEBUG] UPSNAME=apc-dummy@localhost
[2026-01-10 02:06:00] [WARN] 🔋 ON BATTERY: UPS apc-dummy@localhost on battery
[2026-01-10 02:06:00] [WARN] Power failure detected - running on UPS battery
[2026-01-10 02:06:00] [WARN] Monitor battery level - shutdown will occur if power is not restored
════════════════════════════════════════════════════════════
```

Transition to LOWBATT (ups.status=LB)


```shell
UPS apc-dummy@localhost battery is low
[WARN] Host filesystem not mounted at /host - logging to stdout only

════════════════════════════════════════════════════════════
  CrowsNest UPS Notification
════════════════════════════════════════════════════════════
  Type:      LOWBATT
  UPS:       apc-dummy@localhost
  Time:      2026-01-10 02:12:45 UTC
────────────────────────────────────────────────────────────
[2026-01-10 02:12:45] [DEBUG] NOTIFYTYPE=LOWBATT
[2026-01-10 02:12:45] [DEBUG] Message: UPS apc-dummy@localhost battery is low
[2026-01-10 02:12:45] [DEBUG] UPSNAME=apc-dummy@localhost
[2026-01-10 02:12:45] [CRITICAL] ⚠️  LOW BATTERY: UPS apc-dummy@localhost battery is low
[2026-01-10 02:12:45] [CRITICAL] UPS battery critically low - system shutdown is imminent!
[2026-01-10 02:12:45] [CRITICAL] Save all work immediately - power will be lost soon
════════════════════════════════════════════════════════════
```