<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.09.3

This patch release is targeted at [Secure Laptop](../scenarios/showcases.md#secure-laptop) (Lenovo X1 Carbon) test participants and brings in new features and bug fixes.

Lenovo X1 Carbon has been fully tested for this release, other platforms have been sanity-tested only.


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.09.3>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus


## What is New in ghaf-24.09.3

Lenovo X1 Carbon Gen 10/11:

  * Chromium was replaced with Google Chrome.
  * Dynamic updates of Microsoft endpoint URLs.
  * Updated GALA version 0.1.30 with SACA[^note1].
  * Bluetooth applet added to the system tray.
  * Auto-reconnect hotplugged devices when the VM restarts.


## Bug Fixes

* NVIDIA Jetson AGX Orin/Orin NX: the taskbar is no longer available.
* Bluetooth notification windows stay on the screen.
* Audio recording is delayed by several seconds.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| Application menu icons are missing in the first boot after the software installation   | In Progress | Workaround: close and re-open the menu, icons will be available again. |
| Some cursor types are missing causing a cursor to disappear in some cases   | In Progress | Will be fixed in ghaf-24.09.4. |
| Cannot open images and PDF files from the file manager   | In Progress | Will be fixed in ghaf-24.09.4. |
| The Control Panel is non-functional apart from the Display Settings   | In Progress | The functionality will be gradually improved in coming releases. |
| Time synchronization between host and VMs does not work in all scenarios   | In Progress | Under investigation. |
| Suspend does not work from the taskbar power menu   | In Progress | Will be fixed in ghaf-24.09.4. |
| VPN credentials are not saved   | On Hold | It is not clear if this can be fixed. |
| The keyboard always boots up with the English layout   | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [archive.vedenemo.dev/ghaf-24.09.3](https://archive.vedenemo.dev/ghaf-24.09.3/).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).


[^note1]: Secure Android Cloud Application
