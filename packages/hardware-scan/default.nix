# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This is a temporary solution for hardware detection.
#
{
  writeShellApplication,
  util-linux,
  pciutils,
  dmidecode,
  ...
}:
writeShellApplication {
  name = "hardware-scan";
  runtimeInputs = [
    util-linux
    pciutils
    dmidecode
  ];
  text = ''
        detect_system_info() {
        # Use dmidecode to get the SKU
        system_manufacturer=$(sudo dmidecode -s system-manufacturer)
        system_version=$(sudo dmidecode -s system-version)
        system_product_name=$(sudo dmidecode -s system-product-name)
        system_sku_number=$(sudo dmidecode -s system-sku-number)
        system_name="$system_manufacturer $system_version"
        system_sku="$system_sku_number $system_product_name"
    }

    detect_network_devices() {
        # Search for network wifi card using lspci
        network_devices=()
        while IFS= read -r line; do
            network_devices+=("$line")
        done <<< "$(lspci -nn | grep -i network)"

        # Check if any network device found
        if [ ''${#network_devices[@]} -eq 0 ]; then
            echo "No network device found."
            exit 1
        fi

        # Display the available network devices
        if [ ''${#network_devices[@]} -gt 1 ]; then
            echo "Multiple network devices found. Please select one:"
            for i in "''${!network_devices[@]}"; do
                echo "$i. ''${network_devices[$i]}"
            done

            # Prompt the user to select a network device
            read -r -p "Enter the number of the network device you want to select: " network_choice

            # Validate the user's choice
            if ! [[ "$network_choice" =~ ^[0-9]+$ ]] || [ "$network_choice" -lt 0 ] || [ "$network_choice" -ge ''${#network_devices[@]} ]; then
                echo "Invalid choice. Please enter a valid number."
                exit 1
            fi

            # Select the chosen network device
            network_device="''${network_devices[$network_choice]}"
        else
            # Only one network device found, select it automatically
            network_device="''${network_devices[0]}"
        fi

        # Extract vendorId and productId from the input
        wifi_pci_bus_number=$(echo "$network_device" | awk '{print $1}')
        wifi_vendor_id=$(echo "$network_device" | sed -E 's/.*\[([0-9a-fA-F]+):.*/\1/')
        wifi_product_id=$(echo "$network_device" | sed -E 's/.*\[([0-9a-fA-F]+)\].*/\1/')
    }

    detect_gpu_devices () {
        # Search for GPU using lspci
        gpu_devices=()
        while IFS= read -r line; do
            gpu_devices+=("$line")
        done <<< "$(lspci -nn | grep -i vga)"

        # Check if any GPU device found
        if [ ''${#gpu_devices[@]} -eq 0 ]; then
            echo "No GPU device found."
            exit 1
        fi

        # Display the available GPU devices
        if [ ''${#gpu_devices[@]} -gt 1 ]; then
            echo "Multiple GPU devices found. Please select one:"
            for i in "''${!gpu_devices[@]}"; do
                echo "$i. ''${gpu_devices[$i]}"
            done

            # Prompt the user to select a GPU device
            read -r -p "Enter the number of the GPU device you want to select: " gpu_choice

            # Validate the user's choice
            if ! [[ "$gpu_choice" =~ ^[0-9]+$ ]] || [ "$gpu_choice" -lt 0 ] || [ "$gpu_choice" -ge ''${#gpu_devices[@]} ]; then
                echo "Invalid choice. Please enter a valid number."
                exit 1
            fi

            # Select the chosen GPU device
            gpu_device="''${gpu_devices[$gpu_choice]}"
        else
            # Only one GPU device found, select it automatically
            gpu_device="''${gpu_devices[0]}"
        fi

        # Extract vendorId and productId from the input
        gpu_pci_bus_number=$(echo "$gpu_device" | awk '{print $1}')
        gpu_vendor_id=$(echo "$gpu_device" | sed -E 's/.*\[([0-9a-fA-F]+):.*/\1/')
        gpu_product_id=$(echo "$gpu_device" | sed -E 's/.*\[([0-9a-fA-F]+)\].*/\1/')
    }

    detect_input_devices() {
        # Search for events using ls
        input_events=()
        while IFS= read -r line; do
            input_events+=("$line")
        done <<< "$(ls /dev/input/event*)"

        # Use udevadm to iterate through input_events and determine devices
        keyboard_devices=()
        mouse_devices=()
        touch_devices=()
        for event in "''${input_events[@]}"; do
            device_info=$(udevadm info --query=all --name="$event")
            if [[ $device_info =~ ID_INPUT_KEYBOARD=1 ]]; then
                keyboard_devices+=("$event")
            fi
            if [[ $device_info =~ ID_INPUT_MOUSE=1 ]]; then
                mouse_devices+=("$event")
            fi
            if [[ $device_info =~ ID_INPUT_TOUCHPAD=1 ]]; then
                touch_devices+=("$event")
            fi
        done

        # Check if any keyboard device found
        if [ ''${#keyboard_devices[@]} -eq 0 ]; then
            echo "No keyboard device found."
            exit 1
        fi

        # Check if any mouse device found
        if [ ''${#mouse_devices[@]} -eq 0 ]; then
            echo "No mouse device found."
            exit 1
        fi

        if [ ''${#touch_devices[@]} -eq 0 ]; then
            echo "No touchpad device found."
        fi

        # Use udevadm to determine keyboard devices
        keyboard_devlinks=()
        for event in "''${keyboard_devices[@]}"; do
            device_info=$(udevadm info "$event")
            devlink=$(echo "$device_info" | grep "DEVLINKS" | awk -F "=" '{print $2}')
            keyboard_devlinks+=("$devlink")
        done

        # Use udevadm to determine mouse devices
        mouse_devlinks=()
        mouse_attr_names=()
        for event in "''${mouse_devices[@]}"; do
            device_info=$(udevadm info "$event")
            IFS=' ' read -r -a devlinks <<< "$(echo "$device_info" | grep "DEVLINKS" | awk -F "=" '{print $2}')"
            devlink=''${devlinks[0]}
            mouse_devlinks+=("$devlink")
            mouse_attr_name=$(udevadm info -a "$devlink" | grep "ATTRS{name}" | head -1 | awk -F "==" '{print $2}')
            mouse_attr_names+=("''${mouse_attr_name}")
        done

        # Use udevadm to determine touchpad devices
        touch_devlinks=()
        touch_attr_names=()
        for event in "''${touch_devices[@]}"; do
            device_info=$(udevadm info "$event")
            IFS=' ' read -r -a devlinks <<< "$(echo "$device_info" | grep "DEVLINKS" | awk -F "=" '{print $2}')"
            devlink=''${devlinks[0]}
            touch_devlinks+=("$devlink")
            touch_attr_name=$(udevadm info -a "$devlink" | grep "ATTRS{name}" | head -1 | awk -F "==" '{print $2}')
            touch_attr_names+=("''${touch_attr_name}")
        done

    }

    # Run detection functions
    detect_system_info
    detect_network_devices
    detect_gpu_devices
    detect_input_devices
    echo "''${mouse_devlinks[@]}"
    echo "''${mouse_attr_names[@]}"
    echo "''${touch_devlinks[@]}"
    echo "''${touch_attr_names[@]}"

    # Write the hardware-configuration.nix file

    cat << EOF > hardware-configuration.nix
    {
        # System
        name = "$system_name";
        sku = "$system_sku";

        # Passthrough WiFi card
        network.pciDevices = [
            {
                path = "0000:$wifi_pci_bus_number";
                vendorId = "$wifi_vendor_id";
                productId = "$wifi_product_id";
                name = "wlp0s5f0";
            }
        ];

        # Passthrough GPU
        gpu.pciDevices = [
            {
                path = "0000:$gpu_pci_bus_number";
                vendorId = "$gpu_vendor_id";
                productId = "$gpu_product_id";
            }
        ];

        virtioInputHostEvdevs = [
            "/dev/mouse"
            "/dev/touchpad"
        ];

        mouse = [
        ]
    }
    EOF
  '';

  meta = {
    description = "Helper script making Hardware discovery easier";
    platforms = [
      "x86_64-linux"
    ];
  };
}
